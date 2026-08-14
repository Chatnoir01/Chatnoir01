extends RefCounted
class_name GrandBruxellesNpcAiContract

## Engine-agnostic behavior contract for a future LimboAI brain.
## Keeps Brussels gameplay state in our code while LimboAI owns decision flow.

enum Role { CIVILIAN, POLICE }
enum State { IDLE, PATROL, OBSERVE, APPROACH, CHASE, SEARCH, FLEE, RETURN }

var role: Role = Role.CIVILIAN
var state: State = State.IDLE
var suspicion: float = 0.0
var alert_level: float = 0.0
var target_visible: bool = false
var target_distance_m: float = INF
var target_position: Vector3 = Vector3.ZERO
var last_seen_position: Vector3 = Vector3.ZERO
var route_id: StringName = &""
var request_backup: bool = false
var state_age_s: float = 0.0

func _init(agent_role: Role = Role.CIVILIAN) -> void:
    role = agent_role
    state = State.PATROL

func tick(delta: float, visible: bool, distance_m: float, threat: float, target_pos: Vector3) -> State:
    state_age_s += maxf(delta, 0.0)
    target_visible = visible
    target_distance_m = maxf(distance_m, 0.0)
    target_position = target_pos
    alert_level = clampf(threat, 0.0, 1.0)

    if visible:
        last_seen_position = target_pos
        suspicion = clampf(suspicion + delta * (0.55 + alert_level), 0.0, 1.0)
    else:
        suspicion = clampf(suspicion - delta * 0.16, 0.0, 1.0)

    var next := _choose_state()
    if next != state:
        state = next
        state_age_s = 0.0

    request_backup = role == Role.POLICE and state == State.CHASE and (alert_level >= 0.75 or suspicion >= 0.90)
    return state

func _choose_state() -> State:
    if role == Role.CIVILIAN:
        if alert_level >= 0.55 and target_distance_m <= 18.0:
            return State.FLEE
        if target_visible and target_distance_m <= 10.0:
            return State.OBSERVE
        if suspicion > 0.20:
            return State.OBSERVE
        return State.PATROL

    # Police policy. LimboAI will later express this as BT/HSM branches.
    if target_visible and alert_level >= 0.65 and target_distance_m <= 42.0:
        return State.CHASE
    if not target_visible and state == State.CHASE and suspicion > 0.15:
        return State.SEARCH
    if target_visible and (suspicion >= 0.45 or alert_level >= 0.30):
        return State.APPROACH
    if not target_visible and suspicion > 0.15:
        return State.SEARCH
    if target_visible:
        return State.OBSERVE
    return State.PATROL

func blackboard_snapshot() -> Dictionary:
    return {
        "role": "police" if role == Role.POLICE else "civilian",
        "state": State.keys()[state].to_lower(),
        "target_visible": target_visible,
        "target_distance_m": target_distance_m,
        "target_position": target_position,
        "last_seen_position": last_seen_position,
        "suspicion": suspicion,
        "alert_level": alert_level,
        "route_id": route_id,
        "request_backup": request_backup,
    }
