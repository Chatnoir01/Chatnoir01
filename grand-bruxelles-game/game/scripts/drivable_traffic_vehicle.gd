extends "res://game/scripts/traffic_vehicle_core.gd"
class_name DrivableTrafficVehicle

signal driver_entered(vehicle: Node, driver_node: Node)
signal driver_exited(vehicle: Node, driver_node: Node)

@export var manual_max_forward_speed_mps: float = 24.0
@export var manual_max_reverse_speed_mps: float = 8.0
@export var manual_acceleration_mps2: float = 12.0
@export var manual_braking_mps2: float = 20.0
@export var manual_coast_drag_mps2: float = 7.5
@export var manual_steering_speed: float = 1.55
@export var manual_exit_distance_m: float = 2.7
@export var manual_mouse_sensitivity: float = 0.0022
@export var camera_spring_length_m: float = 6.1

var driver: CharacterBody3D = null
var external_driver: Node = null
var _manual_speed_mps: float = 0.0
var _external_throttle: float = 0.0
var _external_steering: float = 0.0
var _external_brake: float = 0.0
var _visual_steering_angle: float = 0.0
var _exit_unlock_ms: int = 0
var _parked_mode: bool = false
var _camera_pivot: Node3D = null
var _camera: Camera3D = null

func _ready() -> void:
    super._ready()
    if traffic_archetype == "car":
        add_to_group("vehicle")
    _ensure_camera_rig()
    if _parked_mode:
        set_physics_process(false)

func configure_archetype(archetype: String) -> void:
    super.configure_archetype(archetype)
    if archetype == "car":
        add_to_group("vehicle")
    elif is_in_group("vehicle"):
        remove_from_group("vehicle")

func configure_as_parked() -> void:
    _parked_mode = true
    speed_mps = 0.0
    velocity = Vector3.ZERO
    if is_inside_tree():
        set_physics_process(false)

func _physics_process(delta: float) -> void:
    if driver != null or external_driver != null:
        _advance_manual_motion(delta)
        return
    if _parked_mode:
        velocity = Vector3.ZERO
        return
    super._physics_process(delta)

func enter_driver(player: CharacterBody3D) -> void:
    if player == null or has_driver() or is_traffic_disabled():
        return
    driver = player
    _manual_speed_mps = speed_mps
    speed_mps = 0.0
    _exit_unlock_ms = Time.get_ticks_msec() + 350
    _ensure_camera_rig()
    if _camera_pivot != null:
        _camera_pivot.rotation.y = 0.0
    if player.has_method("set_vehicle_mode"):
        player.call("set_vehicle_mode", true)
    if _camera != null:
        _camera.current = true
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if DisplayServer.is_touchscreen_available() else Input.MOUSE_MODE_CAPTURED
    if _intersection_system != null:
        _intersection_system.call("release_vehicle", get_instance_id())
    if has_meta("parking_candidate_id"):
        set_meta("parking_departed", true)
    set_physics_process(true)
    driver_entered.emit(self, player)

func exit_driver() -> void:
    if driver == null:
        return
    var player := driver
    driver = null
    if _camera != null:
        _camera.current = false
    var side := global_transform.basis.x.normalized()
    player.global_position = global_position + side * manual_exit_distance_m + Vector3.UP * 0.8
    player.rotation.y = rotation.y
    if player.has_method("set_vehicle_mode"):
        player.call("set_vehicle_mode", false)
    driver_exited.emit(self, player)
    if _parked_mode:
        _manual_speed_mps = 0.0
        velocity = Vector3.ZERO
        set_physics_process(false)
    else:
        _resync_route_after_manual_drive()

func has_driver() -> bool:
    return driver != null or external_driver != null

func is_player_controlled() -> bool:
    return driver != null

func assign_external_driver(controller: Node) -> bool:
    if controller == null or has_driver() or is_traffic_disabled():
        return false
    external_driver = controller
    _manual_speed_mps = speed_mps
    speed_mps = 0.0
    if _intersection_system != null:
        _intersection_system.call("release_vehicle", get_instance_id())
    set_physics_process(true)
    driver_entered.emit(self, controller)
    return true

func release_external_driver(controller: Node = null) -> void:
    if external_driver == null:
        return
    if controller != null and controller != external_driver:
        return
    var released := external_driver
    external_driver = null
    _external_throttle = 0.0
    _external_steering = 0.0
    _external_brake = 0.0
    driver_exited.emit(self, released)
    if _parked_mode:
        _manual_speed_mps = 0.0
        velocity = Vector3.ZERO
        set_physics_process(false)
    else:
        _resync_route_after_manual_drive()

func set_external_drive_input(throttle: float, steering: float, brake: float = 0.0) -> void:
    _external_throttle = clampf(throttle, -1.0, 1.0)
    _external_steering = clampf(steering, -1.0, 1.0)
    _external_brake = clampf(brake, 0.0, 1.0)

func get_visual_steering_angle() -> float:
    return _visual_steering_angle

func _advance_manual_motion(delta: float) -> void:
    var throttle := 0.0
    var steering := 0.0
    var brake := 0.0
    if driver != null:
        var forward_pressed := Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_Z)
        var reverse_pressed := Input.is_key_pressed(KEY_S)
        var left_pressed := Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_Q)
        var right_pressed := Input.is_key_pressed(KEY_D)
        var touch: Node = null
        if get_parent() != null:
            touch = get_parent().get_node_or_null("MobileControls")
        if touch == null and get_tree() != null and get_tree().current_scene != null:
            touch = get_tree().current_scene.get_node_or_null("MobileControls")
        if touch != null:
            forward_pressed = forward_pressed or bool(touch.get("forward_pressed"))
            reverse_pressed = reverse_pressed or bool(touch.get("backward_pressed"))
            left_pressed = left_pressed or bool(touch.get("left_pressed"))
            right_pressed = right_pressed or bool(touch.get("right_pressed"))
        throttle = float(forward_pressed) - float(reverse_pressed)
        steering = float(right_pressed) - float(left_pressed)
    else:
        throttle = _external_throttle
        steering = _external_steering
        brake = _external_brake

    if brake > 0.01:
        _manual_speed_mps = move_toward(_manual_speed_mps, 0.0, manual_braking_mps2 * brake * delta)
    elif throttle > 0.0:
        _manual_speed_mps = move_toward(_manual_speed_mps, manual_max_forward_speed_mps, manual_acceleration_mps2 * throttle * delta)
    elif throttle < 0.0:
        if _manual_speed_mps > 1.0:
            _manual_speed_mps = move_toward(_manual_speed_mps, 0.0, manual_braking_mps2 * -throttle * delta)
        else:
            _manual_speed_mps = move_toward(_manual_speed_mps, -manual_max_reverse_speed_mps, manual_acceleration_mps2 * -throttle * delta)
    else:
        _manual_speed_mps = move_toward(_manual_speed_mps, 0.0, manual_coast_drag_mps2 * delta)

    if not is_on_floor():
        velocity.y -= gravity * delta
    else:
        velocity.y = -0.1
    if absf(_manual_speed_mps) > 0.15 and absf(steering) > 0.01:
        var speed_ratio := clampf(absf(_manual_speed_mps) / maxf(0.1, manual_max_forward_speed_mps), 0.18, 1.0)
        var direction_sign := 1.0 if _manual_speed_mps >= 0.0 else -1.0
        rotation.y -= steering * manual_steering_speed * speed_ratio * direction_sign * delta
    _visual_steering_angle = lerpf(_visual_steering_angle, steering * 0.48, clampf(delta * 9.0, 0.0, 1.0))
    var forward := -global_transform.basis.z
    velocity.x = forward.x * _manual_speed_mps
    velocity.z = forward.z * _manual_speed_mps
    move_and_slide()
    if is_on_wall():
        _manual_speed_mps *= 0.35

func _unhandled_input(event: InputEvent) -> void:
    if driver == null:
        return
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _camera_pivot != null:
        _camera_pivot.rotate_y(-event.relative.x * manual_mouse_sensitivity)
        _camera_pivot.rotation.y = clampf(_camera_pivot.rotation.y, -1.35, 1.35)
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_E and Time.get_ticks_msec() >= _exit_unlock_ms:
            exit_driver()
        elif event.keycode == KEY_ESCAPE:
            Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

func _ensure_camera_rig() -> void:
    if _camera != null and is_instance_valid(_camera):
        return
    _camera_pivot = get_node_or_null("DriverCameraPivot") as Node3D
    if _camera_pivot == null:
        _camera_pivot = Node3D.new()
        _camera_pivot.name = "DriverCameraPivot"
        _camera_pivot.position = Vector3(0.0, 1.32, 0.15)
        _camera_pivot.rotation_degrees.x = -8.0
        add_child(_camera_pivot)
    var arm := _camera_pivot.get_node_or_null("SpringArm3D") as SpringArm3D
    if arm == null:
        arm = SpringArm3D.new()
        arm.name = "SpringArm3D"
        arm.spring_length = camera_spring_length_m
        arm.margin = 0.18
        _camera_pivot.add_child(arm)
    _camera = arm.get_node_or_null("Camera3D") as Camera3D
    if _camera == null:
        _camera = Camera3D.new()
        _camera.name = "Camera3D"
        _camera.current = false
        _camera.fov = 72.0
        arm.add_child(_camera)

func _resync_route_after_manual_drive() -> void:
    _visual_steering_angle = 0.0
    if route_points.size() < 2:
        speed_mps = 0.0
        velocity = Vector3.ZERO
        return
    var best_index := clampi(route_index, 1, route_points.size() - 1)
    var best_distance := INF
    for index: int in range(1, route_points.size()):
        var distance := global_position.distance_squared_to(route_points[index])
        if distance < best_distance:
            best_distance = distance
            best_index = index
    route_index = best_index
    speed_mps = maxf(0.0, _manual_speed_mps)
    _manual_speed_mps = 0.0
    set_physics_process(true)
