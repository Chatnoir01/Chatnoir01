class_name NpcPoliceResponse
extends RefCounted

enum Phase {
	PATROL,
	INVESTIGATE,
	PURSUIT,
	DEESCALATE,
	RETURN_TO_PATROL,
}

const INVESTIGATE_THRESHOLD := 0.25
const PURSUIT_THRESHOLD := 0.70
const PURSUIT_DOWNGRADE_HOLD_SECONDS := 1.5
const DEESCALATE_AFTER_SECONDS := 5.0
const RETURN_AFTER_SECONDS := 15.0
const VEHICLE_SUPPORT_DISTANCE_METERS := 50.0

var phase: Phase = Phase.PATROL
var patrol_anchor := Vector3.ZERO
var incident_position := Vector3.ZERO
var current_incident_id: int = -1
var threat_visible := false
var threat_level := 0.0
var calm_seconds := 0.0
var pursuit_downgrade_seconds := 0.0
var variation_seed := 0

func configure(seed_value: int, anchor: Vector3) -> void:
	variation_seed = seed_value
	patrol_anchor = anchor
	incident_position = anchor
	current_incident_id = -1
	threat_visible = false
	threat_level = 0.0
	calm_seconds = 0.0
	pursuit_downgrade_seconds = 0.0
	phase = Phase.PATROL

func report_incident(world_position: Vector3, severity: float, incident_id: int) -> Phase:
	incident_position = world_position
	current_incident_id = incident_id
	threat_level = clampf(severity, 0.0, 1.0)
	threat_visible = threat_level > 0.0
	calm_seconds = 0.0
	pursuit_downgrade_seconds = 0.0
	if threat_level >= PURSUIT_THRESHOLD:
		phase = Phase.PURSUIT
	elif threat_level >= INVESTIGATE_THRESHOLD:
		phase = Phase.INVESTIGATE
	else:
		phase = Phase.PATROL
	return phase

func update_threat(is_visible: bool, normalized_threat: float, delta_seconds: float) -> Phase:
	threat_visible = is_visible
	threat_level = clampf(normalized_threat, 0.0, 1.0)
	var elapsed := maxf(delta_seconds, 0.0)

	if threat_visible and threat_level >= PURSUIT_THRESHOLD:
		calm_seconds = 0.0
		pursuit_downgrade_seconds = 0.0
		phase = Phase.PURSUIT
		return phase
	if threat_visible and threat_level >= INVESTIGATE_THRESHOLD:
		calm_seconds = 0.0
		if phase == Phase.PURSUIT:
			pursuit_downgrade_seconds += elapsed
			if pursuit_downgrade_seconds < PURSUIT_DOWNGRADE_HOLD_SECONDS:
				return phase
		pursuit_downgrade_seconds = 0.0
		phase = Phase.INVESTIGATE
		return phase

	pursuit_downgrade_seconds = 0.0
	calm_seconds += elapsed
	if current_incident_id < 0:
		phase = Phase.PATROL
	elif calm_seconds >= RETURN_AFTER_SECONDS:
		phase = Phase.RETURN_TO_PATROL
	elif calm_seconds >= DEESCALATE_AFTER_SECONDS:
		phase = Phase.DEESCALATE
	return phase

func should_request_vehicle_support(distance_to_incident_meters: float) -> bool:
	return phase == Phase.PURSUIT and distance_to_incident_meters >= VEHICLE_SUPPORT_DISTANCE_METERS

func target_position() -> Vector3:
	if phase == Phase.RETURN_TO_PATROL or phase == Phase.PATROL:
		return patrol_anchor
	return incident_position

func arrive_at_patrol_anchor() -> void:
	if phase != Phase.RETURN_TO_PATROL:
		return
	phase = Phase.PATROL
	incident_position = patrol_anchor
	current_incident_id = -1
	threat_visible = false
	threat_level = 0.0
	calm_seconds = 0.0
	pursuit_downgrade_seconds = 0.0
