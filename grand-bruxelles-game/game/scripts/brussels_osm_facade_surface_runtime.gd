extends Node

signal facade_surface_ready

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_osm_facade_surface_material.gd")
const EXPECTED_MAX_PALETTE := 6

var _buildings: Array[CSGPolygon3D] = []
var _legacy_materials: Dictionary = {}
var _original_transforms: Dictionary = {}
var _original_polygons: Dictionary = {}
var _original_depths: Dictionary = {}
var _materials: Dictionary = {}
var _enhanced_enabled := true
var _ready_complete := false
var _failed := false
var _hero_replacements_touched := 0
var _bind_scheduled := false

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    var tree := get_tree()
    if not tree.node_added.is_connected(_on_node_added):
        tree.node_added.connect(_on_node_added)
    _schedule_apply()

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

func _valid_buildings_root(node: Node) -> bool:
    return node is Node3D and str(node.name) == "GeneratedBuildings" and node.get_parent() != null and str(node.get_parent().name) == "BrusselsOSM"

func _buildings_root_from_added(node: Node) -> Node3D:
    var cursor: Node = node
    while cursor != null and cursor != get_tree().root:
        if _valid_buildings_root(cursor):
            return cursor as Node3D
        cursor = cursor.get_parent()
    var nested := node.get_node_or_null("BrusselsOSM/GeneratedBuildings")
    if _valid_buildings_root(nested):
        return nested as Node3D
    return null

func _find_existing_buildings_root() -> Node3D:
    # One bounded recursive recovery covers legitimate test/editor mounts where
    # production main is nested below a SubViewport. This is event-driven and
    # never reintroduces the historical frame-by-frame global polling loop.
    for candidate: Node in get_tree().root.find_children("GeneratedBuildings", "Node3D", true, false):
        if _valid_buildings_root(candidate):
            return candidate as Node3D
    return null

func _on_node_added(node: Node) -> void:
    if _ready_complete or _failed:
        return
    if _buildings_root_from_added(node) != null:
        _schedule_apply()

func _schedule_apply() -> void:
    if _bind_scheduled or _ready_complete or _failed:
        return
    _bind_scheduled = true
    call_deferred("_try_apply")

func _disconnect_mount_listener() -> void:
    var tree := get_tree()
    if tree != null and tree.node_added.is_connected(_on_node_added):
        tree.node_added.disconnect(_on_node_added)

func _fail(message: String) -> void:
    push_error("Brussels OSM facade surface runtime: %s" % message)
    _failed = true
    _ready_complete = true
    _disconnect_mount_listener()

func _try_apply() -> void:
    _bind_scheduled = false
    if _ready_complete or _failed:
        return
    var buildings_root := _find_existing_buildings_root()
    if buildings_root == null:
        return

    var candidates: Array[CSGPolygon3D] = []
    for child: Node in buildings_root.get_children():
        if child is CSGPolygon3D and str(child.name).begins_with("Building_"):
            candidates.append(child as CSGPolygon3D)
    # GeneratedBuildings may be announced before its children are populated.
    # Stay dormant; the child node_added event will retry without global polling.
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

    _set_material_state(_enhanced_enabled)
    _ready_complete = true
    _disconnect_mount_listener()
    facade_surface_ready.emit()
    print("BRUSSELS_OSM_FACADE_SURFACE_READY: buildings=%d materials=%d family=%s source=OSM license=ODbL-1.0 geometry_changed=false material_identity_claimed=false event_driven=true" % [_buildings.size(), _materials.size(), MATERIAL_FACTORY.MATERIAL_FAMILY])

func _set_material_state(enabled: bool) -> void:
    for building: CSGPolygon3D in _buildings:
        if not is_instance_valid(building):
            continue
        var instance_id := building.get_instance_id()
        if enabled:
            var legacy := _legacy_materials.get(instance_id) as Material
            building.material = _shared_material_for(legacy)
        else:
            building.material = _legacy_materials.get(instance_id) as Material

func set_enhanced_enabled(enabled: bool) -> void:
    _enhanced_enabled = enabled
    if _ready_complete and not _failed:
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
