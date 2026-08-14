extends RefCounted

## Production locomotion profile extracted from the validated player prototype.
## The player controller keeps ownership of Brussels spawns, camera, mobile input
## and vehicle interaction; this class only owns movement shaping and jump windows.

var walk_speed: float = 5.4
var sprint_speed: float = 8.6
var ground_acceleration: float = 24.0
var ground_deceleration: float = 30.0
var air_acceleration: float = 7.5
var jump_velocity: float = 5.4
var coyote_time_s: float = 0.12
var jump_buffer_s: float = 0.14

var _time_since_grounded_s: float = 999.0
var _jump_buffer_remaining_s: float = 0.0


func camera_relative_direction(input_axis: Vector2, camera_yaw_rad: float) -> Vector3:
    var limited := input_axis.limit_length(1.0)
    var local := Vector3(limited.x, 0.0, limited.y)
    return local.rotated(Vector3.UP, camera_yaw_rad)


func target_horizontal_velocity(input_axis: Vector2, camera_yaw_rad: float, sprinting: bool) -> Vector3:
    var direction := camera_relative_direction(input_axis, camera_yaw_rad)
    var speed := sprint_speed if sprinting else walk_speed
    return direction * speed


func approach_horizontal(current: Vector3, target: Vector3, grounded: bool, dt: float) -> Vector3:
    var current_xz := Vector2(current.x, current.z)
    var target_xz := Vector2(target.x, target.z)
    var rate := air_acceleration
    if grounded:
        rate = ground_acceleration if target_xz.length_squared() > 0.0001 else ground_deceleration
    current_xz = current_xz.move_toward(target_xz, maxf(dt, 0.0) * rate)
    return Vector3(current_xz.x, current.y, current_xz.y)


func request_jump() -> void:
    _jump_buffer_remaining_s = jump_buffer_s


func tick_jump_window(grounded: bool, dt: float) -> bool:
    var step := maxf(dt, 0.0)
    if grounded:
        _time_since_grounded_s = 0.0
    else:
        _time_since_grounded_s += step
    _jump_buffer_remaining_s = maxf(0.0, _jump_buffer_remaining_s - step)

    if _jump_buffer_remaining_s > 0.0 and _time_since_grounded_s <= coyote_time_s:
        _jump_buffer_remaining_s = 0.0
        _time_since_grounded_s = coyote_time_s + 1.0
        return true
    return false


func reset_jump_windows(grounded: bool = true) -> void:
    _time_since_grounded_s = 0.0 if grounded else 999.0
    _jump_buffer_remaining_s = 0.0
