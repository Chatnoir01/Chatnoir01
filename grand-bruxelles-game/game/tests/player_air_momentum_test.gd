extends SceneTree

const PROFILE := preload("res://game/scripts/player_locomotion_profile.gd")
const EPSILON := 0.001


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("PLAYER_AIR_MOMENTUM_FAIL: %s" % message)
    quit(1)


func _horizontal(velocity: Vector3) -> Vector2:
    return Vector2(velocity.x, velocity.z)


func _run() -> void:
    var profile := PROFILE.new()

    # Releasing movement in mid-air must not behave like an invisible brake.
    var airborne_before := Vector3(8.6, 2.5, -1.2)
    var airborne_after := profile.approach_horizontal(
        airborne_before,
        Vector3.ZERO,
        false,
        0.5
    )
    var airborne_delta := _horizontal(airborne_after).distance_to(_horizontal(airborne_before))
    if airborne_delta > EPSILON:
        _fail(
            "releasing input in air changed horizontal momentum by %.3f m/s: %s -> %s"
            % [airborne_delta, airborne_before, airborne_after]
        )
        return
    if absf(airborne_after.y - airborne_before.y) > EPSILON:
        _fail("horizontal shaping modified vertical velocity")
        return

    # Active air steering remains bounded by air_acceleration.
    var steer_dt := 0.1
    var steered := profile.approach_horizontal(
        Vector3.ZERO,
        Vector3(profile.sprint_speed, 0.0, 0.0),
        false,
        steer_dt
    )
    var expected_air_step := profile.air_acceleration * steer_dt
    if absf(_horizontal(steered).length() - expected_air_step) > EPSILON:
        _fail(
            "active air steering changed: expected %.3f m/s, got %.3f m/s"
            % [expected_air_step, _horizontal(steered).length()]
        )
        return

    # Ground release must keep the strong stop response.
    var ground_before := Vector3(profile.sprint_speed, 0.0, 0.0)
    var grounded_after := profile.approach_horizontal(
        ground_before,
        Vector3.ZERO,
        true,
        0.1
    )
    if _horizontal(grounded_after).length() >= _horizontal(ground_before).length():
        _fail("ground deceleration stopped working")
        return
    var expected_ground_speed := maxf(0.0, profile.sprint_speed - profile.ground_deceleration * 0.1)
    if absf(_horizontal(grounded_after).length() - expected_ground_speed) > EPSILON:
        _fail(
            "ground deceleration changed: expected %.3f m/s, got %.3f m/s"
            % [expected_ground_speed, _horizontal(grounded_after).length()]
        )
        return

    print(
        "PLAYER_AIR_MOMENTUM_OK: passive airborne momentum preserved; air steering and ground braking bounded"
    )
    quit(0)
