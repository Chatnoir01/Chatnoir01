extends Node

# ServiceLocator prototype — central point to instantiate services lazily.
# Usage:
#   ServiceLocator.register("TrafficManager", "res://game/scripts/traffic_manager_core.gd")
#   var t = ServiceLocator.get("TrafficManager")

class_name ServiceLocator

static var _registry := {}
static var _instances := {}

static func register(name: String, path: String) -> void:
    _registry[name] = path

static func get(name: String) -> Object:
    if _instances.has(name):
        return _instances[name]
    if not _registry.has(name):
        push_error("ServiceLocator: %s not registered" % name)
        return null
    var path = _registry[name]
    if not ResourceLoader.exists(path):
        push_error("ServiceLocator: resource %s does not exist for %s" % [path, name])
        return null
    var res = load(path)
    var inst = null
    if res is PackedScene:
        inst = res.instantiate()
    elif res is Script:
        inst = res.new()
    else:
        inst = res
    _instances[name] = inst
    return inst

static func clear_instances() -> void:
    for k in _instances.keys():
        var v = _instances[k]
        if v and v.is_inside_tree():
            v.queue_free()
    _instances.clear()

