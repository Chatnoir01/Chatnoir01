extends Node
class_name BrusselsCellNodeBackend

## Runtime adapter between BrusselsCellStreamingManager decisions and Godot nodes.
## Bindings are explicit project resources; this backend never loads external game data.

const ASSET_CACHE_SCRIPT := preload("res://game/scripts/brussels_asset_cache.gd")

var _manager: BrusselsCellStreamingManager
var _asset_cache: BrusselsAssetCache
var _bindings: Dictionary = {}
var _instances: Dictionary = {}
var _desired_active: Dictionary = {}
var _desired_collision: Dictionary = {}
var _load_count := 0
var _unload_count := 0
var _failed_load_count := 0
var _collision_enable_count := 0
var _collision_disable_count := 0

func _ready() -> void:
    if not is_instance_valid(_asset_cache):
        _asset_cache = ASSET_CACHE_SCRIPT.new() as BrusselsAssetCache
        _asset_cache.name = "BrusselsAssetCache"
        add_child(_asset_cache)

func bind_asset_cache(cache: BrusselsAssetCache) -> void:
    if cache == _asset_cache:
        return
    if is_instance_valid(_asset_cache) and _asset_cache.get_parent() == self:
        _asset_cache.queue_free()
    _asset_cache = cache

func bind_manager(manager: BrusselsCellStreamingManager) -> void:
    if _manager == manager:
        return
    if is_instance_valid(_manager):
        if _manager.cell_activation_requested.is_connected(_on_activation_requested):
            _manager.cell_activation_requested.disconnect(_on_activation_requested)
        if _manager.cell_deactivation_requested.is_connected(_on_deactivation_requested):
            _manager.cell_deactivation_requested.disconnect(_on_deactivation_requested)
        if _manager.collision_tier_changed.is_connected(_on_collision_tier_changed):
            _manager.collision_tier_changed.disconnect(_on_collision_tier_changed)
    _manager = manager
    if not is_instance_valid(_manager):
        return
    _manager.cell_activation_requested.connect(_on_activation_requested)
    _manager.cell_deactivation_requested.connect(_on_deactivation_requested)
    _manager.collision_tier_changed.connect(_on_collision_tier_changed)

func register_script_cell(cell_id: String, script_path: String, property_overrides: Dictionary = {}) -> bool:
    if cell_id.is_empty() or script_path.is_empty() or _bindings.has(cell_id):
        return false
    if not script_path.begins_with("res://") or not ResourceLoader.exists(script_path):
        return false
    _bindings[cell_id] = {
        "script_path": script_path,
        "property_overrides": property_overrides.duplicate(true),
    }
    _desired_active[cell_id] = false
    _desired_collision[cell_id] = false
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
    _desired_collision[cell_id] = false
    call_deferred("_release_cell", cell_id)

func _on_collision_tier_changed(cell_id: String, enabled: bool) -> void:
    if not _bindings.has(cell_id):
        return
    _desired_collision[cell_id] = enabled
    call_deferred("_apply_collision_tier", cell_id)

func _instantiate_cell(cell_id: String) -> void:
    if not bool(_desired_active.get(cell_id, false)) or _instances.has(cell_id):
        return
    if not is_instance_valid(_asset_cache):
        _ready()
    var binding: Dictionary = _bindings[cell_id]
    var script_path := str(binding.get("script_path", ""))
    var resource: Resource = _asset_cache.acquire(script_path) if is_instance_valid(_asset_cache) else ResourceLoader.load(script_path)
    if not resource is Script:
        if is_instance_valid(_asset_cache):
            _asset_cache.release(script_path)
        _failed_load_count += 1
        return
    var instance_variant: Variant = (resource as Script).new()
    if not instance_variant is Node:
        if is_instance_valid(_asset_cache):
            _asset_cache.release(script_path)
        _failed_load_count += 1
        return
    var instance := instance_variant as Node
    var overrides: Dictionary = binding.get("property_overrides", {})
    for property_name: String in overrides.keys():
        instance.set(property_name, overrides[property_name])
    instance.name = "StreamedCell_%s" % cell_id
    instance.set_meta("streamed_cell_id", cell_id)
    instance.set_meta("streamed_resource_path", script_path)
    add_child(instance)
    _instances[cell_id] = instance
    _load_count += 1
    call_deferred("_apply_collision_tier", cell_id)

func _apply_collision_tier(cell_id: String) -> void:
    if not has_active_instance(cell_id):
        return
    var instance := _instances[cell_id] as Node
    if not instance.has_method("set_streamed_collision_enabled"):
        return
    var enabled := bool(_desired_collision.get(cell_id, false))
    var before := false
    if instance.has_method("is_streamed_collision_enabled"):
        before = bool(instance.call("is_streamed_collision_enabled"))
    instance.call("set_streamed_collision_enabled", enabled)
    if before != enabled:
        if enabled:
            _collision_enable_count += 1
        else:
            _collision_disable_count += 1

func _release_cell(cell_id: String) -> void:
    if not _instances.has(cell_id):
        return
    var instance: Node = _instances[cell_id]
    _instances.erase(cell_id)
    var script_path := ""
    if is_instance_valid(instance):
        script_path = str(instance.get_meta("streamed_resource_path", ""))
        instance.queue_free()
    if not script_path.is_empty() and is_instance_valid(_asset_cache):
        _asset_cache.release(script_path)
    _unload_count += 1

func has_active_instance(cell_id: String) -> bool:
    if not _instances.has(cell_id):
        return false
    return is_instance_valid(_instances[cell_id]) and not (_instances[cell_id] as Node).is_queued_for_deletion()

func get_instance(cell_id: String) -> Node:
    if not has_active_instance(cell_id):
        return null
    return _instances[cell_id]

func get_asset_cache_metrics() -> Dictionary:
    if not is_instance_valid(_asset_cache):
        return {}
    return _asset_cache.get_metrics()

func get_metrics() -> Dictionary:
    return {
        "active_instances": _instances.size(),
        "load_count": _load_count,
        "unload_count": _unload_count,
        "failed_load_count": _failed_load_count,
        "collision_enable_count": _collision_enable_count,
        "collision_disable_count": _collision_disable_count,
        "asset_cache": get_asset_cache_metrics(),
    }
