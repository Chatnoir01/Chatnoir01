extends CharacterBody3D

@export var max_forward_speed: float = 24.0
@export var max_reverse_speed: float = 8.0
@export var acceleration: float = 12.0
@export var braking: float = 20.0
@export var handbrake_strength: float = 30.0
@export var coast_drag: float = 7.5
@export var steering_speed: float = 1.55
@export var exit_distance: float = 2.7
@export var mouse_sensitivity: float = 0.0022

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D

var driver: CharacterBody3D = null
var speed: float = 0.0
var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var _exit_unlock_ms: int = 0


func _physics_process(delta: float) -> void:
    if not is_on_floor():
        velocity.y -= gravity * delta
    else:
        velocity.y = -0.1

    var throttle: float = 0.0
    var steering: float = 0.0
    var handbrake_pressed: bool = false
    if driver != null:
        var forward_pressed: bool = Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_Z)
        var reverse_pressed: bool = Input.is_key_pressed(KEY_S)
        var left_pressed: bool = Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_Q)
        var right_pressed: bool = Input.is_key_pressed(KEY_D)
        handbrake_pressed = Input.is_key_pressed(KEY_SPACE)
        var touch: Node = get_parent().get_node_or_null("MobileControls")
        if touch != null:
            forward_pressed = forward_pressed or bool(touch.get("forward_pressed"))
            reverse_pressed = reverse_pressed or bool(touch.get("backward_pressed"))
            left_pressed = left_pressed or bool(touch.get("left_pressed"))
            right_pressed = right_pressed or bool(touch.get("right_pressed"))
        throttle = float(forward_pressed) - float(reverse_pressed)
        steering = float(right_pressed) - float(left_pressed)

    if handbrake_pressed:
        speed = move_toward(speed, 0.0, handbrake_strength * delta)
    elif throttle > 0.0:
        speed = move_toward(speed, max_forward_speed, acceleration * delta)
    elif throttle < 0.0:
        if speed > 1.0:
            speed = move_toward(speed, 0.0, braking * delta)
        else:
            speed = move_toward(speed, -max_reverse_speed, acceleration * delta)
    else:
        speed = move_toward(speed, 0.0, coast_drag * delta)

    if absf(speed) > 0.15 and absf(steering) > 0.01:
        var speed_ratio: float = clampf(absf(speed) / max_forward_speed, 0.18, 1.0)
        var direction_sign: float = 1.0 if speed >= 0.0 else -1.0
        rotation.y -= steering * steering_speed * speed_ratio * direction_sign * delta

    var forward_vector: Vector3 = -global_transform.basis.z
    velocity.x = forward_vector.x * speed
    velocity.z = forward_vector.z * speed
    move_and_slide()

    if is_on_wall():
        speed *= 0.35


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
    speed = 0.0
    _exit_unlock_ms = Time.get_ticks_msec() + 350
    camera_pivot.rotation.y = 0.0
    player.call("set_vehicle_mode", true)
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
    player.call("set_vehicle_mode", false)


func has_driver() -> bool:
    return driver != null


func get_speed_mps() -> float:
    return speed


func get_speed_kmh() -> float:
    return absf(speed) * 3.6


func get_max_forward_speed_kmh() -> float:
    return max_forward_speed * 3.6
