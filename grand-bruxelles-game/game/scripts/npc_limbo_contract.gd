extends RefCounted

## Narrow adapter between Grand Bruxelles' authoritative NPC simulation and
## an optional LimboAI state-machine pilot. The shipped behavior model remains
## the source of truth for role, alert thresholds, destinations and state.

var behavior: NpcBehaviorModel = null
var target_visible: bool = false
var target_distance_m: float = INF
var last_seen_position := Vector3.ZERO
var state_age_s: float = 0.0
var _last_branch: StringName = &"unbound"


func _init(existing_behavior: NpcBehaviorModel = null) -> void:
    bind_model(existing_behavior)


func bind_model(existing_behavior: NpcBehaviorModel) -> void:
    behavior = existing_behavior
    state_age_s = 0.0
    _last_branch = limbo_branch()


func sync_perception(visible: bool, distance_m: float, observed_position: Vector3, delta: float) -> void:
    var branch_before := limbo_branch()
    target_visible = visible
    target_distance_m = maxf(distance_m, 0.0)
    if visible:
        last_seen_position = observed_position
    var branch_after := limbo_branch()
    if branch_after != branch_before or branch_after != _last_branch:
        state_age_s = 0.0
    else:
        state_age_s += maxf(delta, 0.0)
    _last_branch = branch_after


func limbo_branch() -> StringName:
    if behavior == null:
        return &"unbound"
    match behavior.state:
        NpcBehaviorModel.State.IDLE, NpcBehaviorModel.State.WALKING, NpcBehaviorModel.State.PATROLLING:
            return &"routine"
        NpcBehaviorModel.State.OBSERVING:
            return &"observe"
        NpcBehaviorModel.State.AVOIDING:
            return &"avoid"
        NpcBehaviorModel.State.FLEEING:
            return &"flee"
        NpcBehaviorModel.State.INVESTIGATING:
            return &"investigate"
        NpcBehaviorModel.State.PURSUING:
            return &"pursue"
        NpcBehaviorModel.State.RETURNING:
            return &"return"
    return &"routine"


func should_request_backup() -> bool:
    return behavior != null \
        and behavior.role == NpcBehaviorModel.Role.POLICE \
        and behavior.state == NpcBehaviorModel.State.PURSUING \
        and behavior.alert_level >= NpcBehaviorModel.POLICE_PURSUIT_THRESHOLD


func action_request() -> Dictionary:
    if behavior == null:
        return {"action": &"none", "destination": Vector3.ZERO, "speed_scale": 0.0}
    var branch := limbo_branch()
    var speed_scale := 1.0
    if branch == &"flee" or branch == &"pursue":
        speed_scale = 1.35
    elif branch == &"observe":
        speed_scale = 0.0
    elif branch == &"avoid" or branch == &"investigate":
        speed_scale = 0.9
    return {
        "action": branch,
        "destination": behavior.target_position,
        "speed_scale": speed_scale,
        "request_backup": should_request_backup(),
    }


func blackboard_snapshot() -> Dictionary:
    if behavior == null:
        return {}
    return {
        "role": "police" if behavior.role == NpcBehaviorModel.Role.POLICE else "civilian",
        "state": NpcBehaviorModel.State.keys()[behavior.state].to_lower(),
        "branch": limbo_branch(),
        "alert_level": behavior.alert_level / NpcBehaviorModel.MAX_ALERT,
        "target_visible": target_visible,
        "target_distance_m": target_distance_m,
        "target_position": behavior.target_position,
        "last_seen_position": last_seen_position,
        "preferred_speed": behavior.preferred_speed,
        "archetype": behavior.archetype,
        "request_backup": should_request_backup(),
        "state_age_s": state_age_s,
    }
