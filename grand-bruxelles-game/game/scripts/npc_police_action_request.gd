class_name NpcPoliceActionRequest
extends RefCounted

enum Action {
    NONE,
    INVESTIGATE,
    FOOT_PURSUIT,
    REQUEST_VEHICLE_SUPPORT,
    RETURN_TO_PATROL,
    TACTICAL_REPOSITION,
    RANGED_ATTACK,
    MELEE_ATTACK,
}

const MELEE_ATTACK_DISTANCE_M := 2.25
const TACTICAL_REPOSITION_DISTANCE_M := 5.0
const RANGED_ATTACK_DISTANCE_M := 18.0

func build(response: NpcPoliceResponse, agent_position: Vector3, combat_ready: bool = false) -> Dictionary:
    if response == null:
        return {
            "action": Action.NONE,
            "action_name": action_name(Action.NONE),
            "target_position": agent_position,
            "incident_id": -1,
            "vehicle_support_requested": false,
        }

    var target: Vector3 = response.target_position()
    var distance_m: float = agent_position.distance_to(target)
    var action: int = Action.NONE
    var request_vehicle := false

    match response.phase:
        NpcPoliceResponse.Phase.INVESTIGATE:
            action = Action.INVESTIGATE
        NpcPoliceResponse.Phase.PURSUIT:
            request_vehicle = response.should_request_vehicle_support(distance_m)
            if request_vehicle:
                action = Action.REQUEST_VEHICLE_SUPPORT
            elif combat_ready and distance_m <= MELEE_ATTACK_DISTANCE_M:
                action = Action.MELEE_ATTACK
            elif combat_ready and distance_m <= TACTICAL_REPOSITION_DISTANCE_M:
                action = Action.TACTICAL_REPOSITION
            elif combat_ready and distance_m <= RANGED_ATTACK_DISTANCE_M:
                action = Action.RANGED_ATTACK
            else:
                action = Action.FOOT_PURSUIT
        NpcPoliceResponse.Phase.DEESCALATE:
            action = Action.INVESTIGATE
        NpcPoliceResponse.Phase.RETURN_TO_PATROL:
            action = Action.RETURN_TO_PATROL
        _:
            action = Action.NONE

    return {
        "action": action,
        "action_name": action_name(action),
        "phase": response.phase,
        "target_position": target,
        "distance_m": distance_m,
        "incident_id": response.current_incident_id,
        "threat_level": response.threat_level,
        "vehicle_support_requested": request_vehicle,
        "combat_ready": combat_ready,
    }

static func action_name(action: int) -> StringName:
    match action:
        Action.INVESTIGATE:
            return &"investigate"
        Action.FOOT_PURSUIT:
            return &"foot_pursuit"
        Action.REQUEST_VEHICLE_SUPPORT:
            return &"request_vehicle_support"
        Action.RETURN_TO_PATROL:
            return &"return_to_patrol"
        Action.TACTICAL_REPOSITION:
            return &"tactical_reposition"
        Action.RANGED_ATTACK:
            return &"ranged_attack"
        Action.MELEE_ATTACK:
            return &"melee_attack"
        _:
            return &"none"
