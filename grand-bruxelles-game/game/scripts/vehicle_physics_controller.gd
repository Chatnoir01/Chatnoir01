extends RigidBody3D

const DYNAMICS_SCRIPT := preload("res://game/scripts/vehicle_dynamics_60hz.gd")

const WHEEL_OFFSETS: Array[Vector3] = [
    Vector3(-0.72, 0.0, -1.35),
    Vector3(0.72, 0.0, -1.35),
    Vector3(-0.72, 0.0, 1.35),
    Vector3(0.72, 0.0, 1.35),
]

@export var exit_distance: float = 2.7
@export var mouse_sensitivity: float = 0.0022
@export var suspension_rest_length_m: float = 0.85
@export var suspension_ray_length_m: float = 1.15

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D

var driver: CharacterBody3D = null
var dynamics := DYNAMICS_SCRIPT.new()
var throttle: float = 0.0
var brake: float = 0.0
var steering: float = 0.0
var _exit_unlock_ms: int = 0
var _suspension_rays: Array[RayCast3D] = []
var _control_override_enabled: bool = false


func _ready() -> void:
    mass = dynamics.mass_kg
    can_sleep = false
    continuous_cd = true
    contact_monitor = true
    max_contacts_reported = 8
    axis_lock_angular_x = true
    axis_lock_angular_z = true
    _ensure_suspension_rays()


func _ensure_suspension_rays() -> void:
    if not _suspension_rays.is_empty():
        return
    for index: int in range(WHEEL_OFFSETS.size()):
        var ray := RayCast3D.new()
        ray.name = "SuspensionRay%d" % index
        ray.position = WHEEL_OFFSETS[index]
        ray.target_position = Vector3(0.0, -suspension_ray_length_m, 0.0)
        ray.enabled = true
        ray.exclude_parent = true
        add_child(ray)
        _suspension_rays.append(ray)


func _physics_process(_delta: float) -> void:
    if _control_override_enabled:
        return

    throttle = 0.0
    brake = 0.0
    steering = 0.0
    if driver == null:
        return

    var forward_pressed := Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_Z)
    var reverse_pressed := Input.is_key_pressed(KEY_S)
    var left_pressed := Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_Q)
    var right_pressed := Input.is_key_pressed(KEY_D)
    var touch := get_parent().get_node_or_null("MobileControls")
    var analog := Vector2.ZERO
    if touch != null:
        forward_pressed = forward_pressed or bool(touch.get("forward_pressed"))
        reverse_pressed = reverse_pressed or bool(touch.get("backward_pressed"))
        left_pressed = left_pressed or bool(touch.get("left_pressed"))
        right_pressed = right_pressed or bool(touch.get("right_pressed"))
        if touch.has_method("get_movement_vector"):
            var value: Variant = touch.call("get_movement_vector")
            if value is Vector2:
                analog = value as Vector2

    if analog.length() > 0.01:
        steering = clampf(analog.x, -1.0, 1.0)
        if analog.y < -0.08:
            throttle = clampf(-analog.y, 0.0, 1.0)
        elif analog.y > 0.08:
            if forward_speed_ms() > 1.0:
                brake = clampf(analog.y, 0.0, 1.0)
            else:
                throttle = -clampf(analog.y, 0.0, 1.0)
    else:
        steering = float(right_pressed) - float(left_pressed)
        if forward_pressed and not reverse_pressed:
            throttle = 1.0
        elif reverse_pressed and not forward_pressed:
            if forward_speed_ms() > 1.0:
                brake = 1.0
            else:
                throttle = -1.0


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
    var dt := maxf(state.step, 0.0001)
    var basis := global_transform.basis.orthonormalized()
    var up := basis.y.normalized()
    var forward := -basis.z.normalized()
    var right := basis.x.normalized()

    var supported_wheels := 0
    var suspension_force_total := 0.0
    var vertical_speed := state.linear_velocity.dot(up)
    for ray: RayCast3D in _suspension_rays:
        ray.force_raycast_update()
        if not ray.is_colliding():
            continue
        var distance_m := ray.global_position.distance_to(ray.get_collision_point())
        if distance_m > suspension_rest_length_m:
            continue
        var compression_m := suspension_rest_length_m - distance_m
        suspension_force_total += dynamics.suspension_force(compression_m, vertical_speed)
        supported_wheels += 1
    if supported_wheels > 0 and suspension_force_total > 0.0:
        state.apply_central_force(up * suspension_force_total)

    var velocity_now := state.linear_velocity
    var forward_speed := velocity_now.dot(forward)
    var next_forward_speed := dynamics.longitudinal_step(forward_speed, throttle, brake, dt)
    var longitudinal_acceleration := (next_forward_speed - forward_speed) / dt
    state.apply_central_force(forward * longitudinal_acceleration * dynamics.mass_kg)

    var lateral_speed := velocity_now.dot(right)
    var normal_load := dynamics.static_wheel_load_n(4) * maxf(float(supported_wheels), 1.0)
    var lateral_force := dynamics.lateral_tire_force(lateral_speed, normal_load)
    state.apply_central_force(right * lateral_force)

    var steer_deg := dynamics.steer_angle_deg(steering, next_forward_speed)
    var steer_response := clampf(absf(next_forward_speed) / 8.0, 0.0, 1.0)
    var target_yaw_rate := -deg_to_rad(steer_deg) * steer_response * 1.35
    state.angular_velocity.y = move_toward(state.angular_velocity.y, target_yaw_rate, dt * 4.5)


func _unhandled_input(event: InputEvent) -> void:
    if driver == null:
        return
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        camera_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
        camera_pivot.rotation.y = clampf(camera_pivot.rotation.y, -1.35, 1.35)
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_E and Time.get_ticks_msec() >= _exit_unlock_ms:
            exit_driver()
        elif event.keycode == KEY_ESCAPE:
            Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED


func enter_driver(player: CharacterBody3D) -> void:
    if driver != null:
        return
    driver = player
    throttle = 0.0
    brake = 0.0
    steering = 0.0
    linear_velocity = Vector3.ZERO
    angular_velocity = Vector3.ZERO
    _exit_unlock_ms = Time.get_ticks_msec() + 350
    camera_pivot.rotation.y = 0.0
    player.call("set_vehicle_mode", true)
    camera.current = true
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if DisplayServer.is_touchscreen_available() else Input.MOUSE_MODE_CAPTURED


func exit_driver() -> void:
    if driver == null:
        return
    var player := driver
    driver = null
    throttle = 0.0
    brake = 0.0
    steering = 0.0
    linear_velocity = Vector3.ZERO
    angular_velocity = Vector3.ZERO
    var side := global_transform.basis.x.normalized()
    player.global_position = global_position + side * exit_distance + Vector3.UP * 0.8
    player.rotation.y = rotation.y
    player.call("set_vehicle_mode", false)


func has_driver() -> bool:
    return driver != null


func forward_speed_ms() -> float:
    return linear_velocity.dot(-global_transform.basis.z.normalized())


func supported_wheel_count() -> int:
    var count := 0
    for ray: RayCast3D in _suspension_rays:
        ray.force_raycast_update()
        if ray.is_colliding() and ray.global_position.distance_to(ray.get_collision_point()) <= suspension_rest_length_m:
            count += 1
    return count


func set_control_state(new_throttle: float, new_brake: float, new_steering: float) -> void:
    _control_override_enabled = true
    throttle = clampf(new_throttle, -1.0, 1.0)
    brake = clampf(new_brake, 0.0, 1.0)
    steering = clampf(new_steering, -1.0, 1.0)


func clear_control_override() -> void:
    _control_override_enabled = false
    throttle = 0.0
    brake = 0.0
    steering = 0.0
