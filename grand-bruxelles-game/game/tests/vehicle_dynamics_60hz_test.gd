extends SceneTree

const MODEL := preload("res://game/prototypes/vehicle/vehicle_dynamics_60hz.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("VEHICLE_DYNAMICS_60HZ_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var hz := int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60))
    if hz != 60:
        _fail("prototype assumes production 60 Hz, got %d" % hz)
        return

    var model := MODEL.new()
    if model.recommended_physics_hz() != 60:
        _fail("model requested a global physics-rate increase")
        return

    var dt := 1.0 / 60.0
    var speed := 0.0
    for _i: int in range(600):
        speed = model.longitudinal_step(speed, 1.0, 0.0, dt)
    if speed < 18.0 or speed > 42.0:
        _fail("10 s full-throttle speed implausible: %.3f m/s" % speed)
        return

    var pre_brake := speed
    for _i: int in range(180):
        speed = model.longitudinal_step(speed, 0.0, 1.0, dt)
    if speed > 0.35:
        _fail("3 s braking failed to stop vehicle: %.3f m/s" % speed)
        return
    if pre_brake <= speed:
        _fail("braking did not reduce speed")
        return

    var wheel_load := model.static_wheel_load_n()
    var lateral := model.lateral_tire_force(4.0, wheel_load)
    var friction_limit := wheel_load * model.tire_friction_mu
    if absf(lateral) > friction_limit + 0.01:
        _fail("lateral tire force exceeded friction circle proxy")
        return

    var low_speed_steer := absf(model.steer_angle_deg(1.0, 3.0))
    var high_speed_steer := absf(model.steer_angle_deg(1.0, 30.0))
    if high_speed_steer >= low_speed_steer:
        _fail("high-speed steering was not reduced")
        return

    var static_compression := wheel_load / model.spring_rate_n_per_m
    var support_force := model.suspension_force(static_compression, 0.0)
    if absf(support_force - wheel_load) > wheel_load * 0.02:
        _fail("spring equilibrium drifted: force=%.3f load=%.3f" % [support_force, wheel_load])
        return

    print("VEHICLE_DYNAMICS_60HZ_OK: production_hz=60 speed10s=%.2fms brake3s=%.2fms steer_low=%.2f steer_high=%.2f" % [pre_brake, speed, low_speed_steer, high_speed_steer])
    quit(0)
