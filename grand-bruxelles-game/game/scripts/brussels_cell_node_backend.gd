extends Node
class_name BrusselsCellNodeBackend

## Runtime adapter between BrusselsCellStreamingManager decisions and Godot nodes.
## Bindings are explicit project resources; this backend never loads external game data.

var _manager: BrusselsCellStreamingManager
var _bindings: Dictionary = {}
var _instances: Dictionary = {}
var _desired_active: Dictionary = {}
var _load_count := 0
var _unload_count := 0
var _failed_load_count := 0

func bind_manager(manager: BrusselsCellStreamingManager) -> void:
    if _manager == manager:
        return
    if is_instance_valid(_manager):
        if _manager.cell_activation_requested.is_connected(_on_activation_requested):
            _manager.cell_activation_requested.disconnect(_on_activation_requested)
        if _manager.cell_deactivation_requested.is_connected(_on_deactivation_requested):
            _manager.cell_deactivation_requested.disconnect(_on_deactivation_requested)
    _manager = manager
    if not is_instance_valid(_manager):
        return
    _manager.cell_activation_requested.connect(_on_activation_requested)
    _manager.cell_deactivation_requested.connect(_on_deactivation_requested)

func register_script_cell(cell_id: String, script_path: String, property_overrides: Dictionary = {}) -> bool:
    if cell_id.is_empty() or script_path.is_empty() or _bindings.has(cell_id):
        return false
    if not ResourceLoader.exists(script_path):
        return false
    _bindings[cell_id] = {
        "script_path": script_path,
        "property_overrides": property_overrides.duplicate(true),
    }
    _desired_active[cell_id] = false
    return true

func _on_activation_requested(cell_id: String, _descriptor: Dictionary) -> void:
    if not _bindings.has(cell_id):
        return
    _desired_active[cell_id] = true
    call_deferred("_instantiate_cell", cell_id)

func _on_deactivation_requested(cell_id: String) -> void:
    if not _bindings.has(cell_id):
        return
    _desired_active[cell_id] = false
    call_deferred("_release_cell", cell_id)

func _instantiate_cell(cell_id: String) -> void:
    if not bool(_desired_active.get(cell_id, false)) or _instances.has(cell_id):
        return
    var binding: Dictionary = _bindings[cell_id]
    var script_path := str(binding.get("script_path", ""))
    var resource: Resource = ResourceLoader.load(script_path)
    if not resource is Script:
        _failed_load_count += 1
        return
    var instance_variant: Variant = (resource as Script).new()
    if not instance_variant is Node:
        _failed_load_count += 1
        return
    var instance := instance_variant as Node
    var overrides: Dictionary = binding.get("property_overrides", {})
    for property_name: String in overrides.keys():
        instance.set(property_name, overrides[property_name])
    instance.name = "StreamedCell_%s" % cell_id
    instance.set_meta("streamed_cell_id", cell_id)
    add_child(instance)
    _instances[cell_id] = instance
    _load_count += 1

func _release_cell(cell_id: String) -> void:
    if not _instances.has(cell_id):
        return
    var instance: Node = _instances[cell_id]
    _instances.erase(cell_id)
    if is_instance_valid(instance):
        instance.queue_free()
    _unload_count += 1

func has_active_instance(cell_id: String) -> bool:
    if not _instances.has(cell_id):
        return false
    return is_instance_valid(_instances[cell_id]) and not (_instances[cell_id] as Node).is_queued_for_deletion()

func get_instance(cell_id: String) -> Node:
    if not has_active_instance(cell_id):
        return null
    return _instances[cell_id]

func get_metrics() -> Dictionary:
    return {
        "active_instances": _instances.size(),
        "load_count": _load_count,
        "unload_count": _unload_count,
        "failed_load_count": _failed_load_count,
    }
