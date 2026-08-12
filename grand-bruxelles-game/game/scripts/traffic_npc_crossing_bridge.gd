extends RefCounted

const SIGNAL_NONE := 0
const INTENT_WAIT_AT_CURB := 1
const INTENT_CROSS := 2

@export var assignment_radius_m: float = 8.0
@export var curb_arrival_radius_m: float = 1.15
@export var crossing_finish_radius_m: float = 1.10
@export var minimum_wait_seconds: float = 0.65
@export var traffic_clear_radius_m: float = 16.0
@export var traffic_stop_speed_kmh: float = 3.0

var _assignments: Dictionary = {}


func update_agents(
    agents: Array,
    crossing_system: RefCounted,
    traffic_root: Node,
    now_seconds: float
) -> Dictionary:
    if crossing_system == null:
        return get_stats()

    var live_ids := {}
    for raw_agent: Variant in agents:
        if not raw_agent is Node:
            continue
        var agent := raw_agent as Node
        if not is_instance_valid(agent) or agent.is_queued_for_deletion():
            continue
        var agent_id := int(agent.get_instance_id())
        live_ids[agent_id] = true
        if _assignments.has(agent_id):
            _advance_assignment(agent, crossing_system, traffic_root, now_seconds)
        else:
            _try_assign(agent, crossing_system, now_seconds)

    for raw_id: Variant in _assignments.keys():
        var agent_id := int(raw_id)
        if live_ids.has(agent_id):
            continue
        _clear_assignment_by_id(agent_id, crossing_system)

    return get_stats()


func clear_all(crossing_system: RefCounted) -> void:
    if crossing_system != null:
        for raw_id: Variant in _assignments.keys():
            _clear_assignment_by_id(int(raw_id), crossing_system)
    _assignments.clear()


func get_stats() -> Dictionary:
    var waiting := 0
    var crossing := 0
    for raw_assignment: Variant in _assignments.values():
        if typeof(raw_assignment) != TYPE_DICTIONARY:
            continue
        var assignment: Dictionary = raw_assignment
        if str(assignment.get("phase", "")) == "crossing":
            crossing += 1
        else:
            waiting += 1
    return {
        "assigned": _assignments.size(),
        "waiting": waiting,
        "crossing": crossing,
    }


func has_assignment(agent: Node) -> bool:
    return is_instance_valid(agent) and _assignments.has(int(agent.get_instance_id()))


func _try_assign(agent: Node, crossing_system: RefCounted, now_seconds: float) -> bool:
    if not _is_crossing_capable(agent):
        return false
    if not _is_agent_available(agent):
        return false

    var position := _agent_position(agent)
    var target_variant := _agent_target(agent)
    if not target_variant is Vector3:
        return false
    var original_target := target_variant as Vector3

    var candidates_variant: Variant = crossing_system.call(
        "get_crossings_near",
        position,
        assignment_radius_m,
        true
    )
    if not candidates_variant is Array:
        return false

    var best: Dictionary = {}
    var best_distance := INF
    for raw_crossing: Variant in candidates_variant:
        if typeof(raw_crossing) != TYPE_DICTIONARY:
            continue
        var crossing: Dictionary = raw_crossing
        if not _destination_crosses_road(position, original_target, crossing):
            continue
        var center: Vector3 = crossing.get("position", Vector3.ZERO)
        var distance := position.distance_to(center)
        if distance < best_distance:
            best_distance = distance
            best = crossing

    if best.is_empty():
        return false

    var center: Vector3 = best.get("position", Vector3.ZERO)
    var direction: Vector3 = best.get("crossing_direction", Vector3.ZERO)
    if direction.length_squared() <= 0.001:
        return false
    direction = direction.normalized()
    var side_sign := signf((position - center).dot(direction))
    if is_zero_approx(side_sign):
        side_sign = -1.0

    var start_point: Vector3 = best.get("start", center - direction * 3.0)
    var finish_point: Vector3 = best.get("finish", center + direction * 3.0)
    var curb_point := start_point if side_sign < 0.0 else finish_point
    var destination_point := finish_point if side_sign < 0.0 else start_point
    var crossing_id := int(best.get("id", 0))
    if crossing_id <= 0:
        return false

    var agent_id := int(agent.get_instance_id())
    _assignments[agent_id] = {
        "crossing_id": crossing_id,
        "phase": "approach",
        "curb": curb_point,
        "destination": destination_point,
        "original_target": original_target,
        "waiting_since_s": now_seconds,
    }
    agent.call("set_destination", curb_point)
    return true


func _advance_assignment(
    agent: Node,
    crossing_system: RefCounted,
    traffic_root: Node,
    now_seconds: float
) -> void:
    var agent_id := int(agent.get_instance_id())
    if not _assignments.has(agent_id):
        return
    var assignment: Dictionary = _assignments[agent_id]
    var crossing_id := int(assignment.get("crossing_id", 0))
    var phase := str(assignment.get("phase", "approach"))
    var position := _agent_position(agent)

    if not _is_agent_available(agent):
        _restore_and_clear(agent, crossing_system)
        return

    if phase == "approach":
        var curb: Vector3 = assignment.get("curb", position)
        agent.call("set_destination", curb)
        if position.distance_to(curb) > curb_arrival_radius_m:
            return
        crossing_system.call("register_waiting", crossing_id, agent_id)
        var intent := int(agent.call("update_crossing_context", SIGNAL_NONE, false, 0.0))
        if intent != INTENT_WAIT_AT_CURB:
            agent.call("update_crossing_context", SIGNAL_NONE, false, 0.0)
        assignment["phase"] = "waiting"
        assignment["waiting_since_s"] = now_seconds
        _assignments[agent_id] = assignment
        return

    if phase == "waiting":
        var waited := maxf(0.0, now_seconds - float(assignment.get("waiting_since_s", now_seconds)))
        var descriptor_variant: Variant = crossing_system.call("get_crossing", crossing_id)
        if typeof(descriptor_variant) != TYPE_DICTIONARY:
            _restore_and_clear(agent, crossing_system)
            return
        var descriptor: Dictionary = descriptor_variant
        var gap_safe := waited >= minimum_wait_seconds and _traffic_gap_safe(descriptor, traffic_root)
        var intent := int(agent.call("update_crossing_context", SIGNAL_NONE, gap_safe, waited))
        if intent != INTENT_CROSS or not gap_safe:
            crossing_system.call("register_waiting", crossing_id, agent_id)
            return
        crossing_system.call("begin_crossing", crossing_id, agent_id)
        if agent.has_method("clear_pedestrian_hold"):
            agent.call("clear_pedestrian_hold")
        agent.call("set_destination", assignment.get("destination", position))
        assignment["phase"] = "crossing"
        _assignments[agent_id] = assignment
        return

    if phase == "crossing":
        var destination: Vector3 = assignment.get("destination", position)
        agent.call("set_destination", destination)
        if position.distance_to(destination) > crossing_finish_radius_m:
            crossing_system.call("begin_crossing", crossing_id, agent_id)
            return
        crossing_system.call("clear_pedestrian", crossing_id, agent_id)
        if agent.has_method("clear_pedestrian_hold"):
            agent.call("clear_pedestrian_hold")
        agent.call("set_destination", assignment.get("original_target", destination))
        _assignments.erase(agent_id)


func _restore_and_clear(agent: Node, crossing_system: RefCounted) -> void:
    var agent_id := int(agent.get_instance_id())
    if not _assignments.has(agent_id):
        return
    var assignment: Dictionary = _assignments[agent_id]
    crossing_system.call("clear_pedestrian", int(assignment.get("crossing_id", 0)), agent_id)
    if agent.has_method("clear_pedestrian_hold"):
        agent.call("clear_pedestrian_hold")
    if agent.has_method("set_destination"):
        agent.call("set_destination", assignment.get("original_target", _agent_position(agent)))
    _assignments.erase(agent_id)


func _clear_assignment_by_id(agent_id: int, crossing_system: RefCounted) -> void:
    if not _assignments.has(agent_id):
        return
    var assignment: Dictionary = _assignments[agent_id]
    if crossing_system != null:
        crossing_system.call("clear_pedestrian", int(assignment.get("crossing_id", 0)), agent_id)
    _assignments.erase(agent_id)


func _destination_crosses_road(position: Vector3, target: Vector3, crossing: Dictionary) -> bool:
    var center: Vector3 = crossing.get("position", Vector3.ZERO)
    var direction: Vector3 = crossing.get("crossing_direction", Vector3.ZERO)
    if direction.length_squared() <= 0.001:
        return false
    direction = direction.normalized()
    var current_side := (position - center).dot(direction)
    var target_side := (target - center).dot(direction)
    if absf(current_side) < 0.25 or absf(target_side) < 0.25:
        return false
    if signf(current_side) == signf(target_side):
        return false
    return target.distance_to(center) >= 2.0


func _traffic_gap_safe(crossing: Dictionary, traffic_root: Node) -> bool:
    if traffic_root == null:
        return true
    var center: Vector3 = crossing.get("position", Vector3.ZERO)
    for child: Node in traffic_root.get_children():
        if not child is Node3D or child.is_queued_for_deletion():
            continue
        var vehicle := child as Node3D
        if vehicle.global_position.distance_to(center) > traffic_clear_radius_m:
            continue
        var speed_kmh := 0.0
        if vehicle.has_method("get_speed_kmh"):
            speed_kmh = float(vehicle.call("get_speed_kmh"))
        if speed_kmh > traffic_stop_speed_kmh:
            return false
    return true


func _is_crossing_capable(agent: Node) -> bool:
    return (
        agent.has_method("set_destination")
        and agent.has_method("update_crossing_context")
        and agent.has_method("clear_pedestrian_hold")
    )


func _is_agent_available(agent: Node) -> bool:
    var active_variant := agent.get("active")
    if typeof(active_variant) == TYPE_BOOL and not bool(active_variant):
        return false
    var transit_variant := agent.get("transit_state")
    if typeof(transit_variant) == TYPE_INT and int(transit_variant) != 0:
        return false
    return true


func _agent_position(agent: Node) -> Vector3:
    if agent.has_method("get_world_position"):
        var position_variant: Variant = agent.call("get_world_position")
        if position_variant is Vector3:
            return position_variant as Vector3
    if agent is Node3D:
        return (agent as Node3D).global_position
    return Vector3.ZERO


func _agent_target(agent: Node) -> Variant:
    var behavior_variant: Variant = agent.get("behavior")
    if behavior_variant is Object:
        return (behavior_variant as Object).get("target_position")
    return null
