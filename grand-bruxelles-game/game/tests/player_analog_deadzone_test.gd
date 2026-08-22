extends SceneTree

const PROFILE_SCRIPT := preload("res://game/scripts/player_locomotion_profile.gd")
const DEADZONE := 0.12
const EPSILON := 0.0001


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    print("PLAYER_ANALOG_DEADZONE_FAIL: %s" % message)
    quit(1)


func _expect_close(actual: float, expected: float, label: String) -> bool:
    if absf(actual - expected) > EPSILON:
        _fail("%s expected %.6f, got %.6f" % [label, expected, actual])
        return false
    return true


func _run() -> void:
    var profile = PROFILE_SCRIPT.new()

    var zero: Vector3 = profile.camera_relative_direction(Vector2.ZERO, 0.0)
    if not _expect_close(zero.length(), 0.0, "zero input"):
        return

    var below: Vector3 = profile.camera_relative_direction(Vector2(0.06, 0.0), 0.0)
    if not _expect_close(below.length(), 0.0, "input below deadzone"):
        return

    var edge: Vector3 = profile.camera_relative_direction(Vector2(DEADZONE, 0.0), 0.0)
    if not _expect_close(edge.length(), 0.0, "input at deadzone"):
        return

    var just_above_input := 0.13
    var just_above_expected := (just_above_input - DEADZONE) / (1.0 - DEADZONE)
    var just_above: Vector3 = profile.camera_relative_direction(Vector2(just_above_input, 0.0), 0.0)
    if not _expect_close(just_above.length(), just_above_expected, "input just above deadzone"):
        return

    var full: Vector3 = profile.camera_relative_direction(Vector2(1.0, 0.0), 0.0)
    if not _expect_close(full.length(), 1.0, "full analog input"):
        return

    var diagonal_input := Vector2(0.5, 0.5)
    var diagonal_expected_magnitude := (diagonal_input.length() - DEADZONE) / (1.0 - DEADZONE)
    var diagonal: Vector3 = profile.camera_relative_direction(diagonal_input, 0.0)
    if not _expect_close(diagonal.length(), diagonal_expected_magnitude, "diagonal magnitude"):
        return
    var expected_diagonal_direction := Vector3(diagonal_input.normalized().x, 0.0, diagonal_input.normalized().y)
    if diagonal.normalized().dot(expected_diagonal_direction) < 0.9999:
        _fail("radial remap changed diagonal direction")
        return

    var saturated: Vector3 = profile.camera_relative_direction(Vector2(2.0, 0.0), 0.0)
    if not _expect_close(saturated.length(), 1.0, "oversized input saturation"):
        return

    print("PLAYER_ANALOG_DEADZONE_GREEN: radial deadzone remap preserves direction and full-scale input")
    quit(0)
