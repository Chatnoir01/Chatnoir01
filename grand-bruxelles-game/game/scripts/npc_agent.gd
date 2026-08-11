class_name NpcAgent
extends CharacterBody3D

@export var role: NpcBehaviorModel.Role = NpcBehaviorModel.Role.CIVILIAN
@export var variation_seed: int = 1
@export var acceleration: float = 7.5
@export var turn_speed: float = 7.0
@export var arrival_radius: float = 0.6
@export var calm_rate: float = 7.5
@export var despawn_distance: float = 180.0

var behavior := NpcBehaviorModel.new()
var observer_position := Vector3.ZERO
var active := true

func _ready() -> void:
	behavior.configure(role, variation_seed, global_position)

func set_spawn_context(new_role: NpcBehaviorModel.Role, seed_value: int, spawn_position: Vector3) -> void:
	role = new_role
	variation_seed = seed_value
	global_position = spawn_position
	behavior.configure(new_role, seed_value, spawn_position)

func set_destination(destination: Vector3) -> void:
	behavior.set_destination(destination)

func react_to_event(intensity: float, world_position: Vector3) -> void:
	behavior.apply_stimulus(intensity, world_position)

func set_observer_position(world_position: Vector3) -> void:
	observer_position = world_position

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

	var destination := behavior.target_position
	if behavior.state == NpcBehaviorModel.State.FLEEING:
		var away := global_position - behavior.target_position
		if away.length_squared() > 0.001:
			destination = global_position + away.normalized() * 10.0

	var planar := destination - global_position
	planar.y = 0.0
	if planar.length() <= arrival_radius:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		move_and_slide()
		return

	var desired := planar.normalized() * behavior.preferred_speed
	velocity.x = move_toward(velocity.x, desired.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired.z, acceleration * delta)
	move_and_slide()

	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed > 0.05:
		var target_yaw := atan2(-velocity.x, -velocity.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))

func reactivate(spawn_position: Vector3) -> void:
	active = true
	visible = true
	global_position = spawn_position
	behavior.configure(role, variation_seed, spawn_position)
	set_physics_process(true)
