extends Node

signal facade_surface_ready

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_osm_facade_surface_material.gd")
const EXPECTED_MAX_PALETTE := 6

var _buildings: Array[CSGPolygon3D] = []
var _buildings_root: Node3D = null
var _legacy_materials: Dictionary = {}
var _owned_materials: Dictionary = {}
var _original_transforms: Dictionary = {}
var _original_polygons: Dictionary = {}
var _original_depths: Dictionary = {}
var _materials: Dictionary = {}
var _enhanced_enabled := true
var _ready_complete := false
var _failed := false
var _hero_replacements_touched := 0
var _bind_scheduled := false
var _tearing_down := false

func _ready() -> void:
    _tearing_down = false
    process_mode = Node.PROCESS_MODE_ALWAYS
    _start_watching()
    _schedule_apply()

func _exit_tree() -> void:
    _tearing_down = true
    _bind_scheduled = false
    _stop_watching()
    _release_material_ownership()
    _buildings_root = null

func _start_watching() -> void:
    if _tearing_down or not is_inside_tree():
        return
    var tree := get_tree()
    if tree == null:
        return
    if not tree.node_added.is_connected(_on_node_added):
        tree.node_added.connect(_on_node_added)
    if not tree.node_removed.is_connected(_on_node_removed):
        tree.node_removed.connect(_on_node_removed)

func _stop_watching() -> void:
    var tree := get_tree()
    if tree == null:
        return
    if tree.node_added.is_connected(_on_node_added):
        tree.node_added.disconnect(_on_node_added)
    if tree.node_removed.is_connected(_on_node_removed):
        tree.node_removed.disconnect(_on_node_removed)

func _palette_key(material: Material) -> String:
    if material is StandardMaterial3D:
        var standard := material as StandardMaterial3D
        var color := standard.albedo_color
        return "%0.4f:%0.4f:%0.4f:%0.4f" % [color.r, color.g, color.b, standard.roughness]
    return ""

func _shared_material_for(material: Material) -> ShaderMaterial:
    var key := _palette_key(material)
    if key.is_empty():
        return null
    if _materials.has(key):
        return _materials[key] as ShaderMaterial
    var standard := material as StandardMaterial3D
    var shared := MATERIAL_FACTORY.create_material(standard.albedo_color, standard.roughness)
    shared.set_meta("legacy_palette_key", key)
    _materials[key] = shared
    return shared

func _is_production_scene(node: Node) -> bool:
    if not node is Node3D:
        return false
    var candidate := node as Node3D
    return candidate.has_node("BrusselsOSM") and candidate.has_node("UrbISMidiExact")

func _is_authoritative_production_scene(node: Node) -> bool:
    if not _is_production_scene(node) or not is_inside_tree():
        return false
    var candidate := node as Node3D
    var tree := get_tree()
    if tree == null:
        return false
    if tree.current_scene == candidate:
        return true
    var parent := candidate.get_parent()
    if parent == tree.root:
        return true
    # Preserve the already-gated root-level Viewport -> Main contract while
    # rejecting arbitrary nested anchor clones under foreign scene owners.
    return str(candidate.name) == "Main" and parent is Viewport and parent.get_parent() == tree.root

func _valid_buildings_root(node: Node) -> bool:
    if not node is Node3D or str(node.name) != "GeneratedBuildings":
        return false
    var osm := node.get_parent()
    if osm == null or str(osm.name) != "BrusselsOSM":
        return false
    return _is_authoritative_production_scene(osm.get_parent())

func _find_existing_buildings_root() -> Node3D:
    if _tearing_down or not is_inside_tree():
        return null
    var tree := get_tree()
    if tree == null:
        return null
    # One bounded recursive recovery covers legitimate test/editor mounts where
    # production main is already nested below a root-level SubViewport before this
    # autoload gets a useful mount event. Discovery may be recursive, authority is not.
    for candidate: Node in tree.root.find_children("GeneratedBuildings", "Node3D", true, false):
        if _valid_buildings_root(candidate):
            return candidate as Node3D
    return null

func _on_node_added(node: Node) -> void:
    if _tearing_down or not is_inside_tree() or _ready_complete or _failed:
        return
    if _valid_buildings_root(node):
        _schedule_apply()

func _on_node_removed(node: Node) -> void:
    if _tearing_down or not is_inside_tree() or _failed:
        return
    if _buildings_root == null or node != _buildings_root:
        return
    _release_material_ownership()
    _buildings_root = null
    _ready_complete = false
    _bind_scheduled = false
    _start_watching()
    call_deferred("_try_apply")

func _schedule_apply() -> void:
    if _tearing_down or not is_inside_tree() or _bind_scheduled or _ready_complete or _failed:
        return
    _bind_scheduled = true
    call_deferred("_try_apply")

func _release_material_ownership() -> void:
    for building: CSGPolygon3D in _buildings:
        if not is_instance_valid(building):
            continue
        var instance_id := building.get_instance_id()
        var owned := _owned_materials.get(instance_id) as Material
        var baseline := _legacy_materials.get(instance_id) as Material
        if owned != null and baseline != null and building.material == owned:
            building.material = baseline
        if str(building.get_meta("material_family", "")) == MATERIAL_FACTORY.MATERIAL_FAMILY:
            building.remove_meta("material_family")
            if str(building.get_meta("environment_role", "")) == "generic_osm_building_wall":
                building.remove_meta("environment_role")
            if str(building.get_meta("placement_provenance", "")) == "OpenStreetMap contributors via Overpass API":
                building.remove_meta("placement_provenance")
            if str(building.get_meta("license", "")) == "ODbL-1.0":
                building.remove_meta("license")
            if building.has_meta("building_material_claimed") and not bool(building.get_meta("building_material_claimed")):
                building.remove_meta("building_material_claimed")
            if building.has_meta("geometry_changed_by_facade_surface_runtime") and not bool(building.get_meta("geometry_changed_by_facade_surface_runtime")):
                building.remove_meta("geometry_changed_by_facade_surface_runtime")
    _buildings.clear()
    _legacy_materials.clear()
    _owned_materials.clear()
    _original_transforms.clear()
    _original_polygons.clear()
    _original_depths.clear()
    _materials.clear()

func _fail(message: String) -> void:
    if _tearing_down:
        return
    push_error("Brussels OSM facade surface runtime: %s" % message)
    _failed = true
    _ready_complete = true
    _stop_watching()

func _try_apply() -> void:
    _bind_scheduled = false
    if _tearing_down or not is_inside_tree() or _ready_complete or _failed:
        return
    var buildings_root := _find_existing_buildings_root()
    if buildings_root == null:
        return

    var candidates: Array[CSGPolygon3D] = []
    for child: Node in buildings_root.get_children():
        if child is CSGPolygon3D and str(child.name).begins_with("Building_"):
            candidates.append(child as CSGPolygon3D)
    if candidates.is_empty():
        return

    for building: CSGPolygon3D in candidates:
        var shared := _shared_material_for(building.material)
        if shared == null:
            _fail("unsupported legacy material for %s" % building.name)
            return
        var instance_id := building.get_instance_id()
        _buildings.append(building)
        _legacy_materials[instance_id] = building.material
        _original_transforms[instance_id] = building.global_transform
        _original_polygons[instance_id] = building.polygon.duplicate()
        _original_depths[instance_id] = building.depth
        building.set_meta("environment_role", "generic_osm_building_wall")
        building.set_meta("material_family", MATERIAL_FACTORY.MATERIAL_FAMILY)
        building.set_meta("placement_provenance", "OpenStreetMap contributors via Overpass API")
        building.set_meta("license", "ODbL-1.0")
        building.set_meta("building_material_claimed", false)
        building.set_meta("geometry_changed_by_facade_surface_runtime", false)

    if _materials.size() > EXPECTED_MAX_PALETTE:
        _fail("unexpected legacy palette expansion (%d)" % _materials.size())
        return

    _buildings_root = buildings_root
    _set_material_state(_enhanced_enabled)
    _ready_complete = true
    facade_surface_ready.emit()
    print("BRUSSELS_OSM_FACADE_SURFACE_READY: buildings=%d materials=%d family=%s source=OSM license=ODbL-1.0 geometry_changed=false material_identity_claimed=false event_driven=true scene_rebindable=true authoritative_scene_only=true" % [_buildings.size(), _materials.size(), MATERIAL_FACTORY.MATERIAL_FAMILY])

func _set_material_state(enabled: bool) -> void:
    if _tearing_down or not is_inside_tree():
        return
    for building: CSGPolygon3D in _buildings:
        if not is_instance_valid(building):
            continue
        var instance_id := building.get_instance_id()
        if enabled:
            var legacy := _legacy_materials.get(instance_id) as Material
            var owned := _shared_material_for(legacy)
            building.material = owned
            _owned_materials[instance_id] = owned
        else:
            building.material = _legacy_materials.get(instance_id) as Material

func set_enhanced_enabled(enabled: bool) -> void:
    _enhanced_enabled = enabled
    if _ready_complete and not _failed and not _tearing_down and is_inside_tree():
        _set_material_state(enabled)

func enhanced_enabled() -> bool:
    return _enhanced_enabled

func ready_complete() -> bool:
    return _ready_complete

func failed() -> bool:
    return _failed

func applied_building_count() -> int:
    return _buildings.size() if _ready_complete and not _failed else 0

func shared_material_count() -> int:
    return _materials.size()

func hero_replacement_count() -> int:
    return _hero_replacements_touched

func material_family() -> String:
    return MATERIAL_FACTORY.MATERIAL_FAMILY

func geometry_unchanged() -> bool:
    for building: CSGPolygon3D in _buildings:
        if not is_instance_valid(building):
            return false
        var instance_id := building.get_instance_id()
        var original_transform: Transform3D = _original_transforms.get(instance_id, Transform3D.IDENTITY)
        var original_polygon: PackedVector2Array = _original_polygons.get(instance_id, PackedVector2Array())
        var original_depth: float = float(_original_depths.get(instance_id, -1.0))
        if not building.global_transform.is_equal_approx(original_transform):
            return false
        if building.polygon != original_polygon:
            return false
        if not is_equal_approx(building.depth, original_depth):
            return false
    return true
