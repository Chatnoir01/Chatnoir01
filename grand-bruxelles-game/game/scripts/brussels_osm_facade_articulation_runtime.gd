extends Node

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_osm_facade_articulation_material.gd")
const BASE_FAMILY := "brussels_osm_facade_surface_v1"
const EXPECTED_MAX_PALETTE := 6

var _buildings: Array[CSGPolygon3D] = []
var _buildings_root: Node3D = null
var _baseline_materials: Dictionary = {}
var _owned_materials: Dictionary = {}
var _candidate_materials: Dictionary = {}
var _original_transforms: Dictionary = {}
var _original_polygons: Dictionary = {}
var _original_depths: Dictionary = {}
var _enhanced_enabled := true
var _ready_complete := false
var _failed := false
var _bind_scheduled := false
var _base_runtime: Node = null
var _tearing_down := false

func _ready() -> void:
    _tearing_down = false
    process_mode = Node.PROCESS_MODE_ALWAYS
    _start_watching()
    _schedule_apply()

func _exit_tree() -> void:
    _tearing_down = true
    _bind_scheduled = false
    _release_material_ownership()
    _buildings_root = null
    _stop_watching()
    _disconnect_base_runtime()

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

func _material_key(material: ShaderMaterial) -> String:
    var color_variant: Variant = material.get_shader_parameter("base_color")
    var roughness_variant: Variant = material.get_shader_parameter("base_roughness")
    if not color_variant is Color:
        return ""
    var color := color_variant as Color
    return "%0.4f:%0.4f:%0.4f:%0.4f:%0.4f" % [color.r, color.g, color.b, color.a, float(roughness_variant)]

func _candidate_for(material: Material) -> ShaderMaterial:
    if not material is ShaderMaterial:
        return null
    var shader_material := material as ShaderMaterial
    if str(shader_material.get_meta("material_family", "")) != BASE_FAMILY:
        return null
    var key := _material_key(shader_material)
    if key.is_empty():
        return null
    if _candidate_materials.has(key):
        return _candidate_materials[key] as ShaderMaterial
    var candidate := MATERIAL_FACTORY.create_material(shader_material.get_shader_parameter("base_color") as Color, float(shader_material.get_shader_parameter("base_roughness")))
    candidate.set_meta("baseline_material_family", BASE_FAMILY)
    candidate.set_meta("baseline_palette_key", key)
    _candidate_materials[key] = candidate
    return candidate

func _is_authoritative_facade_scene(node: Node) -> bool:
    if not node is Node3D or not is_inside_tree():
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
    # Match the already-validated facade-surface synthetic/editor contract:
    # SceneTree.root -> Viewport -> Main. Arbitrary deeper nesting never owns
    # the authored articulation layer merely because its anchors have familiar names.
    return str(candidate.name) == "Main" and parent is Viewport and parent.get_parent() == tree.root

func _valid_buildings_root(node: Node) -> bool:
    if not node is Node3D or str(node.name) != "GeneratedBuildings":
        return false
    var osm := node.get_parent()
    if osm == null or str(osm.name) != "BrusselsOSM":
        return false
    return _is_authoritative_facade_scene(osm.get_parent())

func _find_existing_buildings_root() -> Node3D:
    if _tearing_down or not is_inside_tree():
        return null
    var tree := get_tree()
    if tree == null:
        return null
    # Recovery can stay recursive; authority is constrained by scene topology.
    for candidate: Node in tree.root.find_children("GeneratedBuildings", "Node3D", true, false):
        if _valid_buildings_root(candidate):
            return candidate as Node3D
    return null

func _disconnect_base_runtime() -> void:
    if is_instance_valid(_base_runtime) and _base_runtime.has_signal("facade_surface_ready"):
        if _base_runtime.facade_surface_ready.is_connected(_on_base_surface_ready):
            _base_runtime.facade_surface_ready.disconnect(_on_base_surface_ready)
    _base_runtime = null

func _connect_base_runtime() -> void:
    if _tearing_down or not is_inside_tree() or is_instance_valid(_base_runtime):
        return
    var tree := get_tree()
    if tree == null:
        return
    _base_runtime = tree.root.get_node_or_null("BrusselsOsmFacadeSurfaceRuntime")
    if _base_runtime != null and _base_runtime.has_signal("facade_surface_ready"):
        if not _base_runtime.facade_surface_ready.is_connected(_on_base_surface_ready):
            _base_runtime.facade_surface_ready.connect(_on_base_surface_ready)

func _on_base_surface_ready() -> void:
    if _tearing_down or not is_inside_tree():
        return
    _schedule_apply()

func _on_node_added(node: Node) -> void:
    if _tearing_down or not is_inside_tree() or _ready_complete or _failed:
        return
    if str(node.name) == "BrusselsOsmFacadeSurfaceRuntime":
        _connect_base_runtime()
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
    _connect_base_runtime()
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
        var baseline := _baseline_materials.get(instance_id) as Material
        var owned := _owned_materials.get(instance_id) as Material
        if owned != null and building.material == owned and baseline != null:
            building.material = baseline
        if str(building.get_meta("facade_articulation_family", "")) == MATERIAL_FACTORY.MATERIAL_FAMILY:
            building.remove_meta("facade_articulation_family")
            building.remove_meta("facade_articulation_geometry_changed")
            building.remove_meta("facade_articulation_source")
            building.remove_meta("facade_articulation_license")
    _buildings.clear()
    _baseline_materials.clear()
    _owned_materials.clear()
    _candidate_materials.clear()
    _original_transforms.clear()
    _original_polygons.clear()
    _original_depths.clear()

func _fail(message: String) -> void:
    if _tearing_down:
        return
    push_error("Brussels OSM facade articulation runtime: %s" % message)
    _failed = true
    _ready_complete = true
    _stop_watching()
    _disconnect_base_runtime()

func _try_apply() -> void:
    _bind_scheduled = false
    if _tearing_down or not is_inside_tree() or _ready_complete or _failed:
        return
    _connect_base_runtime()
    if _base_runtime == null:
        return
    if bool(_base_runtime.call("failed")):
        _fail("production facade runtime failed")
        return
    if not bool(_base_runtime.call("ready_complete")):
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
        var candidate := _candidate_for(building.material)
        if candidate == null:
            _fail("unsupported production facade material for %s" % building.name)
            return
        var instance_id := building.get_instance_id()
        _buildings.append(building)
        _baseline_materials[instance_id] = building.material
        _owned_materials[instance_id] = candidate
        _original_transforms[instance_id] = building.global_transform
        _original_polygons[instance_id] = building.polygon.duplicate()
        _original_depths[instance_id] = building.depth
        building.set_meta("facade_articulation_family", MATERIAL_FACTORY.MATERIAL_FAMILY)
        building.set_meta("facade_articulation_geometry_changed", false)
        building.set_meta("facade_articulation_source", "OpenStreetMap contributors via Overpass API")
        building.set_meta("facade_articulation_license", "ODbL-1.0")
    if _candidate_materials.size() > EXPECTED_MAX_PALETTE:
        _fail("invalid production building/palette state")
        return
    _buildings_root = buildings_root
    _set_material_state(_enhanced_enabled)
    _ready_complete = true
    print("BRUSSELS_OSM_FACADE_ARTICULATION_READY: buildings=%d materials=%d family=%s baseline=%s geometry_changed=false event_driven=true scene_rebindable=true authoritative_scene_only=true" % [_buildings.size(), _candidate_materials.size(), MATERIAL_FACTORY.MATERIAL_FAMILY, BASE_FAMILY])

func _set_material_state(enabled: bool) -> void:
    if _tearing_down or not is_inside_tree():
        return
    for building: CSGPolygon3D in _buildings:
        if not is_instance_valid(building):
            continue
        var instance_id := building.get_instance_id()
        var baseline := _baseline_materials.get(instance_id) as Material
        var owned := _owned_materials.get(instance_id) as Material
        building.material = owned if enabled else baseline

func set_enhanced_enabled(enabled: bool) -> void:
    _enhanced_enabled = enabled
    if _ready_complete and not _failed and not _tearing_down and is_inside_tree():
        _set_material_state(enabled)
func enhanced_enabled() -> bool: return _enhanced_enabled
func ready_complete() -> bool: return _ready_complete
func failed() -> bool: return _failed
func applied_building_count() -> int: return _buildings.size() if _ready_complete and not _failed else 0
func shared_material_count() -> int: return _candidate_materials.size()
func material_family() -> String: return MATERIAL_FACTORY.MATERIAL_FAMILY
func baseline_material_family() -> String: return BASE_FAMILY
func geometry_unchanged() -> bool:
    for building: CSGPolygon3D in _buildings:
        if not is_instance_valid(building): return false
        var id := building.get_instance_id()
        if not building.global_transform.is_equal_approx(_original_transforms.get(id, Transform3D.IDENTITY)): return false
        if building.polygon != (_original_polygons.get(id, PackedVector2Array()) as PackedVector2Array): return false
        if not is_equal_approx(building.depth, float(_original_depths.get(id, -1.0))): return false
    return true