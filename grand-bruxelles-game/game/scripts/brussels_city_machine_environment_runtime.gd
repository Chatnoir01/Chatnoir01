extends Node
class_name BrusselsCityMachineEnvironmentRuntime

## Deterministic runtime bridge for City Machine OSM environment artifacts.
## The index is discovery-only and never authorizes promotion, collision, or
## gameplay truth. Individual source artifacts are revalidated before mounting.

const INDEX_PATH := "res://data/runtime/runtime_environment_index.json"
const INDEX_FORMAT := "grand-bruxelles-runtime-environment-index-v1"
const ARTIFACT_FORMAT := "grand-bruxelles-osm-zone-environment-v1"
const OSM_SOURCE := "OpenStreetMap contributors via Overpass API"
const OSM_LICENSE := "ODbL-1.0"
const RENDERER_SCRIPT := preload("res://game/scripts/brussels_osm_environment_runtime.gd")

@export var activation_margin_m := 450.0
@export var unload_margin_m := 700.0
@export var refresh_interval_s := 0.50

var runtime_ready := false
var discovered_zone_count := 0
var _entries: Array[Dictionary] = []
var _active: Dictionary = {}
var _refresh_accumulator := 0.0


func _ready() -> void:
    if activation_margin_m < 0.0 or unload_margin_m <= activation_margin_m:
        push_error("BrusselsCityMachineEnvironmentRuntime: invalid activation/unload margins")
        return
    if not _load_index():
        return
    runtime_ready = true
    _refresh(true)
    print("BRUSSELS_CITY_MACHINE_ENVIRONMENT_READY: zones=%d index=deterministic visual_only=true" % discovered_zone_count)


func _process(delta: float) -> void:
    if not runtime_ready:
        return
    _refresh_accumulator += delta
    if _refresh_accumulator < refresh_interval_s:
        return
    _refresh_accumulator = 0.0
    _refresh(false)


func _read_json(path: String) -> Dictionary:
    if path.is_empty() or not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    return parsed as Dictionary


func _numeric_arrays_match(left: Variant, right: Variant) -> bool:
    if not left is Array or not right is Array or left.size() != right.size():
        return false
    for index: int in range(left.size()):
        if not is_equal_approx(float(left[index]), float(right[index])):
            return false
    return true


func _stats_match(left: Variant, right: Variant) -> bool:
    if not left is Dictionary or not right is Dictionary:
        return false
    for key: String in ["tree", "street_lamp", "bollard", "total"]:
        if int(left.get(key, -1)) != int(right.get(key, -2)):
            return false
    return int(left.get("tree", 0)) > 0 and int(left.get("total", 0)) > 0


func _artifact_contract_valid(entry: Dictionary) -> bool:
    var zone := str(entry.get("zone", ""))
    var data_path := str(entry.get("data_path", ""))
    if zone.is_empty() or not data_path.begins_with("res://data/osm/zones/") or not data_path.ends_with("/environment.game.json"):
        return false
    var artifact := _read_json(data_path)
    if artifact.is_empty():
        return false
    if str(artifact.get("format", "")) != ARTIFACT_FORMAT or str(entry.get("artifact_format", "")) != ARTIFACT_FORMAT:
        return false
    if str(artifact.get("zone", "")) != zone:
        return false
    if str(artifact.get("source", "")) != OSM_SOURCE or str(artifact.get("license", "")) != OSM_LICENSE:
        return false
    if str(artifact.get("projection_crs", "")) != "EPSG:31370":
        return false
    if not _numeric_arrays_match(artifact.get("bounds_m", []), entry.get("bounds_m", [])):
        return false
    if not _stats_match(artifact.get("stats", {}), entry.get("stats", {})):
        return false
    return true


func _load_index() -> bool:
    var index := _read_json(INDEX_PATH)
    if index.is_empty() or str(index.get("format", "")) != INDEX_FORMAT:
        push_error("BrusselsCityMachineEnvironmentRuntime: runtime environment index missing or invalid")
        return false
    if not bool(index.get("visual_only", false)) or bool(index.get("promotion_authorized_by_index", true)):
        push_error("BrusselsCityMachineEnvironmentRuntime: index violated visual-only fail-closed contract")
        return false
    var rows: Variant = index.get("entries", [])
    if not rows is Array or rows.is_empty():
        push_error("BrusselsCityMachineEnvironmentRuntime: index contains no environment entries")
        return false
    var seen_zones := {}
    var seen_paths := {}
    for raw: Variant in rows:
        if not raw is Dictionary:
            push_error("BrusselsCityMachineEnvironmentRuntime: malformed index entry")
            return false
        var entry := raw as Dictionary
        var zone := str(entry.get("zone", ""))
        var data_path := str(entry.get("data_path", ""))
        if zone.is_empty() or seen_zones.has(zone) or seen_paths.has(data_path):
            push_error("BrusselsCityMachineEnvironmentRuntime: duplicate or empty environment identity")
            return false
        if not _artifact_contract_valid(entry):
            push_error("BrusselsCityMachineEnvironmentRuntime: rejected environment artifact for %s" % zone)
            return false
        seen_zones[zone] = true
        seen_paths[data_path] = true
        _entries.append(entry.duplicate(true))
    _entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("zone", "")) < str(b.get("zone", "")))
    discovered_zone_count = _entries.size()
    return discovered_zone_count > 0


func _target() -> Node3D:
    var player := get_tree().get_first_node_in_group("player") as Node3D
    if player != null:
        return player
    var scene := get_tree().current_scene
    if scene == null:
        return null
    return scene.get_node_or_null("Player") as Node3D


func _distance_to_bounds(point: Vector2, bounds: Array) -> float:
    if bounds.size() != 4:
        return INF
    var min_x := float(bounds[0])
    var min_z := float(bounds[1])
    var max_x := float(bounds[2])
    var max_z := float(bounds[3])
    var dx := 0.0
    var dz := 0.0
    if point.x < min_x:
        dx = min_x - point.x
    elif point.x > max_x:
        dx = point.x - max_x
    if point.y < min_z:
        dz = min_z - point.y
    elif point.y > max_z:
        dz = point.y - max_z
    return Vector2(dx, dz).length()


func _mount(entry: Dictionary) -> void:
    var zone := str(entry.get("zone", ""))
    if _active.has(zone):
        return
    if not _artifact_contract_valid(entry):
        push_error("BrusselsCityMachineEnvironmentRuntime: artifact drift detected before mount for %s" % zone)
        return
    var renderer := RENDERER_SCRIPT.new() as Node
    if renderer == null:
        push_error("BrusselsCityMachineEnvironmentRuntime: renderer instantiation failed for %s" % zone)
        return
    renderer.name = StringName("Environment_%s" % zone.capitalize())
    renderer.set("data_path", str(entry.get("data_path", "")))
    renderer.set_meta("city_machine_zone", zone)
    renderer.set_meta("visual_only", true)
    add_child(renderer)
    _active[zone] = renderer
    print("BRUSSELS_CITY_MACHINE_ENVIRONMENT_MOUNT: zone=%s" % zone)


func _unmount(zone: String) -> void:
    if not _active.has(zone):
        return
    var renderer := _active[zone] as Node
    _active.erase(zone)
    if renderer != null and is_instance_valid(renderer):
        renderer.queue_free()
    print("BRUSSELS_CITY_MACHINE_ENVIRONMENT_UNMOUNT: zone=%s" % zone)


func _refresh(force: bool) -> void:
    var target := _target()
    if target == null:
        return
    var point := Vector2(target.global_position.x, target.global_position.z)
    for entry: Dictionary in _entries:
        var zone := str(entry.get("zone", ""))
        var bounds: Array = entry.get("bounds_m", []) as Array
        var distance := _distance_to_bounds(point, bounds)
        if distance <= activation_margin_m:
            _mount(entry)
        elif distance > unload_margin_m and _active.has(zone):
            _unmount(zone)
        elif force and distance > unload_margin_m:
            _unmount(zone)


func get_environment_metrics() -> Dictionary:
    var active_zones := PackedStringArray()
    for zone_variant: Variant in _active.keys():
        active_zones.append(str(zone_variant))
    active_zones.sort()
    return {
        "runtime_ready": runtime_ready,
        "lookup": "deterministic_runtime_environment_index",
        "visual_only": true,
        "discovered_zones": discovered_zone_count,
        "active_zones": active_zones,
    }
