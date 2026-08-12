class_name NpcPoliceActionRequest
extends RefCounted

enum Action {
	NONE,
	INVESTIGATE,
	FOOT_PURSUIT,
	REQUEST_VEHICLE_SUPPORT,
	RETURN_TO_PATROL,
}

func build(response: NpcPoliceResponse, agent_position: Vector3) -> Dictionary:
	if response == null:
		return {
			"action": Action.NONE,
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
			action = Action.REQUEST_VEHICLE_SUPPORT if request_vehicle else Action.FOOT_PURSUIT
		NpcPoliceResponse.Phase.DEESCALATE:
			action = Action.INVESTIGATE
		NpcPoliceResponse.Phase.RETURN_TO_PATROL:
			action = Action.RETURN_TO_PATROL
		_:
			action = Action.NONE

	return {
		"action": action,
		"phase": response.phase,
		"target_position": target,
		"distance_m": distance_m,
		"incident_id": response.current_incident_id,
		"threat_level": response.threat_level,
		"vehicle_support_requested": request_vehicle,
	}
