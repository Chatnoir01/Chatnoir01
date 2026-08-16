extends Node
class_name BrusselsWorldStreamingRuntime

## Production bridge for the clean-room Brussels cell streamer.
## Tracks the real player/driven vehicle and feeds source-backed cell manifests
## into BrusselsCellStreamingManager + BrusselsCellNodeBackend.

const STREAMER_SCRIPT := preload("res://game/scripts/brussels_cell_streaming_manager.gd")
const BACKEND_SCRIPT := preload("res://game/scripts/brussels_cell_node_backend.gd")
const IXELLES_STREAMED_SCRIPT_PATH := "res://game/zones/ixelles/ixelles_streamed_microslice.gd"
const SOURCE_PLAN_STREAMED_SCRIPT_PATH := "res://game/scripts/brussels_source_plan_streamed_cell.gd"

const SHIPPED_CELLS: Array[Dictionary] = [
    {
        "cell_id": "bxl-e149000-n169000-s500",
        "manifest_path": "res://data/urbis/remaining_brussels/cells/bxl-e149000-n169000-s500/manifest.json",
        "runtime_cell_path": "res://data/urbis/remaining_brussels/cells/bxl-e149000-n169000-s500/runtime/cell.game.json",
        "runtime_network_path": "res://data/urbis/remaining_brussels/cells/bxl-e149000-n169000-s500/runtime/network.game.json",
        "script_path": IXELLES_STREAMED_SCRIPT_PATH,
        "metadata": {"build_collision": false},
    },
    {
        "cell_id": "bxl-e149000-n169500-s500",
        "manifest_path": "res://data/urbis/remaining_brussels/cells/bxl-e149000-n169500-s500/manifest.json",
        "runtime_cell_path": "res://data/urbis/remaining_brussels/cells/bxl-e149000-n169500-s500/runtime/cell.game.json",
        "runtime_network_path": "res://data/urbis/remaining_brussels/cells/bxl-e149000-n169500-s500/runtime/network.game.json",
        "strong_heights_path": "res://data/terrain/ixelles/bxl-e149000-n169500-s500_strong_heights.game.json",
        "script_path": SOURCE_PLAN_STREAMED_SCRIPT_PATH,
    },
    {
        "cell_id": "bxl-e149500-n169000-s500",
        "manifest_path": "res://data/urbis/remaining_brussels/cells/bxl-e149500-n169000-s500/manifest.json",
        "runtime_cell_path": "res://data/urbis/remaining_brussels/cells/bxl-e149500-n169000-s500/runtime/cell.game.json",
        "runtime_network_path": "res://data/urbis/remaining_brussels/cells/bxl-e149500-n169000-s500/runtime/network.game.json",
        "strong_heights_path": "res://data/terrain/ixelles/bxl-e149500-n169000-s500_strong_heights.game.json",
        "script_path": SOURCE_PLAN_STREAMED_SCRIPT_PATH,
    },
    {
        "cell_id": "bxl-e149500-n169500-s500",
        "manifest_path": "res://data/urbis/remaining_brussels/cells/bxl-e149500-n169500-s500/manifest.json",
        "runtime_cell_path": "res://data/urbis/remaining_brussels/cells/bxl-e149500-n169500-s500/runtime/cell.game.json",
        "runtime_network_path": "res://data/urbis/remaining_brussels/cells/bxl-e149500-n169500-s500/runtime/network.game.json",
        "strong_heights_path": "res://data/terrain/ixelles/bxl-e149500-n169500-s500_strong_heights.game.json",
        "script_path": SOURCE_PLAN_STREAMED_SCRIPT_PATH,
    },
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
var _player: CharacterBody3D
var _last_observer_position := Vector3.ZERO
var _has_last_observer := false


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

    var registered_count := _register_shipped_cells()
    if registered_count != SHIPPED_CELLS.size():
        push_error("BrusselsWorldStreamingRuntime: shipped cell registration incomplete %d/%d" % [registered_count, SHIPPED_CELLS.size()])
        return
    runtime_ready = true
    _feed_observer()
    print("BRUSSELS_WORLD_STREAMING_READY: cells=%d visual=%.0fm collision=%.0fm" % [int(manager.get_metrics().get("registered_cells", 0)), visual_load_radius_m, collision_radius_m])


func _physics_process(_delta: float) -> void:
    if not runtime_ready:
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


func _register_shipped_cells() -> int:
    var registered_count := 0
    for descriptor: Dictionary in SHIPPED_CELLS:
        var cell_id := str(descriptor.get("cell_id", ""))
        var manifest_path := str(descriptor.get("manifest_path", ""))
        var runtime_cell_path := str(descriptor.get("runtime_cell_path", ""))
        var runtime_network_path := str(descriptor.get("runtime_network_path", ""))
        var script_path := str(descriptor.get("script_path", ""))
        var manifest := _read_json(manifest_path)
        var runtime_cell := _read_json(runtime_cell_path)
        if manifest.is_empty() or runtime_cell.is_empty() or str(manifest.get("cell_id", "")) != cell_id or str(runtime_cell.get("cell_id", "")) != cell_id:
            push_error("BrusselsWorldStreamingRuntime: invalid shipped contract %s" % cell_id)
            continue
        var center := _world_center_from_contract(manifest, runtime_cell)
        if not center.is_finite():
            push_error("BrusselsWorldStreamingRuntime: invalid world center %s" % cell_id)
            continue

        var metadata: Dictionary = (descriptor.get("metadata", {}) as Dictionary).duplicate(true)
        if script_path == SOURCE_PLAN_STREAMED_SCRIPT_PATH:
            metadata["manifest_path"] = manifest_path
            metadata["runtime_cell_path"] = runtime_cell_path
            metadata["runtime_network_path"] = runtime_network_path
            metadata["strong_heights_path"] = str(descriptor.get("strong_heights_path", ""))
            metadata["build_collision"] = false
        if not backend.register_script_cell(cell_id, script_path, metadata):
            push_error("BrusselsWorldStreamingRuntime: backend registration failed %s" % cell_id)
            continue
        if not manager.register_manifest_dict(manifest, center):
            push_error("BrusselsWorldStreamingRuntime: scheduler registration failed %s" % cell_id)
            continue
        registered_count += 1
    return registered_count


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
        }
    return {
        "runtime_ready": true,
        "disabled_for_direct_ixelles": false,
        "scheduler": manager.get_metrics(),
        "backend": backend.get_metrics(),
    }
