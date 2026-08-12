class_name NpcBehaviorModel
extends RefCounted

enum Role {
	CIVILIAN,
	POLICE,
}

enum State {
	IDLE,
	WALKING,
	OBSERVING,
	AVOIDING,
	FLEEING,
	PATROLLING,
	INVESTIGATING,
	PURSUING,
	RETURNING,
}

const MIN_ALERT := 0.0
const MAX_ALERT := 100.0
const CIVILIAN_FLEE_THRESHOLD := 55.0
const POLICE_INVESTIGATE_THRESHOLD := 25.0
const POLICE_PURSUIT_THRESHOLD := 70.0

var role: Role = Role.CIVILIAN
var state: State = State.IDLE
var alert_level: float = 0.0
var home_position := Vector3.ZERO
var target_position := Vector3.ZERO
var preferred_speed: float = 1.35
var variation_seed: int = 0
var archetype: StringName = &"commuter"

func configure(new_role: Role, seed_value: int, spawn_position: Vector3) -> void:
	role = new_role
	variation_seed = seed_value
	home_position = spawn_position
	target_position = spawn_position
	alert_level = 0.0
	archetype = _pick_archetype(seed_value, new_role)
	preferred_speed = _pick_speed(seed_value, new_role)
	state = State.PATROLLING if new_role == Role.POLICE else State.IDLE

func apply_stimulus(intensity: float, stimulus_position: Vector3) -> State:
	alert_level = clampf(alert_level + maxf(intensity, 0.0), MIN_ALERT, MAX_ALERT)
	target_position = stimulus_position
	_update_state_from_alert()
	return state

func calm_down(amount: float) -> State:
	alert_level = clampf(alert_level - maxf(amount, 0.0), MIN_ALERT, MAX_ALERT)
	_update_state_from_alert()
	return state

func set_destination(destination: Vector3) -> void:
	target_position = destination
	if role == Role.POLICE:
		if state != State.PURSUING and state != State.INVESTIGATING:
			state = State.PATROLLING
	else:
		# A stale incident state must not block normal navigation once alertness
		# has actually returned to calm.
		if state != State.FLEEING or alert_level <= 5.0:
			state = State.WALKING

func should_despawn(observer_position: Vector3, max_distance: float) -> bool:
	if max_distance <= 0.0:
		return false
	return home_position.distance_squared_to(observer_position) > max_distance * max_distance

func _update_state_from_alert() -> void:
	if role == Role.POLICE:
		if alert_level >= POLICE_PURSUIT_THRESHOLD:
			state = State.PURSUING
		elif alert_level >= POLICE_INVESTIGATE_THRESHOLD:
			state = State.INVESTIGATING
		elif alert_level <= 5.0:
			state = State.PATROLLING
		elif state == State.PURSUING or state == State.INVESTIGATING:
			state = State.RETURNING
	else:
		if alert_level >= CIVILIAN_FLEE_THRESHOLD:
			state = State.FLEEING
		elif alert_level >= 20.0:
			state = State.AVOIDING
		elif alert_level <= 5.0:
			state = State.IDLE
		elif state == State.FLEEING or state == State.AVOIDING:
			state = State.OBSERVING

func _pick_archetype(seed_value: int, for_role: Role) -> StringName:
	if for_role == Role.POLICE:
		var police_types: Array[StringName] = [&"patrol", &"community", &"traffic"]
		return police_types[abs(seed_value) % police_types.size()]
	var civilian_types: Array[StringName] = [
		&"commuter",
		&"resident",
		&"student",
		&"shopper",
		&"worker",
		&"visitor",
	]
	return civilian_types[abs(seed_value) % civilian_types.size()]

func _pick_speed(seed_value: int, for_role: Role) -> float:
	var normalized := float(abs(seed_value * 37) % 1000) / 1000.0
	if for_role == Role.POLICE:
		return lerpf(1.25, 1.55, normalized)
	var base_speed: float = lerpf(1.0, 1.55, normalized)
	var pace_mix: int = absi(seed_value * 1103515245 + 11 * 12345)
	var pace_factor: float = lerpf(0.88, 1.12, float(pace_mix % 10000) / 10000.0)
	return clampf(base_speed * pace_factor, 0.75, 1.75)
