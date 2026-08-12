extends RefCounted
class_name TrafficNpcCrossingBridge

var minimum_wait_seconds: float = 0.8
var assignment_radius_m: float = 34.0
var curb_reach_distance_m: float = 0.9
var exit_reach_distance_m: float = 1.1
var destination_side_margin_m: float = 0.6

var _assignments: Dictionary = {}

func has_assignment(agent: Node) -> bool:
    return is_instance_valid(agent) and _assignments.has(agent.get_instance_id())

func update_agents(agents: Array, crossing_system: RefCounted, traffic_gap_provider: Variant, now_seconds: float) -> void:
    if crossing_system == null:
        _clear_all(null)
        return

    var seen: Dictionary = {}
    for raw_agent: Variant in agents:
        if raw_agent == null or not raw_agent is Node:
            continue
        var agent := raw_agent as Node
        if not is_instance_valid(agent):
            continue
        var agent_id := agent.get_instance_id()
        seen[agent_id] = true
        if not _agent_is_eligible(agent):
            _clear_assignment(agent, crossing_system, true)
            continue
        if _assignments.has(agent_id):
            _advance_assignment(agent, crossing_system, traffic_gap_provider, now_seconds)
        else:
            _try_assign(agent, crossing_system)

    for raw_id: Variant in _assignments.keys():
        var agent_id := int(raw_id)
        if seen.has(agent_id):
            continue
        var assignment: Dictionary = _assignments[agent_id]
        crossing_system.call("clear_pedestrian", int(assignment.get("crossing_id", 0)), agent_id)
        _assignments.erase(agent_id)

func clear_agent(agent: Node, crossing_system: RefCounted) -> void:
    _clear_assignment(agent, crossing_system, true)

func _try_assign(agent: Node, crossing_system: RefCounted) -> void:
    if not crossing_system.has_method("get_crossings_near"):
        return
    var position := _agent_position(agent)
    var original_target := _agent_target(agent)
    var candidates: Array = crossing_system.call("get_crossings_near", position, assignment_radius_m, true)
    var best: Dictionary = {}
    var best_score := INF
    for raw_crossing: Variant in candidates:
        if typeof(raw_crossing) != TYPE_DICTIONARY:
            continue
        var crossing: Dictionary = raw_crossing
        var start: Vector3 = crossing.get("start", Vector3.ZERO)
        var finish: Vector3 = crossing.get("finish", Vector3.ZERO)
        if start == finish:
            continue
        var curb := start if position.distance_to(start) <= position.distance_to(finish) else finish
        var far_side := finish if curb == start else start
        var target_curb_distance := original_target.distance_to(curb)
        var target_far_distance := original_target.distance_to(far_side)
        if target_far_distance + destination_side_margin_m >= target_curb_distance:
            continue
        var score := position.distance_to(curb)
        if score < best_score:
            best_score = score
            best = {
                "crossing_id": int(crossing.get("osm_id", crossing.get("id", 0))),
                "original_target": original_target,
                "curb": curb,
                "far_side": far_side,
                "phase": &"approach",
                "wait_started_s": -1.0,
                "last_gap_check_s": -1.0,
                "gap_check_attempt": 0,
            }
    if best.is_empty() or int(best.get("crossing_id", 0)) <= 0:
        return
    _assignments[agent.get_instance_id()] = best
    agent.call("set_destination", best["curb"])

func _advance_assignment(agent: Node, crossing_system: RefCounted, traffic_gap_provider: Variant, now_seconds: float) -> void:
    var agent_id := agent.get_instance_id()
    var assignment: Dictionary = _assignments[agent_id]
    var crossing_id := int(assignment.get("crossing_id", 0))
    var phase := StringName(assignment.get("phase", &"approach"))
    var position := _agent_position(agent)
    var curb: Vector3 = assignment.get("curb", position)
    var far_side: Vector3 = assignment.get("far_side", position)

    if phase == &"approach":
        if position.distance_to(curb) > curb_reach_distance_m:
            agent.call("set_destination", curb)
            return
        crossing_system.call("register_waiting", crossing_id, agent_id)
        assignment["phase"] = &"waiting"
        assignment["wait_started_s"] = now_seconds
        assignment["last_gap_check_s"] = now_seconds
        assignment["gap_check_attempt"] = 0
        _assignments[agent_id] = assignment
        if agent.has_method("update_crossing_context"):
            agent.call("update_crossing_context", 0, false, 0.0)
        return

    if phase == &"waiting":
        var wait_started_s := float(assignment.get("wait_started_s", now_seconds))
        var waited := maxf(0.0, now_seconds - wait_started_s)
        var last_gap_check_s := float(assignment.get("last_gap_check_s", wait_started_s))
        var attempt := int(assignment.get("gap_check_attempt", 0))
        var recheck_interval := _agent_gap_recheck_interval(agent, attempt)
        var recheck_due := waited >= minimum_wait_seconds and now_seconds - last_gap_check_s >= recheck_interval
        var gap_safe := false
        if recheck_due:
            gap_safe = _gap_is_safe(traffic_gap_provider, crossing_id, position)
            assignment["last_gap_check_s"] = now_seconds
            assignment["gap_check_attempt"] = attempt + 1
            _assignments[agent_id] = assignment
        if agent.has_method("update_crossing_context"):
            agent.call("update_crossing_context", 0, gap_safe, waited)
        if not gap_safe:
            return
        crossing_system.call("begin_crossing", crossing_id, agent_id)
        if agent.has_method("clear_pedestrian_hold"):
            agent.call("clear_pedestrian_hold")
        agent.call("set_destination", far_side)
        assignment["phase"] = &"crossing"
        _assignments[agent_id] = assignment
        return

    if phase == &"crossing":
        if position.distance_to(far_side) > exit_reach_distance_m:
            agent.call("set_destination", far_side)
            return
        crossing_system.call("clear_pedestrian", crossing_id, agent_id)
        if agent.has_method("clear_pedestrian_hold"):
            agent.call("clear_pedestrian_hold")
        agent.call("set_destination", assignment.get("original_target", position))
        _assignments.erase(agent_id)

func _agent_gap_recheck_interval(agent: Node, attempt_index: int) -> float:
    var pedestrian_context: Variant = agent.get("pedestrian_context")
    if pedestrian_context != null and pedestrian_context.has_method("curb_recheck_interval_seconds"):
        return maxf(0.05, float(pedestrian_context.call("curb_recheck_interval_seconds", attempt_index)))
    return minimum_wait_seconds

func _gap_is_safe(provider: Variant, crossing_id: int, position: Vector3) -> bool:
    if provider == null:
        return true
    if provider.has_method("is_crossing_gap_safe"):
        return bool(provider.call("is_crossing_gap_safe", crossing_id, position))
    if provider.has_method("crossing_gap_safe"):
        return bool(provider.call("crossing_gap_safe", crossing_id, position))
    return false

func _agent_is_eligible(agent: Node) -> bool:
    if not agent.has_method("set_destination") or not agent.has_method("get_world_position"):
        return false
    var active_value: Variant = agent.get("active")
    if active_value != null and not bool(active_value):
        return false
    var transit_value: Variant = agent.get("transit_state")
    if transit_value != null and int(transit_value) != 0:
        return false
    return true

func _agent_position(agent: Node) -> Vector3:
    var value: Variant = agent.call("get_world_position")
    return value as Vector3 if value is Vector3 else Vector3.ZERO

func _agent_target(agent: Node) -> Vector3:
    var behavior: Variant = agent.get("behavior")
    if behavior != null:
        var value: Variant = behavior.get("target_position")
        if value is Vector3:
            return value as Vector3
    return _agent_position(agent)

func _clear_assignment(agent: Node, crossing_system: RefCounted, restore_target: bool) -> void:
    if not is_instance_valid(agent):
        return
    var agent_id := agent.get_instance_id()
    if not _assignments.has(agent_id):
        return
    var assignment: Dictionary = _assignments[agent_id]
    if crossing_system != null:
        crossing_system.call("clear_pedestrian", int(assignment.get("crossing_id", 0)), agent_id)
    if agent.has_method("clear_pedestrian_hold"):
        agent.call("clear_pedestrian_hold")
    if restore_target and agent.has_method("set_destination"):
        agent.call("set_destination", assignment.get("original_target", _agent_position(agent)))
    _assignments.erase(agent_id)

func _clear_all(crossing_system: RefCounted) -> void:
    if crossing_system != null:
        for raw_id: Variant in _assignments.keys():
            var assignment: Dictionary = _assignments[raw_id]
            crossing_system.call("clear_pedestrian", int(assignment.get("crossing_id", 0)), int(raw_id))
    _assignments.clear()
