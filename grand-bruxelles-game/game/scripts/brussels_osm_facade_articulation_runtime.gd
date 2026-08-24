extends Node

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_osm_facade_articulation_material.gd")
const BASE_FAMILY := "brussels_osm_facade_surface_v1"
const EXPECTED_MAX_PALETTE := 6

var _buildings: Array[CSGPolygon3D] = []
var _baseline_materials: Dictionary = {}
var _candidate_materials: Dictionary = {}
var _original_transforms: Dictionary = {}
var _original_polygons: Dictionary = {}
var _original_depths: Dictionary = {}
var _enhanced_enabled := true
var _ready_complete := false
var _failed := false
var _bind_scheduled := false
var _base_runtime: Node = null

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    var tree := get_tree()
    if not tree.node_added.is_connected(_on_node_added):
        tree.node_added.connect(_on_node_added)
    _schedule_apply()

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

func _valid_buildings_root(node: Node) -> bool:
    return node is Node3D and str(node.name) == "GeneratedBuildings" and node.get_parent() != null and str(node.get_parent().name) == "BrusselsOSM"

func _find_existing_buildings_root() -> Node3D:
    # One bounded recursive recovery covers legitimate test/editor mounts where
    # production main is nested below a SubViewport. This remains event-driven
    # and never restores the historical frame polling loop.
    for candidate: Node in get_tree().root.find_children("GeneratedBuildings", "Node3D", true, false):
        if _valid_buildings_root(candidate):
            return candidate as Node3D
    return null

func _connect_base_runtime() -> void:
    if is_instance_valid(_base_runtime):
        return
    _base_runtime = get_tree().root.get_node_or_null("BrusselsOsmFacadeSurfaceRuntime")
    if _base_runtime != null and _base_runtime.has_signal("facade_surface_ready"):
        if not _base_runtime.facade_surface_ready.is_connected(_on_base_surface_ready):
            _base_runtime.facade_surface_ready.connect(_on_base_surface_ready)

func _on_base_surface_ready() -> void:
    _schedule_apply()

func _on_node_added(node: Node) -> void:
    if _ready_complete or _failed:
        return
    if str(node.name) == "BrusselsOsmFacadeSurfaceRuntime":
        _connect_base_runtime()
    var cursor: Node = node
    while cursor != null and cursor != get_tree().root:
        if _valid_buildings_root(cursor):
            _schedule_apply()
            return
        cursor = cursor.get_parent()
    var nested := node.get_node_or_null("BrusselsOSM/GeneratedBuildings")
    if _valid_buildings_root(nested):
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
    push_error("Brussels OSM facade articulation runtime: %s" % message)
    _failed = true
    _ready_complete = true
    _disconnect_mount_listener()

func _try_apply() -> void:
    _bind_scheduled = false
    if _ready_complete or _failed:
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
    _set_material_state(_enhanced_enabled)
    _ready_complete = true
    _disconnect_mount_listener()
    print("BRUSSELS_OSM_FACADE_ARTICULATION_READY: buildings=%d materials=%d family=%s baseline=%s geometry_changed=false event_driven=true" % [_buildings.size(), _candidate_materials.size(), MATERIAL_FACTORY.MATERIAL_FAMILY, BASE_FAMILY])

func _set_material_state(enabled: bool) -> void:
    for building: CSGPolygon3D in _buildings:
        if not is_instance_valid(building):
            continue
        var baseline := _baseline_materials.get(building.get_instance_id()) as Material
        building.material = _candidate_for(baseline) if enabled else baseline

func set_enhanced_enabled(enabled: bool) -> void:
    _enhanced_enabled = enabled
    if _ready_complete and not _failed:
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
