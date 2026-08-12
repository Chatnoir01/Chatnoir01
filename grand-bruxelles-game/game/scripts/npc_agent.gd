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
var pedestrian_intent: int = NpcPedestrianContext.PedestrianIntent.CONTINUE
var weather_context: int = NpcAppearanceProfile.WeatherContext.MILD
var transit_state: int = TransitState.NONE
var observer_position := Vector3.ZERO
var active := true
var movement_held := false

func _ready() -> void:
	behavior.configure(role, variation_seed, global_position)
	_configure_pedestrian_context()
	_configure_appearance()

func set_spawn_context(new_role: NpcBehaviorModel.Role, seed_value: int, spawn_position: Vector3) -> void:
	role = new_role
	variation_seed = seed_value
	_set_world_position(spawn_position)
	behavior.configure(new_role, seed_value, spawn_position)
	_configure_pedestrian_context()
	_configure_appearance()
	_reset_transit_state()

func set_weather_context(new_weather_context: int) -> void:
	weather_context = clampi(new_weather_context, NpcAppearanceProfile.WeatherContext.MILD, NpcAppearanceProfile.WeatherContext.COLD)
	_configure_appearance()

func get_appearance_profile() -> Dictionary:
	return appearance.as_dictionary().duplicate(true)

func get_world_position() -> Vector3:
	if is_inside_tree():
		return global_position
	return position

func set_destination(destination: Vector3) -> void:
	behavior.set_destination(destination)

func react_to_event(intensity: float, world_position: Vector3) -> void:
	behavior.apply_stimulus(intensity, world_position)

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
	elif pedestrian_intent == NpcPedestrianContext.PedestrianIntent.BOARD_TRANSIT:
		transit_state = TransitState.BOARDING
	else:
		transit_state = TransitState.NONE
	movement_held = transit_state == TransitState.WAITING or transit_state == TransitState.BOARDING
	return pedestrian_intent

func confirm_boarded() -> bool:
	if transit_state != TransitState.BOARDING:
		return false
	transit_state = TransitState.ONBOARD
	movement_held = true
	velocity = Vector3.ZERO
	return true

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

func _physics_process(delta: float) -> void:
	if not active:
		velocity = Vector3.ZERO
		return

	behavior.calm_down(calm_rate * delta)
	if behavior.should_despawn(observer_position, despawn_distance):
		active = false
		visible = false
		set_physics_process(false)
		return

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
		move_and_slide()
		return

	var desired: Vector3 = planar.normalized() * behavior.preferred_speed
	velocity.x = move_toward(velocity.x, desired.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired.z, acceleration * delta)
	move_and_slide()

	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	if horizontal_speed > 0.05:
		var target_yaw: float = atan2(-velocity.x, -velocity.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))

func reactivate(spawn_position: Vector3) -> void:
	active = true
	visible = true
	_set_world_position(spawn_position)
	behavior.configure(role, variation_seed, spawn_position)
	_configure_pedestrian_context()
	_configure_appearance()
	_reset_transit_state()
	set_physics_process(true)

func _configure_pedestrian_context() -> void:
	pedestrian_context.configure(variation_seed, behavior.preferred_speed)
	pedestrian_intent = NpcPedestrianContext.PedestrianIntent.CONTINUE
	movement_held = false

func _configure_appearance() -> void:
	appearance.configure(variation_seed, role, weather_context)

func _reset_transit_state() -> void:
	transit_state = TransitState.NONE
	pedestrian_intent = NpcPedestrianContext.PedestrianIntent.CONTINUE
	movement_held = false

func _set_world_position(world_position: Vector3) -> void:
	if is_inside_tree():
		global_position = world_position
	else:
		position = world_position
