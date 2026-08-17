extends Node

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_osm_sidewalk_surface_material.gd")
const EXPECTED_WIDTHS := [1.85, 2.55]
const WIDTH_TOLERANCE := 0.02
const HEIGHT := 0.12
const HEIGHT_TOLERANCE := 0.005

var _sidewalks: Array[CSGBox3D] = []
var _legacy_materials: Dictionary = {}
var _original_transforms: Dictionary = {}
var _original_sizes: Dictionary = {}
var _material: ShaderMaterial
var _enhanced_enabled := true
var _ready_complete := false
var _failed := false

func _ready() -> void:
    call_deferred("_apply_when_ready")

func _is_generated_sidewalk(box: CSGBox3D) -> bool:
    if str(box.name).begins_with("Road_"):
        return false
    if absf(box.size.y - HEIGHT) > HEIGHT_TOLERANCE:
        return false
    for expected: float in EXPECTED_WIDTHS:
        if absf(box.size.x - expected) <= WIDTH_TOLERANCE:
            return true
    return false

func _apply_when_ready() -> void:
    var roads_root: Node3D = null
    for _attempt: int in range(180):
        await get_tree().process_frame
        var candidate := get_tree().root.find_child("GeneratedRoads", true, false)
        if candidate is Node3D:
            roads_root = candidate as Node3D
            break
    if roads_root == null:
        push_error("Brussels OSM sidewalk surface runtime: GeneratedRoads missing")
        _failed = true
        _ready_complete = true
        return

    _material = MATERIAL_FACTORY.create_material()
    for child: Node in roads_root.get_children():
        if not child is CSGBox3D:
            continue
        var box := child as CSGBox3D
        if not _is_generated_sidewalk(box):
            continue
        var instance_id := box.get_instance_id()
        _sidewalks.append(box)
        _legacy_materials[instance_id] = box.material
        _original_transforms[instance_id] = box.global_transform
        _original_sizes[instance_id] = box.size
        box.set_meta("environment_role", "generated_osm_sidewalk")
        box.set_meta("material_family", MATERIAL_FACTORY.MATERIAL_FAMILY)
        box.set_meta("placement_provenance", "adjacent_to_existing_osm_road_runtime_convention")
        box.set_meta("surface_composition_claimed", false)
        box.set_meta("geometry_changed_by_sidewalk_surface_runtime", false)

    if _sidewalks.is_empty():
        push_error("Brussels OSM sidewalk surface runtime: no existing generated sidewalks found")
        _failed = true
        _ready_complete = true
        return

    _set_material_state(_enhanced_enabled)
    _ready_complete = true
    print("BRUSSELS_OSM_SIDEWALK_SURFACE_READY: sidewalks=%d materials=1 family=%s source=OSM-adjacent authored-placement license=ODbL-1.0 geometry_changed=false" % [_sidewalks.size(), MATERIAL_FACTORY.MATERIAL_FAMILY])

func _set_material_state(enabled: bool) -> void:
    for sidewalk: CSGBox3D in _sidewalks:
        if not is_instance_valid(sidewalk):
            continue
        var instance_id := sidewalk.get_instance_id()
        if enabled:
            sidewalk.material = _material
        else:
            sidewalk.material = _legacy_materials.get(instance_id) as Material

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

func applied_sidewalk_count() -> int:
    return _sidewalks.size() if _ready_complete and not _failed else 0

func shared_material_count() -> int:
    return 1 if _material != null else 0

func geometry_unchanged() -> bool:
    for sidewalk: CSGBox3D in _sidewalks:
        if not is_instance_valid(sidewalk):
            return false
        var instance_id := sidewalk.get_instance_id()
        var original_transform: Transform3D = _original_transforms.get(instance_id, Transform3D.IDENTITY)
        var original_size: Vector3 = _original_sizes.get(instance_id, Vector3.ZERO)
        if not sidewalk.global_transform.is_equal_approx(original_transform):
            return false
        if not sidewalk.size.is_equal_approx(original_size):
            return false
    return true
