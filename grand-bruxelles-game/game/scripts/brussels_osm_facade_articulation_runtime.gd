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

func _ready() -> void:
    call_deferred("_apply_when_ready")

func _material_key(material: ShaderMaterial) -> String:
    var color_variant: Variant = material.get_shader_parameter("base_color")
    var roughness_variant: Variant = material.get_shader_parameter("base_roughness")
    if not color_variant is Color:
        return ""
    var color := color_variant as Color
    var roughness := float(roughness_variant)
    return "%0.4f:%0.4f:%0.4f:%0.4f:%0.4f" % [color.r, color.g, color.b, color.a, roughness]

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
    var color := shader_material.get_shader_parameter("base_color") as Color
    var roughness := float(shader_material.get_shader_parameter("base_roughness"))
    var candidate := MATERIAL_FACTORY.create_material(color, roughness)
    candidate.set_meta("baseline_material_family", BASE_FAMILY)
    candidate.set_meta("baseline_palette_key", key)
    _candidate_materials[key] = candidate
    return candidate

func _apply_when_ready() -> void:
    var base_runtime := get_tree().root.get_node_or_null("BrusselsOsmFacadeSurfaceRuntime")
    if base_runtime == null:
        push_error("Brussels OSM facade articulation runtime: production facade runtime missing")
        _failed = true
        _ready_complete = true
        return
    for _frame: int in range(240):
        if bool(base_runtime.call("ready_complete")):
            break
        await get_tree().process_frame
    if not bool(base_runtime.call("ready_complete")) or bool(base_runtime.call("failed")):
        push_error("Brussels OSM facade articulation runtime: production facade runtime not ready")
        _failed = true
        _ready_complete = true
        return
    if not bool(base_runtime.call("enhanced_enabled")):
        push_error("Brussels OSM facade articulation runtime: production facade baseline unexpectedly disabled")
        _failed = true
        _ready_complete = true
        return

    var buildings_root := get_tree().root.find_child("GeneratedBuildings", true, false) as Node3D
    if buildings_root == null:
        push_error("Brussels OSM facade articulation runtime: GeneratedBuildings missing")
        _failed = true
        _ready_complete = true
        return

    for child: Node in buildings_root.get_children():
        if not child is CSGPolygon3D or not str(child.name).begins_with("Building_"):
            continue
        var building := child as CSGPolygon3D
        var candidate := _candidate_for(building.material)
        if candidate == null:
            push_error("Brussels OSM facade articulation runtime: unsupported production facade material for %s" % building.name)
            _failed = true
            _ready_complete = true
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
        building.set_meta("facade_articulation_window_geometry_claimed", false)

    if _buildings.is_empty():
        push_error("Brussels OSM facade articulation runtime: no generic production buildings found")
        _failed = true
        _ready_complete = true
        return
    if _candidate_materials.size() > EXPECTED_MAX_PALETTE:
        push_error("Brussels OSM facade articulation runtime: unexpected palette expansion (%d)" % _candidate_materials.size())
        _failed = true
        _ready_complete = true
        return

    _set_material_state(_enhanced_enabled)
    _ready_complete = true
    print("BRUSSELS_OSM_FACADE_ARTICULATION_READY: buildings=%d materials=%d family=%s baseline=%s geometry_changed=false" % [_buildings.size(), _candidate_materials.size(), MATERIAL_FACTORY.MATERIAL_FAMILY, BASE_FAMILY])

func _set_material_state(enabled: bool) -> void:
    for building: CSGPolygon3D in _buildings:
        if not is_instance_valid(building):
            continue
        var instance_id := building.get_instance_id()
        var baseline := _baseline_materials.get(instance_id) as Material
        if enabled:
            building.material = _candidate_for(baseline)
        else:
            building.material = baseline

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
    return _candidate_materials.size()

func material_family() -> String:
    return MATERIAL_FACTORY.MATERIAL_FAMILY

func baseline_material_family() -> String:
    return BASE_FAMILY

func geometry_unchanged() -> bool:
    for building: CSGPolygon3D in _buildings:
        if not is_instance_valid(building):
            return false
        var instance_id := building.get_instance_id()
        var original_transform: Transform3D = _original_transforms.get(instance_id, Transform3D.IDENTITY)
        var original_polygon: PackedVector2Array = _original_polygons.get(instance_id, PackedVector2Array())
        var original_depth := float(_original_depths.get(instance_id, -1.0))
        if not building.global_transform.is_equal_approx(original_transform):
            return false
        if building.polygon != original_polygon:
            return false
        if not is_equal_approx(building.depth, original_depth):
            return false
    return true
