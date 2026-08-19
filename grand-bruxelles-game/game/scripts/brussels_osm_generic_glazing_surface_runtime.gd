extends Node

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_osm_generic_glazing_surface_material.gd")
const SOURCE := "OpenStreetMap contributors via Overpass API"
const LICENSE := "ODbL-1.0"
const WINDOW_PREFIX := "CorridorWindowGlass"
const SHOP_PREFIX := "CorridorShopfrontGlass"

var _targets: Dictionary = {"window": [], "shop": []}
var _legacy_overrides: Dictionary = {}
var _materials: Dictionary = {}
var _enhanced_enabled := true
var _ready_complete := false
var _failed := false

func _ready() -> void:
    call_deferred("_apply_when_ready")

func _collect_render_targets(details_root: Node3D) -> Dictionary:
    var found := {"window": [], "shop": []}
    for child: Node in details_root.get_children():
        if not child is MultiMeshInstance3D:
            continue
        var instance := child as MultiMeshInstance3D
        if instance.multimesh == null or instance.multimesh.mesh == null:
            continue
        var node_name := str(instance.name)
        if node_name == WINDOW_PREFIX or node_name.begins_with(WINDOW_PREFIX + "_"):
            (found["window"] as Array).append(instance)
        elif node_name == SHOP_PREFIX or node_name.begins_with(SHOP_PREFIX + "_"):
            (found["shop"] as Array).append(instance)
    return found

func _apply_when_ready() -> void:
    var details_root: Node3D = null
    for _attempt: int in range(300):
        await get_tree().process_frame
        var candidate := get_tree().root.find_child("GeneratedFacadeDetails", true, false)
        if not candidate is Node3D:
            continue
        details_root = candidate as Node3D
        var found := _collect_render_targets(details_root)
        if not (found["window"] as Array).is_empty() and not (found["shop"] as Array).is_empty():
            _targets = found
            break
    if details_root == null:
        _stop("GeneratedFacadeDetails missing")
        return
    if (_targets["window"] as Array).is_empty() or (_targets["shop"] as Array).is_empty():
        _stop("rendered corridor glazing batches missing")
        return

    var source_windows := details_root.get_node_or_null("CorridorFacadeWindows") as MultiMeshInstance3D
    var source_shops := details_root.get_node_or_null("CorridorShopfronts") as MultiMeshInstance3D
    if source_windows == null or source_shops == null:
        _stop("generic facade glazing source batches missing")
        return
    if source_windows.visible or source_shops.visible:
        _stop("facade depth runtime did not replace legacy source glazing")
        return

    _materials = MATERIAL_FACTORY.create_materials()
    if _materials.size() != 2:
        _stop("shared material family incomplete")
        return

    for role: String in _targets.keys():
        for raw_instance: Variant in _targets[role]:
            var instance := raw_instance as MultiMeshInstance3D
            if instance == null:
                _stop("invalid rendered glazing target")
                return
            _legacy_overrides[instance.get_instance_id()] = instance.material_override
            instance.set_meta("generic_glazing_surface_family", MATERIAL_FACTORY.MATERIAL_FAMILY)
            instance.set_meta("generic_glazing_role", role)
            instance.set_meta("source", SOURCE)
            instance.set_meta("license", LICENSE)
            instance.set_meta("geometry_changed_by_generic_glazing_runtime", false)

    _set_material_state(_enhanced_enabled)
    _ready_complete = true
    print("BRUSSELS_OSM_GENERIC_GLAZING_READY: window_batches=%d shop_batches=%d instances=%d materials=2 family=%s geometry_changed=false" % [render_batch_count("window"), render_batch_count("shop"), applied_instance_count(), MATERIAL_FACTORY.MATERIAL_FAMILY])

func _stop(message: String) -> void:
    push_error("Brussels OSM generic glazing surface runtime: %s" % message)
    _failed = true
    _ready_complete = true

func _set_material_state(enabled: bool) -> void:
    for role: String in _targets.keys():
        for raw_instance: Variant in _targets[role]:
            var instance := raw_instance as MultiMeshInstance3D
            if not is_instance_valid(instance):
                continue
            if enabled:
                instance.material_override = _materials[role] as Material
            else:
                instance.material_override = _legacy_overrides.get(instance.get_instance_id()) as Material

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
        for raw_instance: Variant in _targets[role]:
            var instance := raw_instance as MultiMeshInstance3D
            if instance == null or bool(instance.get_meta("geometry_changed_by_generic_glazing_runtime", true)):
                return false
    return true

func applied_instance_count() -> int:
    var total := 0
    for role: String in _targets.keys():
        for raw_instance: Variant in _targets[role]:
            var instance := raw_instance as MultiMeshInstance3D
            if instance != null and instance.multimesh != null:
                total += instance.multimesh.instance_count
    return total

func render_batch_count(role: String) -> int:
    if not _targets.has(role):
        return 0
    return (_targets[role] as Array).size()

func shared_material_count() -> int:
    return _materials.size()
