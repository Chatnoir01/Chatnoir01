extends Node
class_name BrusselsWorldStreamer

const CELL_ID := "bxl-e149000-n169000-s500"
const MANIFEST_PATH := "res://data/urbis/remaining_brussels/cells/bxl-e149000-n169000-s500/manifest.json"
const RUNTIME_CELL_PATH := "res://data/urbis/remaining_brussels/cells/bxl-e149000-n169000-s500/runtime/cell.game.json"
const IXELLES_STREAMED_SCRIPT_PATH := "res://game/zones/ixelles/ixelles_streamed_microslice.gd"
const IXELLES_CAMERA_AXIS_ID := "https://databrussels.be/id/streetaxe/71374:1"
const IXELLES_TARGET_AXIS_ID := "https://databrussels.be/id/streetaxe/71306:2"
const IXELLES_CAMERA_AXIS_T := 0.68
const IXELLES_BODY_CLEARANCE_M := 0.90

@export var update_interval_seconds := 0.20
@export var visual_load_radius_m := 650.0
@export var visual_unload_radius_m := 850.0
@export var collision_radius_m := 260.0
@export var lookahead_seconds := 4.0
@export var max_operations_per_tick := 2
@export var max_active_cells := 9

var _manager: BrusselsCellStreamingManager
var _backend: BrusselsCellNodeBackend
var _update_accumulator := 0.0
var _ixelles_world_center := Vector3.ZERO
var _registered := false
var _fast_travel_running := false

func _ready() -> void:
    _manager = BrusselsCellStreamingManager.new()
    _manager.name = "CellScheduler"
    _manager.visual_load_radius_m = visual_load_radius_m
    _manager.visual_unload_radius_m = visual_unload_radius_m
    _manager.collision_radius_m = collision_radius_m
    _manager.lookahead_seconds = lookahead_seconds
    _manager.max_operations_per_tick = max_operations_per_tick
    _manager.max_active_cells = max_active_cells
    add_child(_manager)

    _backend = BrusselsCellNodeBackend.new()
    _backend.name = "CellBackend"
    add_child(_backend)
    _backend.bind_manager(_manager)

    _registered = _register_ixelles_cell()
    if not _registered:
        push_error("BrusselsWorldStreamer: failed to register committed Ixelles cell")
        set_process(false)
        return
    _update_from_gameplay_observer()

func _process(delta: float) -> void:
    if not _registered:
        return
    _update_accumulator += delta
    if _update_accumulator < update_interval_seconds:
        return
    _update_accumulator = 0.0
    _update_from_gameplay_observer()

func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    return parsed as Dictionary

func _register_ixelles_cell() -> bool:
    var manifest := _read_json(MANIFEST_PATH)
    var runtime_cell := _read_json(RUNTIME_CELL_PATH)
    if manifest.is_empty() or runtime_cell.is_empty():
        return false
    var bbox_raw: Variant = manifest.get("bbox", [])
    var coords: Variant = runtime_cell.get("coordinate_system", {})
    if not bbox_raw is Array or bbox_raw.size() != 4 or not coords is Dictionary:
        return false
    if not bool(coords.get("coordinates_are_current_game_world", false)):
        return false
    var center_e := (float(bbox_raw[0]) + float(bbox_raw[2])) * 0.5
    var center_n := (float(bbox_raw[1]) + float(bbox_raw[3])) * 0.5
    var origin_e := float(coords.get("lambert_origin_e", 0.0))
    var origin_n := float(coords.get("lambert_origin_n", 0.0))
    var anchor_x := float(coords.get("world_anchor_x", 0.0))
    var anchor_z := float(coords.get("world_anchor_z", 0.0))
    _ixelles_world_center = Vector3(anchor_x + (center_e - origin_e), 0.0, anchor_z - (center_n - origin_n))
    if not _backend.register_script_cell(CELL_ID, IXELLES_STREAMED_SCRIPT_PATH, {"build_collision": false}):
        return false
    return _manager.register_manifest_dict(manifest, _ixelles_world_center)

func _update_from_gameplay_observer() -> void:
    var observer := _gameplay_observer()
    if observer == null:
        return
    _manager.update_observer(observer.global_position, _node_velocity(observer))

func _gameplay_observer() -> Node3D:
    for candidate: Node in get_tree().get_nodes_in_group("vehicle"):
        if candidate is Node3D and candidate.has_method("has_driver") and bool(candidate.call("has_driver")):
            return candidate as Node3D
    var player := get_parent().get_node_or_null("Player")
    if player is Node3D:
        return player as Node3D
    return null

func _node_velocity(node: Node3D) -> Vector3:
    if node is RigidBody3D:
        return (node as RigidBody3D).linear_velocity
    if node is CharacterBody3D:
        return (node as CharacterBody3D).velocity
    return Vector3.ZERO

func request_ixelles_fast_travel(player: Node) -> bool:
    if _fast_travel_running or not _registered or player == null:
        return false
    _fast_travel_running = true
    call_deferred("_perform_ixelles_fast_travel", player)
    return true

func _perform_ixelles_fast_travel(player: Node) -> void:
    _set_loading_label("IXELLES · CHARGEMENT DE LA ZONE…")
    _manager.update_observer(_ixelles_world_center, Vector3.ZERO)

    var instance: Node = null
    for _frame_index: int in range(120):
        await get_tree().process_frame
        if _backend.has_active_instance(CELL_ID):
            instance = _backend.get_instance(CELL_ID)
            if is_instance_valid(instance) and bool(instance.get("runtime_loaded")) and instance.find_child("OfficialIxellesDTMCollision", true, false) != null:
                break
    if not is_instance_valid(instance) or not bool(instance.get("runtime_loaded")):
        push_error("BrusselsWorldStreamer: Ixelles fast travel timed out waiting for visual cell")
        _fast_travel_running = false
        return
    if instance.find_child("OfficialIxellesDTMCollision", true, false) == null:
        push_error("BrusselsWorldStreamer: Ixelles fast travel timed out waiting for collision tier")
        _fast_travel_running = false
        return

    var spawn := _ixelles_source_backed_spawn(instance)
    if spawn.is_empty():
        push_error("BrusselsWorldStreamer: source-backed Ixelles spawn unavailable")
        _fast_travel_running = false
        return
    if not _place_player(player, spawn["position"], float(spawn["yaw_degrees"])):
        push_error("BrusselsWorldStreamer: player could not be placed at streamed Ixelles spawn")
        _fast_travel_running = false
        return
    _set_loading_label("IXELLES · PLACE STÉPHANIE / STEFANIA")
    _fast_travel_running = false

func _place_player(player: Node, position: Vector3, yaw_degrees: float) -> bool:
    if not player is Node3D:
        return false
    # Reuse the existing public fast-travel reset path for vehicle exit, camera,
    # locomotion windows and HUD restoration before applying the sourced target.
    if player.has_method("fast_travel_to"):
        player.call("fast_travel_to", "bourse")
    var player_3d := player as Node3D
    player_3d.global_position = position
    player_3d.rotation_degrees.y = yaw_degrees
    if player is CharacterBody3D:
        (player as CharacterBody3D).velocity = Vector3.ZERO
    return true

func _ixelles_source_backed_spawn(instance: Node) -> Dictionary:
    var camera_axis := _axis_segment(instance, IXELLES_CAMERA_AXIS_ID)
    var target_axis := _axis_segment(instance, IXELLES_TARGET_AXIS_ID)
    if camera_axis.size() != 2 or target_axis.size() != 2:
        return {}
    var camera_xz := camera_axis[0].lerp(camera_axis[1], IXELLES_CAMERA_AXIS_T)
    if not _inside_official_street_surface(instance, camera_xz):
        return {}
    var ground := float(instance.call("sample_height", camera_xz.x, camera_xz.y))
    if not is_finite(ground):
        return {}
    var target_xz := target_axis[1]
    var to_target := Vector2(target_xz.x - camera_xz.x, target_xz.y - camera_xz.y)
    var yaw := rad_to_deg(atan2(-to_target.x, -to_target.y))
    return {
        "position": Vector3(camera_xz.x, ground + IXELLES_BODY_CLEARANCE_M, camera_xz.y),
        "yaw_degrees": yaw,
    }

func _axis_segment(instance: Node, axis_id: String) -> PackedVector2Array:
    var network: Dictionary = instance.get_meta("ixelles_network_contract", {})
    var axes: Variant = network.get("street_axes", [])
    if not axes is Array:
        return PackedVector2Array()
    for raw: Variant in axes:
        if not raw is Dictionary or str(raw.get("id", "")) != axis_id:
            continue
        var points: Variant = raw.get("points", [])
        if not points is Array or points.size() != 2:
            return PackedVector2Array()
        var result := PackedVector2Array()
        for point: Variant in points:
            if not point is Array or point.size() < 2:
                return PackedVector2Array()
            result.append(Vector2(float(point[0]), float(point[1])))
        return result
    return PackedVector2Array()

func _inside_official_street_surface(instance: Node, point: Vector2) -> bool:
    var cell: Dictionary = instance.get_meta("ixelles_cell_contract", {})
    var surfaces: Variant = cell.get("street_surfaces", [])
    if not surfaces is Array:
        return false
    for raw: Variant in surfaces:
        if not raw is Dictionary:
            continue
        var polygon_raw: Variant = raw.get("polygon", [])
        if not polygon_raw is Array or polygon_raw.size() < 3:
            continue
        var polygon := PackedVector2Array()
        for pair: Variant in polygon_raw:
            if pair is Array and pair.size() >= 2:
                polygon.append(Vector2(float(pair[0]), float(pair[1])))
        if polygon.size() >= 3 and Geometry2D.is_point_in_polygon(point, polygon):
            return true
    return false

func _set_loading_label(text: String) -> void:
    var label := get_parent().get_node_or_null("LocationLabel")
    if label != null and label.has_method("set_forced_label"):
        label.call("set_forced_label", text)
    elif label is Label:
        (label as Label).text = text

func get_streaming_manager() -> BrusselsCellStreamingManager:
    return _manager

func get_backend() -> BrusselsCellNodeBackend:
    return _backend

func get_ixelles_world_center() -> Vector3:
    return _ixelles_world_center

func is_ixelles_active() -> bool:
    return is_instance_valid(_backend) and _backend.has_active_instance(CELL_ID)

func get_metrics() -> Dictionary:
    return {
        "registered": _registered,
        "ixelles_center": _ixelles_world_center,
        "scheduler": _manager.get_metrics() if is_instance_valid(_manager) else {},
        "backend": _backend.get_metrics() if is_instance_valid(_backend) else {},
    }

func force_observer_for_test(position: Vector3, velocity: Vector3 = Vector3.ZERO) -> void:
    if is_instance_valid(_manager):
        _manager.update_observer(position, velocity)
