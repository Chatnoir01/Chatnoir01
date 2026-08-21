extends Node
class_name BrusselsWorldStreamingRuntime

## Production bridge for the clean-room Brussels cell streamer.
## Tracks the real player/driven vehicle and discovers source-backed, pregenerated
## runtime cell bundles instead of maintaining a hand-authored cell allowlist.
## Discovery is fail-closed: incomplete, malformed or identity-mismatched bundles
## are ignored and can never be promoted implicitly.

const STREAMER_SCRIPT := preload("res://game/scripts/brussels_cell_streaming_manager.gd")
const BACKEND_SCRIPT := preload("res://game/scripts/brussels_cell_node_backend.gd")
const CELL_SOURCE_ROOT := "res://data/urbis/remaining_brussels/cells"
const IXELLES_STREAMED_CELL_ID := "bxl-e149000-n169000-s500"
const IXELLES_STREAMED_SCRIPT_PATH := "res://game/zones/ixelles/ixelles_streamed_microslice.gd"
const SOURCE_PLAN_STREAMED_SCRIPT_PATH := "res://game/scripts/brussels_source_plan_streamed_cell.gd"
const BUILT_CELL_FORMAT := "grand-bruxelles-urbis-built-cell-v1"
const RUNTIME_CELL_FORMAT := "grand-bruxelles-urbis-cell-runtime-v1"
const RUNTIME_NETWORK_FORMAT := "grand-bruxelles-urbis-network-cell-runtime-v2"
const EXPECTED_CRS := "EPSG:31370"
const RUNTIME_CELL_RELATIVE_PATH := "runtime/cell.game.json"
const RUNTIME_NETWORK_RELATIVE_PATH := "runtime/network.game.json"
const STRONG_HEIGHT_ROOTS := [
    "res://data/terrain/ixelles",
]

@export var visual_load_radius_m := 650.0
@export var visual_unload_radius_m := 850.0
@export var collision_radius_m := 260.0
@export var lookahead_seconds := 4.0
@export var max_operations_per_tick := 1
@export var max_active_cells := 4

var manager: BrusselsCellStreamingManager
var backend: BrusselsCellNodeBackend
var runtime_ready := false
var disabled_for_direct_ixelles := false
var discovered_cell_count := 0
var runtime_cell_descriptors: Array[Dictionary] = []
var _player: CharacterBody3D
var _last_observer_position := Vector3.ZERO
var _has_last_observer := false
var _destination_preload_active := false
var _destination_preload_cell_id := ""
var _destination_preload_position := Vector3.ZERO


func _ready() -> void:
    disabled_for_direct_ixelles = _has_direct_ixelles_spawn(OS.get_cmdline_user_args())
    if disabled_for_direct_ixelles:
        set_meta("streaming_disabled_reason", "direct_ixelles_spawn")
        return
    _player = get_parent().get_node_or_null("Player") as CharacterBody3D
    if _player == null:
        push_error("BrusselsWorldStreamingRuntime: Player node unavailable")
        return

    manager = STREAMER_SCRIPT.new() as BrusselsCellStreamingManager
    manager.name = "CellStreamingManager"
    manager.visual_load_radius_m = visual_load_radius_m
    manager.visual_unload_radius_m = visual_unload_radius_m
    manager.collision_radius_m = collision_radius_m
    manager.lookahead_seconds = lookahead_seconds
    manager.max_operations_per_tick = max_operations_per_tick
    manager.max_active_cells = max_active_cells
    add_child(manager)

    backend = BACKEND_SCRIPT.new() as BrusselsCellNodeBackend
    backend.name = "CellStreamingBackend"
    add_child(backend)
    backend.bind_manager(manager)

    runtime_cell_descriptors = discover_runtime_cell_descriptors()
    discovered_cell_count = runtime_cell_descriptors.size()
    if discovered_cell_count == 0:
        push_error("BrusselsWorldStreamingRuntime: no valid pregenerated runtime cells discovered")
        return
    var registered_count := _register_runtime_cells(runtime_cell_descriptors)
    if registered_count != discovered_cell_count:
        push_error("BrusselsWorldStreamingRuntime: runtime cell registration incomplete %d/%d" % [registered_count, discovered_cell_count])
        return
    runtime_ready = true
    _feed_observer()
    print("BRUSSELS_WORLD_STREAMING_READY: cells=%d visual=%.0fm collision=%.0fm" % [int(manager.get_metrics().get("registered_cells", 0)), visual_load_radius_m, collision_radius_m])


func _physics_process(_delta: float) -> void:
    if not runtime_ready:
        return
    if _destination_preload_active:
        manager.update_observer(_destination_preload_position, Vector3.ZERO)
        return
    _feed_observer()


func _has_direct_ixelles_spawn(args: PackedStringArray) -> bool:
    for arg: String in args:
        if arg.strip_edges().to_lower() == "spawn=ixelles":
            return true
    return false


func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    return parsed as Dictionary


func _is_canonical_cell_id(cell_id: String) -> bool:
    var parts := cell_id.split("-", false)
    if parts.size() != 4 or parts[0] != "bxl" or parts[3] != "s500":
        return false
    if not parts[1].begins_with("e") or not parts[2].begins_with("n"):
        return false
    var raw_easting := parts[1].trim_prefix("e")
    var raw_northing := parts[2].trim_prefix("n")
    return not raw_easting.is_empty() and raw_easting.is_valid_int() and not raw_northing.is_empty() and raw_northing.is_valid_int()


func _world_center_from_contract(manifest: Dictionary, runtime_cell: Dictionary) -> Vector3:
    var bbox: Variant = manifest.get("bbox", [])
    var coords: Variant = runtime_cell.get("coordinate_system", {})
    if not bbox is Array or bbox.size() != 4 or not coords is Dictionary:
        return Vector3.INF
    if not bool((coords as Dictionary).get("coordinates_are_current_game_world", false)):
        return Vector3.INF
    var center_e := (float(bbox[0]) + float(bbox[2])) * 0.5
    var center_n := (float(bbox[1]) + float(bbox[3])) * 0.5
    var origin_e := float((coords as Dictionary).get("lambert_origin_e", 0.0))
    var origin_n := float((coords as Dictionary).get("lambert_origin_n", 0.0))
    var anchor_x := float((coords as Dictionary).get("world_anchor_x", 0.0))
    var anchor_z := float((coords as Dictionary).get("world_anchor_z", 0.0))
    return Vector3(anchor_x + (center_e - origin_e), 0.0, anchor_z - (center_n - origin_n))


func _strong_heights_path(cell_id: String) -> String:
    for root: String in STRONG_HEIGHT_ROOTS:
        var candidate := root.path_join("%s_strong_heights.game.json" % cell_id)
        if FileAccess.file_exists(candidate):
            return candidate
    return ""


func _descriptor_for_runtime_cell(root_path: String, cell_id: String) -> Dictionary:
    if not _is_canonical_cell_id(cell_id):
        return {}
    var base_path := root_path.path_join(cell_id)
    var manifest_path := base_path.path_join("manifest.json")
    var runtime_cell_path := base_path.path_join(RUNTIME_CELL_RELATIVE_PATH)
    var runtime_network_path := base_path.path_join(RUNTIME_NETWORK_RELATIVE_PATH)
    if not FileAccess.file_exists(manifest_path) or not FileAccess.file_exists(runtime_cell_path) or not FileAccess.file_exists(runtime_network_path):
        return {}

    var manifest := _read_json(manifest_path)
    var runtime_cell := _read_json(runtime_cell_path)
    var runtime_network := _read_json(runtime_network_path)
    if manifest.is_empty() or runtime_cell.is_empty() or runtime_network.is_empty():
        return {}
    if str(manifest.get("format", "")) != BUILT_CELL_FORMAT or str(manifest.get("crs", "")) != EXPECTED_CRS:
        return {}
    if str(manifest.get("cell_id", "")) != cell_id or str(runtime_cell.get("cell_id", "")) != cell_id or str(runtime_network.get("cell_id", "")) != cell_id:
        return {}
    if str(runtime_cell.get("format", "")) != RUNTIME_CELL_FORMAT or str(runtime_network.get("format", "")) != RUNTIME_NETWORK_FORMAT:
        return {}

    var runtime_contract: Variant = manifest.get("runtime", {})
    if not runtime_contract is Dictionary:
        return {}
    var runtime_dict := runtime_contract as Dictionary
    if str(runtime_dict.get("geometry_file", "")) != RUNTIME_CELL_RELATIVE_PATH or str(runtime_dict.get("geometry_format", "")) != RUNTIME_CELL_FORMAT:
        return {}
    if str(runtime_dict.get("network_file", "")) != RUNTIME_NETWORK_RELATIVE_PATH or str(runtime_dict.get("network_format", "")) != RUNTIME_NETWORK_FORMAT:
        return {}
    if not _world_center_from_contract(manifest, runtime_cell).is_finite():
        return {}

    var script_path := SOURCE_PLAN_STREAMED_SCRIPT_PATH
    var metadata: Dictionary = {"build_collision": false}
    var destination_collision_authorized := false
    if cell_id == IXELLES_STREAMED_CELL_ID:
        script_path = IXELLES_STREAMED_SCRIPT_PATH
        destination_collision_authorized = true
    else:
        metadata["manifest_path"] = manifest_path
        metadata["runtime_cell_path"] = runtime_cell_path
        metadata["runtime_network_path"] = runtime_network_path
        metadata["strong_heights_path"] = _strong_heights_path(cell_id)

    return {
        "cell_id": cell_id,
        "manifest_path": manifest_path,
        "runtime_cell_path": runtime_cell_path,
        "runtime_network_path": runtime_network_path,
        "script_path": script_path,
        "destination_collision_authorized": destination_collision_authorized,
        "metadata": metadata,
    }


func discover_runtime_cell_descriptors(root_path: String = CELL_SOURCE_ROOT) -> Array[Dictionary]:
    var descriptors: Array[Dictionary] = []
    var directory := DirAccess.open(root_path)
    if directory == null:
        return descriptors

    var cell_ids := PackedStringArray()
    directory.list_dir_begin()
    var entry := directory.get_next()
    while not entry.is_empty():
        if directory.current_is_dir() and entry != "." and entry != ".." and _is_canonical_cell_id(entry):
            cell_ids.append(entry)
        entry = directory.get_next()
    directory.list_dir_end()
    cell_ids.sort()

    for cell_id: String in cell_ids:
        var descriptor := _descriptor_for_runtime_cell(root_path, cell_id)
        if not descriptor.is_empty():
            descriptors.append(descriptor)
    return descriptors


func _register_runtime_cells(descriptors: Array[Dictionary]) -> int:
    var registered_count := 0
    for descriptor: Dictionary in descriptors:
        var cell_id := str(descriptor.get("cell_id", ""))
        var manifest_path := str(descriptor.get("manifest_path", ""))
        var runtime_cell_path := str(descriptor.get("runtime_cell_path", ""))
        var script_path := str(descriptor.get("script_path", ""))
        var manifest := _read_json(manifest_path)
        var runtime_cell := _read_json(runtime_cell_path)
        var center := _world_center_from_contract(manifest, runtime_cell)
        if manifest.is_empty() or runtime_cell.is_empty() or not center.is_finite():
            push_error("BrusselsWorldStreamingRuntime: invalid discovered contract %s" % cell_id)
            continue

        var metadata: Dictionary = (descriptor.get("metadata", {}) as Dictionary).duplicate(true)
        if not backend.register_script_cell(cell_id, script_path, metadata):
            push_error("BrusselsWorldStreamingRuntime: backend registration failed %s" % cell_id)
            continue
        if not manager.register_manifest_dict(manifest, center):
            push_error("BrusselsWorldStreamingRuntime: scheduler registration failed %s" % cell_id)
            continue
        registered_count += 1
    return registered_count


func get_shipped_cell_contract(cell_id: String) -> Dictionary:
    for descriptor: Dictionary in runtime_cell_descriptors:
        if str(descriptor.get("cell_id", "")) == cell_id:
            return descriptor.duplicate(true)
    return {}


func is_destination_collision_authorized(cell_id: String) -> bool:
    var descriptor := get_shipped_cell_contract(cell_id)
    return not descriptor.is_empty() and bool(descriptor.get("destination_collision_authorized", false))


func begin_destination_preload(cell_id: String, target_position: Vector3) -> bool:
    if not runtime_ready or cell_id.is_empty() or not target_position.is_finite():
        return false
    if not is_destination_collision_authorized(cell_id):
        return false
    if manager.get_cell_descriptor(cell_id).is_empty():
        return false
    if _destination_preload_active and _destination_preload_cell_id != cell_id:
        manager.set_collision_pin(_destination_preload_cell_id, false)
    _destination_preload_active = true
    _destination_preload_cell_id = cell_id
    _destination_preload_position = target_position
    if not manager.set_collision_pin(cell_id, true):
        _destination_preload_active = false
        _destination_preload_cell_id = ""
        return false
    manager.update_observer(target_position, Vector3.ZERO)
    return true


func get_destination_readiness(cell_id: String) -> Dictionary:
    var result := {
        "cell_id": cell_id,
        "collision_authorized": is_destination_collision_authorized(cell_id),
        "preload_active": _destination_preload_active and _destination_preload_cell_id == cell_id,
        "active": false,
        "instance_loaded": false,
        "collision_scheduled": false,
        "collision_enabled": false,
        "authoritative_collision_body": false,
        "ready": false,
    }
    if not runtime_ready or not bool(result["collision_authorized"]):
        return result
    result["active"] = cell_id in manager.get_active_cell_ids()
    result["collision_scheduled"] = manager.is_collision_active(cell_id) and manager.is_collision_pinned(cell_id)
    if not backend.has_active_instance(cell_id):
        return result
    var instance := backend.get_instance(cell_id)
    if instance == null:
        return result
    result["instance_loaded"] = bool(instance.get("runtime_loaded"))
    if not instance.has_method("is_streamed_collision_enabled"):
        return result
    result["collision_enabled"] = bool(instance.call("is_streamed_collision_enabled"))
    result["authoritative_collision_body"] = instance.get_node_or_null("OfficialIxellesDTMCollision") != null
    result["ready"] = bool(result["active"]) and bool(result["instance_loaded"]) and bool(result["collision_scheduled"]) and bool(result["collision_enabled"]) and bool(result["authoritative_collision_body"])
    return result


func get_destination_instance(cell_id: String) -> Node:
    if not runtime_ready or not backend.has_active_instance(cell_id):
        return null
    return backend.get_instance(cell_id)


func finish_destination_preload(cell_id: String) -> void:
    if not runtime_ready:
        return
    if not cell_id.is_empty():
        manager.set_collision_pin(cell_id, false)
    if _destination_preload_cell_id == cell_id:
        _destination_preload_active = false
        _destination_preload_cell_id = ""
        _destination_preload_position = Vector3.ZERO
    _feed_observer()


func _select_observer() -> Node3D:
    for vehicle: Node in get_tree().get_nodes_in_group("vehicle"):
        if vehicle is Node3D and vehicle.has_method("has_driver") and bool(vehicle.call("has_driver")):
            return vehicle as Node3D
    return _player


func _observer_velocity(observer: Node3D) -> Vector3:
    if observer is CharacterBody3D:
        return (observer as CharacterBody3D).velocity
    if observer is RigidBody3D:
        return (observer as RigidBody3D).linear_velocity
    if _has_last_observer:
        return observer.global_position - _last_observer_position
    return Vector3.ZERO


func _feed_observer() -> void:
    var observer := _select_observer()
    if observer == null or not is_instance_valid(observer):
        return
    var velocity := _observer_velocity(observer)
    manager.update_observer(observer.global_position, velocity)
    _last_observer_position = observer.global_position
    _has_last_observer = true


func get_streaming_metrics() -> Dictionary:
    if not runtime_ready:
        return {
            "runtime_ready": false,
            "disabled_for_direct_ixelles": disabled_for_direct_ixelles,
            "discovered_cells": discovered_cell_count,
            "destination_preload_active": _destination_preload_active,
        }
    return {
        "runtime_ready": true,
        "disabled_for_direct_ixelles": false,
        "discovered_cells": discovered_cell_count,
        "destination_preload_active": _destination_preload_active,
        "destination_preload_cell_id": _destination_preload_cell_id,
        "scheduler": manager.get_metrics(),
        "backend": backend.get_metrics(),
    }
