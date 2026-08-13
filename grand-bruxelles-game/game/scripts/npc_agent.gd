class_name NpcAgent
extends CharacterBody3D

enum TransitState {
	NONE,
	WAITING,
	BOARDING,
	ONBOARD,
	DISEMBARKING,
}

@export var role: NpcBehaviorModel.Role = NpcBehaviorModel.Role.CIVILIAN
@export var variation_seed: int = 1
@export var acceleration: float = 7.5
@export var turn_speed: float = 7.0
@export var arrival_radius: float = 0.6
@export var calm_rate: float = 7.5
@export var despawn_distance: float = 180.0

var behavior := NpcBehaviorModel.new()
var pedestrian_context := NpcPedestrianContext.new()
var appearance := NpcAppearanceProfile.new()
var ambient_state := NpcAmbientState.new()
var police_response := NpcPoliceResponse.new()
var crowd_reaction := NpcCrowdReaction.new()
var civilian_recovery := NpcCivilianRecovery.new()
var pedestrian_intent: int = NpcPedestrianContext.PedestrianIntent.CONTINUE
var weather_context: int = NpcAppearanceProfile.WeatherContext.MILD
var transit_state: int = TransitState.NONE
var observer_position := Vector3.ZERO
var active := true
var movement_held := false
var transit_queue: NpcTransitQueue = null
var transit_queue_passenger_id: int = -1
var transit_stop: NpcTransitStop = null
var civilian_routine_target := Vector3.ZERO
var civilian_recovery_movement_scale: float = 1.0
var _transit_queue_applied_target := Vector3.ZERO
var _transit_queue_pending_target := Vector3.ZERO
var _transit_queue_has_applied_target: bool = false
var _transit_queue_has_pending_target: bool = false
var _transit_queue_compaction_remaining_s: float = 0.0

func _ready() -> void:
	behavior.configure(role, variation_seed, global_position)
	_configure_pedestrian_context()
	_configure_appearance()
	_configure_ambient_state()
	_configure_response_models(global_position)

func set_spawn_context(new_role: NpcBehaviorModel.Role, seed_value: int, spawn_position: Vector3) -> void:
	_leave_transit_queue_if_needed()
	role = new_role
	variation_seed = seed_value
	_set_world_position(spawn_position)
	behavior.configure(new_role, seed_value, spawn_position)
	_configure_pedestrian_context()
	_configure_appearance()
	_configure_ambient_state()
	_configure_response_models(spawn_position)
	_reset_transit_state()

func set_weather_context(new_weather_context: int) -> void:
	weather_context = clampi(new_weather_context, NpcAppearanceProfile.WeatherContext.MILD, NpcAppearanceProfile.WeatherContext.COLD)
	_configure_appearance()

func get_appearance_profile() -> Dictionary:
	return appearance.as_dictionary().duplicate(true)

func get_ambient_animation_tag() -> StringName:
	return ambient_state.animation_tag()

func advance_ambient_state(crowd_is_dense: bool, sequence_index: int = -1) -> int:
	var is_raining: bool = weather_context == NpcAppearanceProfile.WeatherContext.RAIN
	return ambient_state.advance(is_raining, crowd_is_dense, sequence_index)

func join_transit_queue(queue: NpcTransitQueue, passenger_id: int) -> int:
	if queue == null or passenger_id < 0:
		return -1
	if transit_queue != null and (transit_queue != queue or transit_queue_passenger_id != passenger_id):
		_leave_transit_queue_if_needed()
	var slot: int = queue.join_queue(passenger_id)
	if slot < 0:
		return -1
	transit_queue = queue
	transit_queue_passenger_id = passenger_id
	return slot

func join_transit_stop(stop: NpcTransitStop, passenger_id: int, preferred_door: int = -1) -> int:
	if stop == null or passenger_id < 0:
		return -1
	_leave_transit_queue_if_needed()
	var door_index: int = stop.join_waiting_passenger(passenger_id, preferred_door)
	if door_index < 0:
		return -1
	var queue: NpcTransitQueue = stop.queue_for_door(door_index)
	var slot: int = join_transit_queue(queue, passenger_id)
	if slot < 0:
		stop.leave_waiting_passenger(passenger_id)
		return -1
	transit_stop = stop
	transit_state = TransitState.WAITING
	ambient_state.set_transit_context(true, false)
	pedestrian_intent = NpcPedestrianContext.PedestrianIntent.WAIT_FOR_TRANSIT
	refresh_transit_stop_target()
	return door_index

func transit_queue_compaction_delay_seconds() -> float:
	var passenger_component := maxi(transit_queue_passenger_id, 0)
	var bucket := posmod(variation_seed * 7 + passenger_component * 3, 5)
	return 0.18 + float(bucket) * 0.09

func refresh_transit_stop_target(delta_seconds: float = 0.0) -> Vector3:
	if transit_stop == null or transit_queue_passenger_id < 0:
		_reset_transit_queue_target_tracking()
		return get_world_position()
	var desired_target: Vector3 = transit_stop.queue_target_for(transit_queue_passenger_id)
	if not _transit_queue_has_applied_target:
		_apply_transit_queue_target(desired_target)
		return desired_target

	if desired_target.is_equal_approx(_transit_queue_applied_target):
		_transit_queue_has_pending_target = false
		_transit_queue_compaction_remaining_s = 0.0
		_apply_transit_queue_target(_transit_queue_applied_target)
		return _transit_queue_applied_target

	if not _transit_queue_has_pending_target:
		_transit_queue_pending_target = desired_target
		_transit_queue_has_pending_target = true
		_transit_queue_compaction_remaining_s = transit_queue_compaction_delay_seconds()
	elif not desired_target.is_equal_approx(_transit_queue_pending_target):
		_transit_queue_pending_target = desired_target

	_transit_queue_compaction_remaining_s = maxf(0.0, _transit_queue_compaction_remaining_s - maxf(0.0, delta_seconds))
	if _transit_queue_compaction_remaining_s <= 0.0:
		var target_to_apply := _transit_queue_pending_target
		_transit_queue_has_pending_target = false
		_apply_transit_queue_target(target_to_apply)
		return target_to_apply

	_apply_transit_queue_target(_transit_queue_applied_target)
	return _transit_queue_applied_target

func request_transit_stop_boarding() -> Dictionary:
	if transit_stop == null or transit_queue_passenger_id < 0:
		return {"allowed": false, "door_index": -1, "reason": "not_waiting"}
	var passenger_id: int = transit_queue_passenger_id
	var result: Dictionary = transit_stop.request_boarding(passenger_id)
	if bool(result.get("allowed", false)):
		transit_queue = null
		transit_queue_passenger_id = -1
		transit_stop = null
		_reset_transit_queue_target_tracking()
		transit_state = TransitState.BOARDING
		ambient_state.set_transit_context(true, true)
		pedestrian_intent = NpcPedestrianContext.PedestrianIntent.BOARD_TRANSIT
		movement_held = false
		var door_position_value: Variant = result.get("door_position", get_world_position())
		if door_position_value is Vector3:
			behavior.set_destination(door_position_value as Vector3)
	else:
		transit_state = TransitState.WAITING
		ambient_state.set_transit_context(true, false)
		refresh_transit_stop_target()
	return result

func leave_transit_queue() -> bool:
	if transit_queue == null or transit_queue_passenger_id < 0:
		return false
	var passenger_id: int = transit_queue_passenger_id
	var removed: bool = transit_queue.leave_queue(passenger_id)
	if transit_stop != null:
		removed = transit_stop.leave_waiting_passenger(passenger_id) or removed
	transit_queue = null
	transit_queue_passenger_id = -1
	transit_stop = null
	_reset_transit_queue_target_tracking()
	return removed

func get_transit_queue_target() -> Vector3:
	if transit_queue == null or transit_queue_passenger_id < 0:
		return get_world_position()
	return transit_queue.position_for(transit_queue_passenger_id)

func can_board_from_queue(vehicle_capacity_remaining: int) -> bool:
	if transit_queue == null or transit_queue_passenger_id < 0:
		return false
	return transit_queue.can_board(transit_queue_passenger_id, vehicle_capacity_remaining)

func get_world_position() -> Vector3:
	if is_inside_tree():
		return global_position
	return position

func set_destination(destination: Vector3) -> void:
	if role == NpcBehaviorModel.Role.CIVILIAN:
		civilian_routine_target = destination
	behavior.set_destination(destination)

func react_to_event(intensity: float, world_position: Vector3) -> void:
	behavior.apply_stimulus(intensity, world_position)

func apply_local_crowd_stimulus(stimulus_position: Vector3, normalized_intensity: float, sheltered_or_occluded: bool = false) -> Dictionary:
	var result: Dictionary = crowd_reaction.reaction_for(
		get_world_position(),
		stimulus_position,
		normalized_intensity,
		sheltered_or_occluded
	)
	if role != NpcBehaviorModel.Role.CIVILIAN:
		return result
	var action: StringName = StringName(result.get("action", &"observe"))
	var response_intensity: float = float(result.get("intensity", 0.0))
	if action == &"flee":
		behavior.apply_stimulus(maxf(60.0, response_intensity * 100.0), stimulus_position)
	elif action == &"avoid":
		behavior.apply_stimulus(maxf(22.0, response_intensity * 100.0), stimulus_position)
	elif response_intensity > 0.05:
		behavior.apply_stimulus(minf(15.0, response_intensity * 20.0), stimulus_position)
	return result

func begin_civilian_recovery(normalized_severity: float, started_at_seconds: float, context: String = "street") -> Dictionary:
	if role != NpcBehaviorModel.Role.CIVILIAN:
		return {"settle_seconds": 0.0, "recovery_seconds": 0.0, "severity": 0.0}
	civilian_recovery_movement_scale = 0.42
	return civilian_recovery.begin_recovery(normalized_severity, started_at_seconds, context, _capture_civilian_routine_snapshot())

func update_civilian_recovery(now_seconds: float, threat_active: bool) -> Dictionary:
	if role != NpcBehaviorModel.Role.CIVILIAN:
		return {"alertness": 0.0, "movement_scale": 1.0, "resume_routine": false, "progress": 0.0}
	var result: Dictionary = civilian_recovery.sample(now_seconds, threat_active)
	civilian_recovery_movement_scale = clampf(float(result.get("movement_scale", 1.0)), 0.0, 1.0)
	if threat_active:
		behavior.alert_level = maxf(behavior.alert_level, float(result.get("alertness", 0.0)) * 100.0)
	elif bool(result.get("resume_routine", false)):
		behavior.alert_level = 0.0
		var routine_snapshot_value: Variant = result.get("routine_snapshot", null)
		if routine_snapshot_value is Dictionary:
			_restore_civilian_routine_snapshot(routine_snapshot_value as Dictionary)
		else:
			behavior.set_destination(civilian_routine_target)
		civilian_recovery_movement_scale = 1.0
	else:
		behavior.alert_level = clampf(float(result.get("alertness", 0.0)) * 100.0, 0.0, 100.0)
		if behavior.state == NpcBehaviorModel.State.FLEEING or behavior.state == NpcBehaviorModel.State.AVOIDING:
			behavior.state = NpcBehaviorModel.State.OBSERVING
	return result

func report_police_incident(world_position: Vector3, severity: float, incident_id: int) -> int:
	if role != NpcBehaviorModel.Role.POLICE:
		return NpcPoliceResponse.Phase.PATROL
	var phase: int = police_response.report_incident(world_position, severity, incident_id)
	_sync_police_response_to_behavior()
	return phase

func update_police_threat(is_visible: bool, normalized_threat: float, delta_seconds: float) -> int:
	if role != NpcBehaviorModel.Role.POLICE:
		return NpcPoliceResponse.Phase.PATROL
	var phase: int = police_response.update_threat(is_visible, normalized_threat, delta_seconds)
	_sync_police_response_to_behavior()
	return phase

func police_requires_vehicle_support(distance_to_incident_meters: float) -> bool:
	return role == NpcBehaviorModel.Role.POLICE and police_response.should_request_vehicle_support(distance_to_incident_meters)

func mark_police_patrol_anchor_reached() -> void:
	if role != NpcBehaviorModel.Role.POLICE:
		return
	police_response.arrive_at_patrol_anchor()
	_sync_police_response_to_behavior()

func set_observer_position(world_position: Vector3) -> void:
	observer_position = world_position

func update_crossing_context(signal_value: int, traffic_gap_safe: bool, waiting_seconds: float) -> int:
	pedestrian_intent = pedestrian_context.crossing_intent(signal_value, traffic_gap_safe, waiting_seconds)
	movement_held = pedestrian_intent == NpcPedestrianContext.PedestrianIntent.WAIT_AT_CURB
	return pedestrian_intent

func update_transit_context(vehicle_arrived: bool, has_capacity: bool, waiting_seconds: float) -> int:
	if transit_state == TransitState.ONBOARD or transit_state == TransitState.DISEMBARKING:
		return pedestrian_intent
	pedestrian_intent = pedestrian_context.transit_intent(vehicle_arrived, has_capacity, waiting_seconds)
	if pedestrian_intent == NpcPedestrianContext.PedestrianIntent.WAIT_FOR_TRANSIT:
		transit_state = TransitState.WAITING
		ambient_state.set_transit_context(true, false)
	elif pedestrian_intent == NpcPedestrianContext.PedestrianIntent.BOARD_TRANSIT:
		transit_state = TransitState.BOARDING
		ambient_state.set_transit_context(true, true)
	else:
		transit_state = TransitState.NONE
		ambient_state.set_transit_context(false, false)
	movement_held = transit_state == TransitState.WAITING or transit_state == TransitState.BOARDING
	return pedestrian_intent

func confirm_boarded() -> bool:
	if transit_state != TransitState.BOARDING:
		return false
	_leave_transit_queue_if_needed()
	transit_state = TransitState.ONBOARD
	movement_held = true
	velocity = Vector3.ZERO
	return true

func begin_disembark_from_stop(stop: NpcTransitStop, door_index: int, exit_sequence_index: int) -> bool:
	if stop == null or transit_state != TransitState.ONBOARD:
		return false
	if door_index < 0 or door_index >= stop.door_count():
		return false
	var started: bool = begin_disembark(stop.disembark_position_for(door_index, exit_sequence_index))
	if started and stop.pending_alighting_for_door(door_index) > 0:
		stop.register_disembarked(door_index)
	return started

func begin_disembark(exit_position: Vector3) -> bool:
	if transit_state != TransitState.ONBOARD:
		return false
	transit_state = TransitState.DISEMBARKING
	_set_world_position(exit_position)
	velocity = Vector3.ZERO
	movement_held = true
	return true

func complete_disembark() -> bool:
	if transit_state != TransitState.DISEMBARKING:
		return false
	_reset_transit_state()
	return true

func clear_pedestrian_hold() -> void:
	pedestrian_intent = NpcPedestrianContext.PedestrianIntent.CONTINUE
	movement_held = false
	if transit_state == TransitState.WAITING or transit_state == TransitState.BOARDING:
		transit_state = TransitState.NONE
		ambient_state.set_transit_context(false, false)

func _physics_process(delta: float) -> void:
	if not active:
		velocity = Vector3.ZERO
		return

	if role != NpcBehaviorModel.Role.POLICE or police_response.phase == NpcPoliceResponse.Phase.PATROL:
		if role != NpcBehaviorModel.Role.CIVILIAN or not civilian_recovery.is_active():
			behavior.calm_down(calm_rate * delta)
	if behavior.should_despawn(observer_position, despawn_distance):
		_leave_transit_queue_if_needed()
		active = false
		visible = false
		set_physics_process(false)
		return

	if transit_state == TransitState.WAITING and transit_stop != null:
		refresh_transit_stop_target(delta)

	if movement_held:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		move_and_slide()
		return

	var destination: Vector3 = behavior.target_position
	if behavior.state == NpcBehaviorModel.State.FLEEING:
		var away: Vector3 = global_position - behavior.target_position
		if away.length_squared() > 0.001:
			destination = global_position + away.normalized() * 10.0

	var planar: Vector3 = destination - global_position
	planar.y = 0.0
	if planar.length() <= arrival_radius:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		if role == NpcBehaviorModel.Role.POLICE and police_response.phase == NpcPoliceResponse.Phase.RETURN_TO_PATROL:
			mark_police_patrol_anchor_reached()
		move_and_slide()
		return

	var speed_scale := civilian_recovery_movement_scale if role == NpcBehaviorModel.Role.CIVILIAN else 1.0
	var desired: Vector3 = planar.normalized() * behavior.preferred_speed * speed_scale
	velocity.x = move_toward(velocity.x, desired.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired.z, acceleration * delta)
	move_and_slide()

	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	if horizontal_speed > 0.05:
		var target_yaw: float = atan2(-velocity.x, -velocity.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))

func reactivate(spawn_position: Vector3) -> void:
	_leave_transit_queue_if_needed()
	active = true
	visible = true
	_set_world_position(spawn_position)
	behavior.configure(role, variation_seed, spawn_position)
	_configure_pedestrian_context()
	_configure_appearance()
	_configure_ambient_state()
	_configure_response_models(spawn_position)
	_reset_transit_state()
	set_physics_process(true)

func _configure_pedestrian_context() -> void:
	pedestrian_context.configure(variation_seed, behavior.preferred_speed)
	pedestrian_intent = NpcPedestrianContext.PedestrianIntent.CONTINUE
	movement_held = false

func _configure_appearance() -> void:
	appearance.configure(variation_seed, role, weather_context)

func _configure_ambient_state() -> void:
	ambient_state.configure(variation_seed)

func _configure_response_models(spawn_position: Vector3) -> void:
	crowd_reaction.configure(variation_seed)
	police_response.configure(variation_seed, spawn_position)
	civilian_recovery.configure(variation_seed)
	civilian_recovery_movement_scale = 1.0
	civilian_routine_target = behavior.target_position
	if role == NpcBehaviorModel.Role.POLICE:
		_sync_police_response_to_behavior()

func _capture_civilian_routine_snapshot() -> Dictionary:
	var activity_kind: StringName = &"walking"
	if transit_state == TransitState.WAITING:
		activity_kind = &"transit_wait"
	elif transit_state == TransitState.BOARDING:
		activity_kind = &"transit_boarding"
	elif transit_state == TransitState.ONBOARD:
		activity_kind = &"transit_onboard"
	elif transit_state == TransitState.DISEMBARKING:
		activity_kind = &"transit_disembarking"
	elif ambient_state.current_state != NpcAmbientState.State.WALK:
		activity_kind = &"ambient"
	var transit_door_index: int = -1
	if transit_stop != null and transit_queue_passenger_id >= 0:
		transit_door_index = transit_stop.assigned_door_for(transit_queue_passenger_id)
	return {
		"activity_kind": activity_kind,
		"transit_state": transit_state,
		"passenger_id": transit_queue_passenger_id,
		"transit_door_index": transit_door_index,
		"transit_queue": transit_queue,
		"transit_stop": transit_stop,
		"ambient_state": ambient_state.current_state,
		"ambient_sequence_index": ambient_state.sequence_index,
		"pedestrian_intent": pedestrian_intent,
		"movement_held": movement_held,
		"routine_target": civilian_routine_target,
	}

func _restore_civilian_routine_snapshot(snapshot: Dictionary) -> void:
	var routine_target_value: Variant = snapshot.get("routine_target", civilian_routine_target)
	if routine_target_value is Vector3:
		civilian_routine_target = routine_target_value as Vector3
	ambient_state.current_state = int(snapshot.get("ambient_state", NpcAmbientState.State.WALK))
	ambient_state.sequence_index = int(snapshot.get("ambient_sequence_index", ambient_state.sequence_index))
	pedestrian_intent = int(snapshot.get("pedestrian_intent", NpcPedestrianContext.PedestrianIntent.CONTINUE))
	var restored_transit_state: int = int(snapshot.get("transit_state", TransitState.NONE))
	var activity_kind: StringName = StringName(snapshot.get("activity_kind", &"walking"))
	if activity_kind == &"transit_wait":
		var queue_value: Variant = snapshot.get("transit_queue", null)
		var stop_value: Variant = snapshot.get("transit_stop", null)
		var passenger_id: int = int(snapshot.get("passenger_id", -1))
		var preferred_door: int = int(snapshot.get("transit_door_index", -1))
		transit_queue = queue_value as NpcTransitQueue if queue_value is NpcTransitQueue else null
		transit_stop = stop_value as NpcTransitStop if stop_value is NpcTransitStop else null
		transit_queue_passenger_id = passenger_id
		if transit_stop != null and passenger_id >= 0:
			var assigned_door: int = transit_stop.assigned_door_for(passenger_id)
			if assigned_door < 0:
				assigned_door = transit_stop.join_waiting_passenger(passenger_id, preferred_door)
			if assigned_door >= 0:
				transit_queue = transit_stop.queue_for_door(assigned_door)
			else:
				transit_queue = null
				transit_stop = null
				transit_queue_passenger_id = -1
				restored_transit_state = TransitState.NONE
		elif transit_queue != null and passenger_id >= 0 and transit_queue.position_index_for(passenger_id) < 0:
			if transit_queue.join_queue(passenger_id) < 0:
				transit_queue = null
				transit_queue_passenger_id = -1
				restored_transit_state = TransitState.NONE
		if transit_queue != null and transit_queue_passenger_id >= 0:
			transit_state = TransitState.WAITING
			ambient_state.set_transit_context(true, false)
			pedestrian_intent = NpcPedestrianContext.PedestrianIntent.WAIT_FOR_TRANSIT
			if transit_stop != null:
				refresh_transit_stop_target()
			else:
				_apply_transit_queue_target(transit_queue.position_for(transit_queue_passenger_id))
			return
	transit_state = restored_transit_state if restored_transit_state in [TransitState.NONE, TransitState.BOARDING, TransitState.ONBOARD, TransitState.DISEMBARKING] else TransitState.NONE
	if transit_state == TransitState.NONE:
		transit_queue = null
		transit_stop = null
		transit_queue_passenger_id = -1
		_reset_transit_queue_target_tracking()
	behavior.set_destination(civilian_routine_target)
	if activity_kind == &"ambient":
		movement_held = ambient_state.movement_scale() <= 0.0
	else:
		movement_held = bool(snapshot.get("movement_held", false))

func _sync_police_response_to_behavior() -> void:
	behavior.target_position = police_response.target_position()
	match police_response.phase:
		NpcPoliceResponse.Phase.PATROL:
			behavior.state = NpcBehaviorModel.State.PATROLLING
			behavior.alert_level = 0.0
		NpcPoliceResponse.Phase.INVESTIGATE:
			behavior.state = NpcBehaviorModel.State.INVESTIGATING
			behavior.alert_level = maxf(behavior.alert_level, NpcBehaviorModel.POLICE_INVESTIGATE_THRESHOLD)
		NpcPoliceResponse.Phase.PURSUIT:
			behavior.state = NpcBehaviorModel.State.PURSUING
			behavior.alert_level = maxf(behavior.alert_level, NpcBehaviorModel.POLICE_PURSUIT_THRESHOLD)
		NpcPoliceResponse.Phase.DEESCALATE, NpcPoliceResponse.Phase.RETURN_TO_PATROL:
			behavior.state = NpcBehaviorModel.State.RETURNING
			behavior.alert_level = minf(behavior.alert_level, NpcBehaviorModel.POLICE_INVESTIGATE_THRESHOLD - 1.0)

func _apply_transit_queue_target(target: Vector3) -> void:
	_transit_queue_applied_target = target
	_transit_queue_has_applied_target = true
	behavior.set_destination(target)
	var planar_distance := Vector2(target.x - get_world_position().x, target.z - get_world_position().z).length()
	movement_held = planar_distance <= arrival_radius

func _reset_transit_queue_target_tracking() -> void:
	_transit_queue_applied_target = Vector3.ZERO
	_transit_queue_pending_target = Vector3.ZERO
	_transit_queue_has_applied_target = false
	_transit_queue_has_pending_target = false
	_transit_queue_compaction_remaining_s = 0.0

func _reset_transit_state() -> void:
	transit_state = TransitState.NONE
	pedestrian_intent = NpcPedestrianContext.PedestrianIntent.CONTINUE
	movement_held = false
	ambient_state.set_transit_context(false, false)
	_reset_transit_queue_target_tracking()

func _leave_transit_queue_if_needed() -> void:
	if transit_queue == null or transit_queue_passenger_id < 0:
		transit_queue = null
		transit_queue_passenger_id = -1
		transit_stop = null
		_reset_transit_queue_target_tracking()
		return
	var passenger_id: int = transit_queue_passenger_id
	transit_queue.leave_queue(passenger_id)
	if transit_stop != null:
		transit_stop.leave_waiting_passenger(passenger_id)
	transit_queue = null
	transit_queue_passenger_id = -1
	transit_stop = null
	_reset_transit_queue_target_tracking()

func _set_world_position(world_position: Vector3) -> void:
	if is_inside_tree():
		global_position = world_position
	else:
		position = world_position
