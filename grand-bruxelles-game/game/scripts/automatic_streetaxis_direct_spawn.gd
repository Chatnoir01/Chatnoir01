extends Node
class_name AutomaticStreetAxisDirectSpawn

## Generic direct-entry resolver for official UrbIS StreetAxis identities.
## It never accepts arbitrary coordinates and never promotes a visual-only cell.
## A destination must be source-backed, collision-authorized, streamed, physically
## grounded on the destination cell and safe to hand back to normal streaming.

const WORLD_STREAMING_SCRIPT := preload("res://game/scripts/brussels_world_streaming_runtime.gd")
const STREETAXIS_SOURCE_PREFIX := "https://databrussels.be/id/streetaxe/"
const REQUEST_PATTERN := "^streetaxis-([1-9][0-9]{0,17})$"
const DEFAULT_TIMEOUT_MS := 30000

var last_result: Dictionary = {}


func _ready() -> void:
    var requested_id := requested_streetaxis_id(OS.get_cmdline_user_args())
    if requested_id > 0:
        call_deferred("_apply_requested_destination", requested_id)


func requested_streetaxis_id(args: PackedStringArray) -> int:
    var regex := RegEx.new()
    if regex.compile(REQUEST_PATTERN) != OK:
        return 0
    for raw_arg: String in args:
        var arg := raw_arg.strip_edges().to_lower()
        if not arg.begins_with("spawn="):
            continue
        var key := arg.trim_prefix("spawn=")
        var match := regex.search(key)
        if match == null:
            continue
        return int(match.get_string(1))
    return 0


func _read_json(path: String) -> Dictionary:
    if path.is_empty() or not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed as Dictionary if parsed is Dictionary else {}


func _segment_points(raw: Variant) -> Array[Vector2]:
    var result: Array[Vector2] = []
    if not raw is Array or raw.size() < 2:
        return result
    for point_raw: Variant in raw:
        if not point_raw is Array or point_raw.size() < 2:
            return []
        result.append(Vector2(float(point_raw[0]), float(point_raw[1])))
    return result


func resolve_streetaxis(streetaxis_id: int) -> Dictionary:
    if streetaxis_id <= 0:
        return {}
    var wanted_source_id := "%s%d" % [STREETAXIS_SOURCE_PREFIX, streetaxis_id]
    for descriptor: Dictionary in WORLD_STREAMING_SCRIPT.SHIPPED_CELLS:
        var cell_id := str(descriptor.get("cell_id", ""))
        var network_path := str(descriptor.get("runtime_network_path", ""))
        var network := _read_json(network_path)
        if network.is_empty() or str(network.get("format", "")) != "grand-bruxelles-urbis-network-cell-runtime-v2" or str(network.get("cell_id", "")) != cell_id:
            continue
        var axes: Variant = network.get("street_axes", [])
        if not axes is Array:
            continue
        var longest_a := Vector2.ZERO
        var longest_b := Vector2.ZERO
        var longest_length := 0.0
        var segment_count := 0
        var street_fr := ""
        var street_nl := ""
        for raw_axis: Variant in axes:
            if not raw_axis is Dictionary:
                continue
            var axis := raw_axis as Dictionary
            if str(axis.get("source_id", "")) != wanted_source_id or str(axis.get("kind", "")) != "street_axis" or str(axis.get("type", "")) != "S":
                continue
            var points := _segment_points(axis.get("points", []))
            if points.size() < 2:
                return {}
            var axis_fr := str(axis.get("street_fr", "")).strip_edges()
            var axis_nl := str(axis.get("street_nl", "")).strip_edges()
            if not axis_fr.is_empty():
                if not street_fr.is_empty() and street_fr != axis_fr:
                    return {}
                street_fr = axis_fr
            if not axis_nl.is_empty():
                if not street_nl.is_empty() and street_nl != axis_nl:
                    return {}
                street_nl = axis_nl
            for index: int in range(points.size() - 1):
                var a := points[index]
                var b := points[index + 1]
                var length := a.distance_to(b)
                if length <= 0.001:
                    continue
                segment_count += 1
                if length > longest_length:
                    longest_length = length
                    longest_a = a
                    longest_b = b
        if segment_count <= 0 or longest_length <= 0.001 or (street_fr.is_empty() and street_nl.is_empty()):
            continue
        var tangent := (longest_b - longest_a).normalized()
        return {
            "streetaxis_id": streetaxis_id,
            "source_id": wanted_source_id,
            "cell_id": cell_id,
            "network_path": network_path,
            "street_fr": street_fr,
            "street_nl": street_nl,
            "segment_count": segment_count,
            "target": (longest_a + longest_b) * 0.5,
            "tangent": tangent,
            "destination_collision_authorized": bool(descriptor.get("destination_collision_authorized", false)),
        }
    return {}


func _find_streamer(node: Node) -> BrusselsWorldStreamingRuntime:
    if node.get_script() == WORLD_STREAMING_SCRIPT:
        return node as BrusselsWorldStreamingRuntime
    for child: Node in node.get_children():
        var found := _find_streamer(child)
        if found != null:
            return found
    return null


func _ensure_streamer(scene: Node) -> BrusselsWorldStreamingRuntime:
    var existing := _find_streamer(scene)
    if existing != null:
        return existing
    var created := WORLD_STREAMING_SCRIPT.new() as BrusselsWorldStreamingRuntime
    created.name = "BrusselsWorldStreamingRuntime"
    scene.add_child(created)
    await get_tree().process_frame
    return created


func _belongs_to(node: Node, ancestor: Node) -> bool:
    var cursor: Node = node
    while cursor != null:
        if cursor == ancestor:
            return true
        cursor = cursor.get_parent()
    return false


func _failure(reason: String, resolved: Dictionary = {}) -> Dictionary:
    var result := {"ok": false, "reason": reason}
    if not resolved.is_empty():
        result["streetaxis_id"] = int(resolved.get("streetaxis_id", 0))
        result["cell_id"] = str(resolved.get("cell_id", ""))
    last_result = result
    return result


func apply_streetaxis_to_player(player: CharacterBody3D, streetaxis_id: int, timeout_ms: int = DEFAULT_TIMEOUT_MS) -> Dictionary:
    if player == null or not is_instance_valid(player):
        return _failure("player_unavailable")
    var resolved := resolve_streetaxis(streetaxis_id)
    if resolved.is_empty():
        return _failure("streetaxis_unresolved")
    if not bool(resolved.get("destination_collision_authorized", false)):
        return _failure("cell_collision_not_authorized", resolved)

    var scene := get_tree().current_scene
    if scene == null:
        scene = player.get_parent()
    if scene == null:
        return _failure("scene_unavailable", resolved)
    var streamer := await _ensure_streamer(scene)
    if streamer == null or not streamer.runtime_ready:
        return _failure("streamer_unavailable", resolved)

    var cell_id := str(resolved["cell_id"])
    if not streamer.is_destination_collision_authorized(cell_id):
        return _failure("streamer_collision_not_authorized", resolved)
    var target_2d: Vector2 = resolved["target"]
    var target_position := Vector3(target_2d.x, 0.0, target_2d.y)
    var cell_descriptor := streamer.manager.get_cell_descriptor(cell_id)
    if cell_descriptor.is_empty():
        return _failure("stream_cell_unregistered", resolved)
    var cell_center: Vector3 = cell_descriptor.get("world_center", Vector3.INF)
    if not cell_center.is_finite():
        return _failure("stream_cell_center_invalid", resolved)
    var handoff_distance := Vector2(target_position.x, target_position.z).distance_to(Vector2(cell_center.x, cell_center.z))
    if handoff_distance > streamer.collision_radius_m:
        return _failure("normal_collision_handoff_not_ready", resolved)

    if not streamer.begin_destination_preload(cell_id, target_position):
        return _failure("destination_preload_refused", resolved)

    var deadline := Time.get_ticks_msec() + maxi(timeout_ms, 1)
    var readiness: Dictionary = {}
    while Time.get_ticks_msec() < deadline:
        readiness = streamer.get_destination_readiness(cell_id)
        if bool(readiness.get("ready", false)):
            break
        await get_tree().process_frame
        await get_tree().physics_frame
    if not bool(readiness.get("ready", false)):
        streamer.finish_destination_preload(cell_id)
        return _failure("destination_preload_timeout", resolved)

    var destination_instance := streamer.get_destination_instance(cell_id)
    if destination_instance == null:
        streamer.finish_destination_preload(cell_id)
        return _failure("destination_instance_missing", resolved)

    var query := PhysicsRayQueryParameters3D.create(
        Vector3(target_position.x, 250.0, target_position.z),
        Vector3(target_position.x, -100.0, target_position.z)
    )
    query.exclude = [player.get_rid()]
    query.collide_with_areas = false
    var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
    if hit.is_empty():
        streamer.finish_destination_preload(cell_id)
        return _failure("authoritative_ground_missing", resolved)
    var collider: Variant = hit.get("collider")
    if not collider is Node or not _belongs_to(collider as Node, destination_instance):
        streamer.finish_destination_preload(cell_id)
        return _failure("ground_not_from_destination_cell", resolved)

    var original_position := player.global_position
    var ground_position: Vector3 = hit.get("position", Vector3.INF)
    if not ground_position.is_finite():
        streamer.finish_destination_preload(cell_id)
        return _failure("ground_position_invalid", resolved)
    player.global_position = ground_position + Vector3.UP * 1.05
    player.velocity = Vector3.ZERO
    var tangent: Vector2 = resolved["tangent"]
    if tangent.length_squared() > 0.5:
        player.look_at(player.global_position + Vector3(tangent.x, 0.0, tangent.y), Vector3.UP)

    player.set_meta("automatic_streetaxis_direct_id", streetaxis_id)
    player.set_meta("automatic_streetaxis_direct_source_id", str(resolved["source_id"]))
    player.set_meta("automatic_streetaxis_direct_cell_id", cell_id)
    player.set_meta("automatic_streetaxis_direct_network_path", str(resolved["network_path"]))
    player.set_meta("automatic_streetaxis_direct_street_fr", str(resolved["street_fr"]))
    player.set_meta("automatic_streetaxis_direct_street_nl", str(resolved["street_nl"]))
    player.set_meta("automatic_streetaxis_direct_ground_y", ground_position.y)
    player.set_meta("automatic_streetaxis_direct_collision_authorized", true)
    player.set_meta("automatic_streetaxis_direct_streaming_ready", true)

    streamer.finish_destination_preload(cell_id)
    await get_tree().physics_frame
    if not streamer.manager.is_collision_active(cell_id):
        player.global_position = original_position
        return _failure("collision_lost_after_handoff", resolved)

    last_result = {
        "ok": true,
        "streetaxis_id": streetaxis_id,
        "cell_id": cell_id,
        "street_fr": str(resolved["street_fr"]),
        "street_nl": str(resolved["street_nl"]),
        "ground_y": ground_position.y,
        "handoff_distance_m": handoff_distance,
        "streaming_ready": true,
        "collision_ready": true,
    }
    print("AUTOMATIC_STREETAXIS_DIRECT_SPAWN_READY: id=%d cell=%s street=%s / %s ground_y=%.3f" % [streetaxis_id, cell_id, str(resolved["street_fr"]), str(resolved["street_nl"]), ground_position.y])
    return last_result


func _apply_requested_destination(streetaxis_id: int) -> void:
    for _frame: int in range(600):
        var scene := get_tree().current_scene
        if scene != null:
            var player := scene.get_node_or_null("Player") as CharacterBody3D
            if player != null:
                await apply_streetaxis_to_player(player, streetaxis_id)
                return
        await get_tree().process_frame
    _failure("startup_player_timeout", {"streetaxis_id": streetaxis_id})
