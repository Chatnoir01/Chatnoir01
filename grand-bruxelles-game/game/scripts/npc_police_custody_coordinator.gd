class_name NpcPoliceCustodyCoordinator
extends RefCounted

enum State {
	CLEAR,
	CONTACT,
	DETAINED,
	TRANSFER_PENDING,
	RELEASED,
}

const CONTACT_TIMEOUT_SECONDS := 12.0
const CALM_REASSESSMENT_SECONDS := 8.0

var state: State = State.CLEAR
var subject_id: int = -1
var incident_id: int = -1
var elapsed_seconds := 0.0
var calm_seconds := 0.0
var reassessment_due := false

func reset() -> void:
	state = State.CLEAR
	subject_id = -1
	incident_id = -1
	elapsed_seconds = 0.0
	calm_seconds = 0.0
	reassessment_due = false

func apply_request(request: Dictionary) -> State:
	var action := int(request.get("action", NpcPoliceCustodyRequest.Action.NONE))
	subject_id = int(request.get("subject_id", -1))
	incident_id = int(request.get("incident_id", -1))
	elapsed_seconds = 0.0
	calm_seconds = 0.0
	reassessment_due = false
	match action:
		NpcPoliceCustodyRequest.Action.CONTACT:
			state = State.CONTACT
		NpcPoliceCustodyRequest.Action.DETAIN:
			state = State.DETAINED
		NpcPoliceCustodyRequest.Action.REQUEST_ARREST_TRANSFER:
			state = State.TRANSFER_PENDING
		NpcPoliceCustodyRequest.Action.RELEASE:
			state = State.RELEASED
		_:
			state = State.CLEAR
	return state

func advance(delta_seconds: float, legal_basis_still_confirmed: bool, subject_compliant: bool, immediate_safety_risk: bool) -> State:
	var delta := maxf(0.0, delta_seconds)
	elapsed_seconds += delta

	if state == State.CLEAR or state == State.RELEASED:
		return state

	if (state == State.DETAINED or state == State.TRANSFER_PENDING) and not legal_basis_still_confirmed:
		state = State.RELEASED
		reassessment_due = false
		return state

	if state == State.CONTACT:
		if legal_basis_still_confirmed:
			return state
		if elapsed_seconds >= CONTACT_TIMEOUT_SECONDS:
			state = State.RELEASED
		return state

	if subject_compliant and not immediate_safety_risk:
		calm_seconds += delta
		if calm_seconds >= CALM_REASSESSMENT_SECONDS:
			reassessment_due = true
	else:
		calm_seconds = 0.0
		reassessment_due = false
	return state

func acknowledge_reassessment() -> void:
	calm_seconds = 0.0
	reassessment_due = false

func confirm_transfer_complete() -> bool:
	if state != State.TRANSFER_PENDING:
		return false
	reset()
	return true

func is_movement_restricted() -> bool:
	return state == State.DETAINED or state == State.TRANSFER_PENDING

func as_dictionary() -> Dictionary:
	return {
		"state": state,
		"subject_id": subject_id,
		"incident_id": incident_id,
		"elapsed_seconds": elapsed_seconds,
		"calm_seconds": calm_seconds,
		"reassessment_due": reassessment_due,
		"movement_restricted": is_movement_restricted(),
	}
