extends CharacterBody3D

@export var walk_speed: float = 6.0
@export var sprint_speed: float = 10.0
@export var acceleration: float = 18.0
@export var jump_velocity: float = 5.5
@export var mouse_sensitivity: float = 0.0025

@onready var camera_pivot: Node3D = $CameraPivot

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        rotate_y(-event.relative.x * mouse_sensitivity)
        camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
        camera_pivot.rotation.x = clamp(
            camera_pivot.rotation.x,
            deg_to_rad(-60.0),
            deg_to_rad(35.0)
        )

    if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        Input.mouse_mode = (
            Input.MOUSE_MODE_VISIBLE
            if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
            else Input.MOUSE_MODE_CAPTURED
        )


func _physics_process(delta: float) -> void:
    if not is_on_floor():
        velocity.y -= gravity * delta

    if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
        velocity.y = jump_velocity

    var input_2d := Vector2(
        float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
        float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
    )

    # AZERTY support: Z/Q mirror W/A.
    input_2d.x += float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_Q))
    input_2d.y += float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_Z))
    input_2d = input_2d.limit_length(1.0)

    var move_direction := Vector3(input_2d.x, 0.0, input_2d.y)
    move_direction = move_direction.rotated(Vector3.UP, rotation.y).normalized()

    var target_speed := sprint_speed if Input.is_key_pressed(KEY_SHIFT) else walk_speed
    var target_velocity := move_direction * target_speed

    velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
    velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)

    move_and_slide()
