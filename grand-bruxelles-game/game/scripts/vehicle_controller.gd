extends CharacterBody3D

@export var max_forward_speed: float = 24.0
@export var max_reverse_speed: float = 8.0
@export var acceleration: float = 12.0
@export var braking: float = 20.0
@export var coast_drag: float = 7.5
@export var steering_speed: float = 1.55
@export var exit_distance: float = 2.7
@export var mouse_sensitivity: float = 0.0022
@export var emergency_yield_range: float = 20.0
@export var ai_max_speed: float = 22.0
@export var ai_route_update_interval: float = 0.28
@export var ai_target_lead_seconds: float = 0.7
@export var ai_steering_gain: float = 1.55
@export var ai_stop_distance: float = 3.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D

var driver: CharacterBody3D = null
var speed: float = 0.0
var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var _exit_unlock_ms: int = 0
var _ai_enabled: bool = false
var _ai_target: Node3D = null
var _ai_router: Node = null
var _ai_route_point: Vector3 = Vector3.ZERO
var _ai_route_timer: float = 0.0
var _ai_reverse_timer: float = 0.0
var _ai_last_steering: float = 0.0


func _physics_process(delta: float) -> void:
    if not is_on_floor():
        velocity.y -= gravity * delta
    else:
        velocity.y = -0.1

    var throttle: float = 0.0
    var steering: float = 0.0
    if driver != null:
        var forward_pressed: bool = Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_Z)
        var reverse_pressed: bool = Input.is_key_pressed(KEY_S)
        var left_pressed: bool = Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_Q)
        var right_pressed: bool = Input.is_key_pressed(KEY_D)
        var touch: Node = get_parent().get_node_or_null("MobileControls")
        if touch != null:
            forward_pressed = forward_pressed or bool(touch.get("forward_pressed"))
            reverse_pressed = reverse_pressed or bool(touch.get("backward_pressed"))
            left_pressed = left_pressed or bool(touch.get("left_pressed"))
            right_pressed = right_pressed or bool(touch.get("right_pressed"))
        throttle = float(forward_pressed) - float(reverse_pressed)
        steering = float(right_pressed) - float(left_pressed)
    elif _ai_enabled:
        var controls: Vector2 = _compute_ai_controls(delta)
        throttle = controls.x
        steering = controls.y

    var forward_limit: float = max_forward_speed
    if _ai_enabled and driver == null:
        forward_limit = minf(max_forward_speed, ai_max_speed)

    if throttle > 0.0:
        speed = move_toward(speed, forward_limit, acceleration * throttle * delta)
    elif throttle < 0.0:
        if speed > 1.0:
            speed = move_toward(speed, 0.0, braking * absf(throttle) * delta)
        else:
            speed = move_toward(speed, -max_reverse_speed, acceleration * absf(throttle) * delta)
    else:
        speed = move_toward(speed, 0.0, coast_drag * delta)

    if absf(speed) > 0.15 and absf(steering) > 0.01:
        var speed_ratio: float = clampf(absf(speed) / maxf(1.0, max_forward_speed), 0.18, 1.0)
        var direction_sign: float = 1.0 if speed >= 0.0 else -1.0
        rotation.y -= steering * steering_speed * speed_ratio * direction_sign * delta

    var forward_vector: Vector3 = -global_transform.basis.z
    velocity.x = forward_vector.x * speed
    velocity.z = forward_vector.z * speed
    move_and_slide()

    if is_on_wall():
        speed *= 0.35
        if _ai_enabled and driver == null and _ai_reverse_timer <= 0.0:
            _ai_reverse_timer = 0.55


func _compute_ai_controls(delta: float) -> Vector2:
    if not is_instance_valid(_ai_target):
        return Vector2.ZERO

    var target_position: Vector3 = _ai_target.global_position
    if _ai_target.has_method("get_gameplay_position"):
        target_position = _ai_target.call("get_gameplay_position") as Vector3

    var target_velocity: Vector3 = Vector3.ZERO
    if _ai_target.has_method("get_gameplay_velocity"):
        target_velocity = _ai_target.call("get_gameplay_velocity") as Vector3
    var predicted_target: Vector3 = target_position + target_velocity * ai_target_lead_seconds

    _ai_route_timer -= delta
    if _ai_route_timer <= 0.0 or global_position.distance_to(_ai_route_point) < 4.0:
        _ai_route_timer = ai_route_update_interval
        var heading: Vector3 = -global_transform.basis.z
        if _ai_router != null and _ai_router.has_method("next_pursuit_point"):
            _ai_route_point = _ai_router.call("next_pursuit_point", global_position, predicted_target, heading) as Vector3
        else:
            _ai_route_point = predicted_target

    var to_route: Vector3 = _ai_route_point - global_position
    to_route.y = 0.0
    var to_target: Vector3 = target_position - global_position
    to_target.y = 0.0
    if to_route.length_squared() < 0.01:
        to_route = to_target
    if to_route.length_squared() < 0.01:
        return Vector2.ZERO

    var desired: Vector3 = to_route.normalized()
    var right: Vector3 = global_transform.basis.x.normalized()
    var forward: Vector3 = -global_transform.basis.z.normalized()
    var steering: float = clampf(right.dot(desired) * ai_steering_gain, -1.0, 1.0)
    _ai_last_steering = steering

    if _ai_reverse_timer > 0.0:
        _ai_reverse_timer -= delta
        var reverse_steer: float = -_ai_last_steering if absf(_ai_last_steering) > 0.05 else 0.65
        return Vector2(-1.0, reverse_steer)

    var target_distance: float = to_target.length()
    if target_distance <= ai_stop_distance:
        return Vector2(-0.7 if speed > 1.0 else 0.0, steering)

    var alignment: float = clampf(forward.dot(desired), -1.0, 1.0)
    var corner_factor: float = clampf((alignment + 1.0) * 0.5, 0.28, 1.0)
    var desired_speed: float = ai_max_speed * corner_factor
    if target_distance < 12.0:
        desired_speed = minf(desired_speed, maxf(5.0, target_distance * 0.65))

    var throttle: float = 0.0
    if speed < desired_speed - 0.5:
        throttle = 1.0
    elif speed > desired_speed + 1.0:
        throttle = -0.75
    else:
        throttle = 0.18
    return Vector2(throttle, steering)


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
    if driver != null or _ai_enabled:
        return
    driver = player
    speed = 0.0
    _exit_unlock_ms = Time.get_ticks_msec() + 350
    camera_pivot.rotation.y = 0.0
    player.call("set_vehicle_mode", true, self)
    camera.current = true
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if DisplayServer.is_touchscreen_available() else Input.MOUSE_MODE_CAPTURED


func exit_driver() -> void:
    if driver == null:
        return
    var player: CharacterBody3D = driver
    driver = null
    speed = 0.0
    var side: Vector3 = global_transform.basis.x.normalized()
    player.global_position = global_position + side * exit_distance + Vector3.UP * 0.8
    player.rotation.y = rotation.y
    player.call("set_vehicle_mode", false, null)


func has_driver() -> bool:
    return driver != null


func set_ai_pursuit(target: Node3D, router: Node = null) -> void:
    if driver != null:
        return
    _ai_target = target
    _ai_router = router
    _ai_enabled = target != null
    _ai_route_timer = 0.0
    _ai_reverse_timer = 0.0
    speed = 0.0


func clear_ai_control() -> void:
    _ai_enabled = false
    _ai_target = null
    _ai_router = null
    _ai_route_point = global_position
    _ai_route_timer = 0.0
    _ai_reverse_timer = 0.0
    speed = 0.0


func is_ai_controlled() -> bool:
    return _ai_enabled


func get_ai_route_point() -> Vector3:
    return _ai_route_point


func get_emergency_yield_factor() -> float:
    if not is_in_group("traffic_vehicle"):
        return 1.0
    for candidate: Node in get_tree().get_nodes_in_group("police_vehicle"):
        if candidate == self or not candidate is Node3D:
            continue
        var emergency_vehicle: Node3D = candidate as Node3D
        if global_position.distance_to(emergency_vehicle.global_position) > emergency_yield_range:
            continue
        var visuals: Node = emergency_vehicle.get_node_or_null("EmergencyVisuals")
        if visuals != null and visuals.has_method("are_emergency_lights_active"):
            if bool(visuals.call("are_emergency_lights_active")):
                return 0.18
    return 1.0
