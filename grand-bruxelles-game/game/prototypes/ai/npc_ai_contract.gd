extends RefCounted
class_name GrandBruxellesNpcAiContract

## Adapter seam between the existing Grand Bruxelles NPC simulation and LimboAI.
## NpcBehaviorModel remains the source of truth; LimboAI may orchestrate branches,
## but it does not duplicate alert thresholds, roles, destinations or runtime state.

var behavior: NpcBehaviorModel = null
var target_visible: bool = false
var target_distance_m: float = INF
var last_seen_position: Vector3 = Vector3.ZERO
var state_age_s: float = 0.0

func _init(existing_behavior: NpcBehaviorModel = null) -> void:
    behavior = existing_behavior

func bind_model(existing_behavior: NpcBehaviorModel) -> void:
    behavior = existing_behavior
    state_age_s = 0.0

func sync_perception(visible: bool, distance_m: float, observed_position: Vector3, delta: float) -> void:
    state_age_s += maxf(delta, 0.0)
    target_visible = visible
    target_distance_m = maxf(distance_m, 0.0)
    if visible:
        last_seen_position = observed_position

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
