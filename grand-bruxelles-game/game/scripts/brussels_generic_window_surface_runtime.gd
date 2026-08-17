extends Node

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_generic_window_surface_material.gd")

var _window_instance: MultiMeshInstance3D
var _window_mesh: BoxMesh
var _legacy_material: Material
var _shared_material: ShaderMaterial
var _original_instance_count := 0
var _original_transforms: Array[Transform3D] = []
var _enhanced_enabled := true
var _ready_complete := false
var _failed := false

func _ready() -> void:
    call_deferred("_apply_when_ready")

func _apply_when_ready() -> void:
    var found: MultiMeshInstance3D = null
    for _attempt: int in range(180):
        await get_tree().process_frame
        var candidate := get_tree().root.find_child("CorridorFacadeWindows", true, false)
        if candidate is MultiMeshInstance3D:
            found = candidate as MultiMeshInstance3D
            break
    if found == null:
        push_error("Brussels generic window surface runtime: CorridorFacadeWindows missing")
        _failed = true
        _ready_complete = true
        return
    if found.multimesh == null or found.multimesh.mesh == null:
        push_error("Brussels generic window surface runtime: window MultiMesh missing mesh")
        _failed = true
        _ready_complete = true
        return
    if not found.multimesh.mesh is BoxMesh:
        push_error("Brussels generic window surface runtime: unsupported generic window mesh")
        _failed = true
        _ready_complete = true
        return

    _window_instance = found
    _window_mesh = found.multimesh.mesh as BoxMesh
    _legacy_material = _window_mesh.material
    if not _legacy_material is StandardMaterial3D:
        push_error("Brussels generic window surface runtime: legacy window material is not StandardMaterial3D")
        _failed = true
        _ready_complete = true
        return

    var standard := _legacy_material as StandardMaterial3D
    _shared_material = MATERIAL_FACTORY.create_material(standard.albedo_color, standard.roughness, standard.metallic)
    _original_instance_count = found.multimesh.instance_count
    if _original_instance_count <= 0:
        push_error("Brussels generic window surface runtime: generic window batch is empty")
        _failed = true
        _ready_complete = true
        return

    _original_transforms.clear()
    for index: int in range(_original_instance_count):
        _original_transforms.append(found.multimesh.get_instance_transform(index))

    found.set_meta("environment_role", "generic_osm_window_presentation")
    found.set_meta("material_family", MATERIAL_FACTORY.MATERIAL_FAMILY)
    found.set_meta("parent_building_placement_provenance", "OpenStreetMap contributors via Overpass API")
    found.set_meta("license", "ODbL-1.0")
    found.set_meta("opening_geometry_claimed", false)
    found.set_meta("glass_identity_claimed", false)
    found.set_meta("geometry_changed_by_window_surface_runtime", false)

    _set_material_state(_enhanced_enabled)
    _ready_complete = true
    print("BRUSSELS_GENERIC_WINDOW_SURFACE_READY: windows=%d family=%s source=OSM-parent-buildings license=ODbL-1.0 geometry_changed=false opening_geometry_claimed=false glass_identity_claimed=false" % [_original_instance_count, MATERIAL_FACTORY.MATERIAL_FAMILY])

func _set_material_state(enabled: bool) -> void:
    if _window_mesh == null:
        return
    _window_mesh.material = _shared_material if enabled else _legacy_material

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

func applied_window_count() -> int:
    return _original_instance_count if _ready_complete and not _failed else 0

func material_family() -> String:
    return MATERIAL_FACTORY.MATERIAL_FAMILY

func opening_geometry_claimed() -> bool:
    return false

func geometry_unchanged() -> bool:
    if _window_instance == null or _window_instance.multimesh == null:
        return false
    if _window_instance.multimesh.instance_count != _original_instance_count:
        return false
    if _original_transforms.size() != _original_instance_count:
        return false
    for index: int in range(_original_instance_count):
        if not _window_instance.multimesh.get_instance_transform(index).is_equal_approx(_original_transforms[index]):
            return false
    return true
