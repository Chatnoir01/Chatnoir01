extends Node
class_name BrusselsAssetCache

## Small reusable resource cache for streamed Brussels cells.
## Keeps recently used project resources warm across cell unload/reload cycles.
## It only accepts local res:// resources and never fetches external game data.

@export var max_entries := 32

var _entries: Dictionary = {}
var _clock := 0
var _hits := 0
var _misses := 0
var _failed_loads := 0
var _evictions := 0
var _acquires := 0
var _releases := 0

func acquire(path: String) -> Resource:
    _clock += 1
    _acquires += 1
    if path.is_empty() or not path.begins_with("res://"):
        _failed_loads += 1
        return null
    if _entries.has(path):
        var warm: Dictionary = _entries[path]
        var warm_resource: Resource = warm.get("resource")
        if is_instance_valid(warm_resource):
            warm["ref_count"] = int(warm.get("ref_count", 0)) + 1
            warm["last_used"] = _clock
            _entries[path] = warm
            _hits += 1
            return warm_resource
        _entries.erase(path)

    if not ResourceLoader.exists(path):
        _failed_loads += 1
        return null
    var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
    if loaded == null:
        _failed_loads += 1
        return null
    _entries[path] = {
        "resource": loaded,
        "ref_count": 1,
        "last_used": _clock,
    }
    _misses += 1
    _prune_if_needed()
    return loaded

func release(path: String) -> void:
    if not _entries.has(path):
        return
    _clock += 1
    _releases += 1
    var entry: Dictionary = _entries[path]
    entry["ref_count"] = maxi(int(entry.get("ref_count", 0)) - 1, 0)
    entry["last_used"] = _clock
    _entries[path] = entry
    _prune_if_needed()

func _prune_if_needed() -> void:
    var limit := maxi(max_entries, 1)
    while _entries.size() > limit:
        var victim := ""
        var oldest := 9223372036854775807
        for path: String in _entries.keys():
            var entry: Dictionary = _entries[path]
            if int(entry.get("ref_count", 0)) > 0:
                continue
            var last_used := int(entry.get("last_used", 0))
            if last_used < oldest:
                oldest = last_used
                victim = path
        if victim.is_empty():
            break
        _entries.erase(victim)
        _evictions += 1

func clear_unreferenced() -> void:
    var removable: Array[String] = []
    for path: String in _entries.keys():
        if int((_entries[path] as Dictionary).get("ref_count", 0)) == 0:
            removable.append(path)
    for path: String in removable:
        _entries.erase(path)
        _evictions += 1

func is_warm(path: String) -> bool:
    return _entries.has(path) and is_instance_valid((_entries[path] as Dictionary).get("resource"))

func get_ref_count(path: String) -> int:
    if not _entries.has(path):
        return 0
    return int((_entries[path] as Dictionary).get("ref_count", 0))

func get_metrics() -> Dictionary:
    var referenced := 0
    for path: String in _entries.keys():
        if int((_entries[path] as Dictionary).get("ref_count", 0)) > 0:
            referenced += 1
    return {
        "entries": _entries.size(),
        "referenced_entries": referenced,
        "hits": _hits,
        "misses": _misses,
        "failed_loads": _failed_loads,
        "evictions": _evictions,
        "acquires": _acquires,
        "releases": _releases,
    }
