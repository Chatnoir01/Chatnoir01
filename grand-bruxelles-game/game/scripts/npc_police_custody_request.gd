class_name NpcPoliceCustodyRequest
extends RefCounted

enum Action {
	NONE,
	CONTACT,
	DETAIN,
	REQUEST_ARREST_TRANSFER,
	RELEASE,
}

func build(
	response: NpcPoliceResponse,
	subject_id: int,
	subject_position: Vector3,
	legal_basis_confirmed: bool,
	arrest_authorized: bool,
	subject_compliant: bool,
	immediate_safety_risk: bool
) -> Dictionary:
	var result := {
		"action": Action.NONE,
		"subject_id": subject_id,
		"target_position": subject_position,
		"incident_id": -1,
		"additional_support_requested": false,
		"legal_basis_confirmed": legal_basis_confirmed,
		"arrest_authorized": arrest_authorized,
		"subject_compliant": subject_compliant,
	}
	if response == null or subject_id < 0:
		return result

	result["incident_id"] = response.current_incident_id
	if response.phase == NpcPoliceResponse.Phase.PATROL or response.phase == NpcPoliceResponse.Phase.RETURN_TO_PATROL:
		return result

	# This interface never invents legal authority. A higher-level gameplay/legal
	# system must explicitly confirm the basis and any arrest authorization.
	if not legal_basis_confirmed:
		result["action"] = Action.CONTACT
		return result

	result["additional_support_requested"] = immediate_safety_risk or not subject_compliant
	if arrest_authorized:
		result["action"] = Action.REQUEST_ARREST_TRANSFER
	else:
		result["action"] = Action.DETAIN
	return result

func build_release(subject_id: int, subject_position: Vector3, incident_id: int = -1) -> Dictionary:
	return {
		"action": Action.RELEASE,
		"subject_id": subject_id,
		"target_position": subject_position,
		"incident_id": incident_id,
		"additional_support_requested": false,
		"legal_basis_confirmed": false,
		"arrest_authorized": false,
		"subject_compliant": true,
	}
