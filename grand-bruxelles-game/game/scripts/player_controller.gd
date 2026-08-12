extends CharacterBody3D

@export var walk_speed: float = 6.0
@export var sprint_speed: float = 10.0
@export var acceleration: float = 18.0
@export var jump_velocity: float = 5.5
@export var mouse_sensitivity: float = 0.0025
@export var vehicle_interaction_range: float = 4.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var _base_collision_layer: int = 1
var _base_collision_mask: int = 1
var _active_vehicle: Node3D = null
var _arrested: bool = false
var _spawn_transform: Transform3D


func _ready() -> void:
    _base_collision_layer = collision_layer
    _base_collision_mask = collision_mask
    _spawn_transform = global_transform
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if DisplayServer.is_touchscreen_available() else Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
    if _arrested:
        return

    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        rotate_y(-event.relative.x * mouse_sensitivity)
        camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
        camera_pivot.rotation.x = clampf(
            camera_pivot.rotation.x,
            deg_to_rad(-60.0),
            deg_to_rad(35.0)
        )

    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_E:
            try_enter_vehicle()
        elif event.keycode == KEY_ESCAPE:
            Input.mouse_mode = (
                Input.MOUSE_MODE_VISIBLE
                if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
                else Input.MOUSE_MODE_CAPTURED
            )


func _physics_process(delta: float) -> void:
    if _arrested:
        velocity = Vector3.ZERO
        return

    if not is_on_floor():
        velocity.y -= gravity * delta

    var mobile: Node = _mobile_controls()
    var touch_jump: bool = mobile != null and bool(mobile.get("jump_pressed"))
    if (Input.is_key_pressed(KEY_SPACE) or touch_jump) and is_on_floor():
        velocity.y = jump_velocity

    var left: bool = Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_Q)
    var right: bool = Input.is_key_pressed(KEY_D)
    var forward: bool = Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_Z)
    var backward: bool = Input.is_key_pressed(KEY_S)
    var sprint: bool = Input.is_key_pressed(KEY_SHIFT)

    if mobile != null:
        left = left or bool(mobile.get("left_pressed"))
        right = right or bool(mobile.get("right_pressed"))
        forward = forward or bool(mobile.get("forward_pressed"))
        backward = backward or bool(mobile.get("backward_pressed"))
        sprint = sprint or bool(mobile.get("sprint_pressed"))

    var input_2d: Vector2 = Vector2(
        float(right) - float(left),
        float(backward) - float(forward)
    ).limit_length(1.0)

    var move_direction: Vector3 = Vector3(input_2d.x, 0.0, input_2d.y)
    move_direction = move_direction.rotated(Vector3.UP, rotation.y).normalized()

    var target_speed: float = sprint_speed if sprint else walk_speed
    var target_velocity: Vector3 = move_direction * target_speed

    velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
    velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)

    move_and_slide()


func _mobile_controls() -> Node:
    return get_parent().get_node_or_null("MobileControls")


func try_enter_vehicle() -> void:
    if _arrested:
        return

    var nearest_vehicle: Node3D = null
    var nearest_distance: float = vehicle_interaction_range

    for candidate: Node in get_tree().get_nodes_in_group("vehicle"):
        if not candidate is Node3D:
            continue
        var vehicle: Node3D = candidate as Node3D
        if not vehicle.has_method("enter_driver"):
            continue
        if vehicle.has_method("has_driver") and bool(vehicle.call("has_driver")):
            continue
        if vehicle.has_method("is_ai_controlled") and bool(vehicle.call("is_ai_controlled")):
            continue
        var distance: float = global_position.distance_to(vehicle.global_position)
        if distance <= nearest_distance:
            nearest_vehicle = vehicle
            nearest_distance = distance

    if nearest_vehicle != null:
        if nearest_vehicle.is_in_group("police_vehicle"):
            var wanted: Node = get_tree().get_first_node_in_group("wanted_system")
            if wanted != null and wanted.has_method("report_offence"):
                wanted.call("report_offence", 28.0, "police_vehicle_theft")
        nearest_vehicle.call("enter_driver", self)


func set_vehicle_mode(enabled: bool, vehicle: Node3D = null) -> void:
    visible = not enabled
    set_physics_process(not enabled and not _arrested)
    set_process_unhandled_input(not enabled and not _arrested)
    velocity = Vector3.ZERO
    _active_vehicle = vehicle if enabled else null

    if enabled:
        collision_layer = 0
        collision_mask = 0
    else:
        collision_layer = _base_collision_layer
        collision_mask = _base_collision_mask
        camera.current = true
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if DisplayServer.is_touchscreen_available() else Input.MOUSE_MODE_CAPTURED


func get_gameplay_position() -> Vector3:
    if is_instance_valid(_active_vehicle):
        return _active_vehicle.global_position
    return global_position


func get_gameplay_velocity() -> Vector3:
    if is_instance_valid(_active_vehicle) and _active_vehicle is CharacterBody3D:
        return (_active_vehicle as CharacterBody3D).velocity
    return velocity


func get_gameplay_forward() -> Vector3:
    if is_instance_valid(_active_vehicle):
        return -_active_vehicle.global_transform.basis.z.normalized()
    return -global_transform.basis.z.normalized()


func is_in_vehicle() -> bool:
    return is_instance_valid(_active_vehicle)


func set_arrested(enabled: bool) -> void:
    _arrested = enabled
    velocity = Vector3.ZERO
    if not is_in_vehicle():
        set_physics_process(not enabled)
        set_process_unhandled_input(not enabled)


func is_arrested() -> bool:
    return _arrested


func reset_after_arrest() -> void:
    if is_in_vehicle():
        return
    global_transform = _spawn_transform
    velocity = Vector3.ZERO
    camera.current = true
