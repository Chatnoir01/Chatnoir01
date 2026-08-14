extends CharacterBody3D
class_name GrandBruxellesPlayerLocomotionBody

const PROFILE := preload("res://game/prototypes/player/player_locomotion_profile.gd")

var profile := PROFILE.new()
var input_axis := Vector2.ZERO
var camera_yaw_rad: float = 0.0
var sprinting: bool = false
var _jump_requested: bool = false
var gravity: float = 9.8

func set_control_state(axis: Vector2, yaw_rad: float, wants_sprint: bool, wants_jump: bool = false) -> void:
    input_axis = axis
    camera_yaw_rad = yaw_rad
    sprinting = wants_sprint
    if wants_jump:
        _jump_requested = true

func _physics_process(delta: float) -> void:
    if _jump_requested:
        profile.request_jump()
        _jump_requested = false

    var grounded := is_on_floor()
    if grounded and velocity.y < 0.0:
        velocity.y = -0.05
    elif not grounded:
        velocity.y -= gravity * delta

    if profile.tick_jump_window(grounded, delta):
        velocity.y = profile.jump_velocity

    var target := profile.target_horizontal_velocity(input_axis, camera_yaw_rad, sprinting)
    velocity = profile.approach_horizontal(velocity, target, grounded, delta)
    move_and_slide()
