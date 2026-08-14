extends SceneTree

const PROFILE := preload("res://game/prototypes/player/player_locomotion_profile.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("PLAYER_LOCOMOTION_PROFILE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var profile := PROFILE.new()

    var diagonal := profile.camera_relative_direction(Vector2(1.0, 1.0), 0.0)
    if absf(diagonal.length() - 1.0) > 0.001:
        _fail("diagonal input is not normalized")
        return

    var forward_rotated := profile.camera_relative_direction(Vector2(0.0, -1.0), PI * 0.5)
    if forward_rotated.x > -0.95 or absf(forward_rotated.z) > 0.08:
        _fail("camera-relative movement rotation is wrong: %s" % forward_rotated)
        return

    var current := Vector3.ZERO
    var target := profile.target_horizontal_velocity(Vector2(0.0, -1.0), 0.0, true)
    current = profile.approach_horizontal(current, target, true, 1.0 / 60.0)
    if current.length() <= 0.0 or current.length() >= target.length():
        _fail("ground acceleration does not ramp smoothly")
        return

    var ground_after := profile.approach_horizontal(Vector3.ZERO, target, true, 0.1).length()
    var air_after := profile.approach_horizontal(Vector3.ZERO, target, false, 0.1).length()
    if air_after >= ground_after:
        _fail("air control should be weaker than ground acceleration")
        return

    profile.reset_jump_windows(true)
    profile.tick_jump_window(true, 0.016)
    profile.tick_jump_window(false, 0.05)
    profile.request_jump()
    if not profile.tick_jump_window(false, 0.01):
        _fail("coyote-time jump was rejected")
        return

    profile.reset_jump_windows(false)
    profile.request_jump()
    profile.tick_jump_window(false, 0.08)
    if not profile.tick_jump_window(true, 0.01):
        _fail("buffered jump did not fire on landing")
        return

    var sprint := profile.target_horizontal_velocity(Vector2(0.0, -1.0), 0.0, true).length()
    var walk := profile.target_horizontal_velocity(Vector2(0.0, -1.0), 0.0, false).length()
    if sprint <= walk:
        _fail("sprint speed is not above walk speed")
        return

    print("PLAYER_LOCOMOTION_PROFILE_OK: camera-relative movement, acceleration, air control, coyote time and jump buffer valid")
    quit(0)
