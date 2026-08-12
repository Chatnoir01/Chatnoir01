extends CharacterBody3D

@export var walk_speed: float = 6.0
@export var sprint_speed: float = 10.0
@export var acceleration: float = 18.0
@export var jump_velocity: float = 5.5
@export var mouse_sensitivity: float = 0.0025
@export var vehicle_interaction_range: float = 4.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D

const BOURSE_DIRECT_SPAWN_POSITION := Vector3(83.44, 1.05, -663.42)
# Faces the authoritative UrbIS LoD2 Bourse bbox center from the direct-test position.
const BOURSE_DIRECT_SPAWN_YAW_DEGREES := -84.32

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var _base_collision_layer: int = 1
var _base_collision_mask: int = 1


func _ready() -> void:
    _base_collision_layer = collision_layer
    _base_collision_mask = collision_mask
    _apply_direct_spawn_from_user_args(OS.get_cmdline_user_args())
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if DisplayServer.is_touchscreen_available() else Input.MOUSE_MODE_CAPTURED


func _apply_direct_spawn_from_user_args(args: PackedStringArray) -> void:
    for arg: String in args:
        if arg.strip_edges().to_lower() != "spawn=bourse":
            continue
        global_position = BOURSE_DIRECT_SPAWN_POSITION
        rotation_degrees.y = BOURSE_DIRECT_SPAWN_YAW_DEGREES
        velocity = Vector3.ZERO
        print("Direct test spawn: Bourse / Beursplein")
        return


func _unhandled_input(event: InputEvent) -> void:
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
    if not is_on_floor():
        velocity.y -= gravity * delta

    var mobile := _mobile_controls()
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
        var distance: float = global_position.distance_to(vehicle.global_position)
        if distance <= nearest_distance:
            nearest_vehicle = vehicle
            nearest_distance = distance

    if nearest_vehicle != null:
        nearest_vehicle.call("enter_driver", self)


func set_vehicle_mode(enabled: bool) -> void:
    visible = not enabled
    set_physics_process(not enabled)
    set_process_unhandled_input(not enabled)
    velocity = Vector3.ZERO

    if enabled:
        collision_layer = 0
        collision_mask = 0
    else:
        collision_layer = _base_collision_layer
        collision_mask = _base_collision_mask
        camera.current = true
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if DisplayServer.is_touchscreen_available() else Input.MOUSE_MODE_CAPTURED
