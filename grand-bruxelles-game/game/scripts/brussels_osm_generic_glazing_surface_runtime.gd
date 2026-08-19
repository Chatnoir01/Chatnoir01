extends Node

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_osm_generic_glazing_surface_material.gd")
const SOURCE := "OpenStreetMap contributors via Overpass API"
const LICENSE := "ODbL-1.0"

var _targets: Dictionary = {}
var _legacy_materials: Dictionary = {}
var _materials: Dictionary = {}
var _enhanced_enabled := true
var _ready_complete := false
var _failed := false

func _ready() -> void:
    call_deferred("_apply_when_ready")

func _apply_when_ready() -> void:
    var details_root: Node3D = null
    for _attempt: int in range(240):
        await get_tree().process_frame
        var candidate := get_tree().root.find_child("GeneratedFacadeDetails", true, false)
        if candidate is Node3D:
            details_root = candidate as Node3D
            break
    if details_root == null:
        _stop("GeneratedFacadeDetails missing")
        return

    var windows := details_root.get_node_or_null("CorridorFacadeWindows") as MultiMeshInstance3D
    var shops := details_root.get_node_or_null("CorridorShopfronts") as MultiMeshInstance3D
    if windows == null or shops == null:
        _stop("generic facade glazing batches missing")
        return
    if windows.multimesh == null or shops.multimesh == null:
        _stop("generic facade glazing multimesh missing")
        return
    if windows.multimesh.mesh == null or shops.multimesh.mesh == null:
        _stop("generic facade glazing mesh missing")
        return

    _targets = {"window": windows, "shop": shops}
    _legacy_materials = {
        "window": windows.multimesh.mesh.material,
        "shop": shops.multimesh.mesh.material,
    }
    _materials = MATERIAL_FACTORY.create_materials()
    if _materials.size() != 2:
        _stop("shared material family incomplete")
        return

    for role: String in _targets.keys():
        var instance := _targets[role] as MultiMeshInstance3D
        instance.set_meta("generic_glazing_surface_family", MATERIAL_FACTORY.MATERIAL_FAMILY)
        instance.set_meta("source", SOURCE)
        instance.set_meta("license", LICENSE)
        instance.set_meta("geometry_changed_by_generic_glazing_runtime", false)

    _set_material_state(_enhanced_enabled)
    _ready_complete = true
    print("BRUSSELS_OSM_GENERIC_GLAZING_READY: windows=%d shops=%d materials=2 family=%s geometry_changed=false" % [windows.multimesh.instance_count, shops.multimesh.instance_count, MATERIAL_FACTORY.MATERIAL_FAMILY])

func _stop(message: String) -> void:
    push_error("Brussels OSM generic glazing surface runtime: %s" % message)
    _failed = true
    _ready_complete = true

func _set_material_state(enabled: bool) -> void:
    for role: String in _targets.keys():
        var instance := _targets[role] as MultiMeshInstance3D
        if not is_instance_valid(instance) or instance.multimesh == null or instance.multimesh.mesh == null:
            continue
        instance.multimesh.mesh.material = (_materials[role] if enabled else _legacy_materials[role]) as Material

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

func geometry_unchanged() -> bool:
    if not _ready_complete or _failed:
        return false
    for role: String in _targets.keys():
        var instance := _targets[role] as MultiMeshInstance3D
        if instance == null or bool(instance.get_meta("geometry_changed_by_generic_glazing_runtime", true)):
            return false
    return true

func applied_instance_count() -> int:
    var total := 0
    for role: String in _targets.keys():
        var instance := _targets[role] as MultiMeshInstance3D
        if instance != null and instance.multimesh != null:
            total += instance.multimesh.instance_count
    return total

func shared_material_count() -> int:
    return _materials.size()
