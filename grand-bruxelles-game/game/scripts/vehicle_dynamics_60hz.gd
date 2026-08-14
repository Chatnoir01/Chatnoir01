extends RefCounted

## Clean-room 60 Hz vehicle dynamics used by the playable A/B car experiment.
## Keeps the open world at 60 Hz while adding spring/damper suspension, drag,
## friction-limited lateral grip and speed-sensitive steering.

var mass_kg: float = 1450.0
var engine_force_n: float = 5500.0
var brake_force_n: float = 12500.0
var rolling_resistance_n: float = 210.0
var aero_drag_coefficient: float = 0.44
var cornering_stiffness_n_per_ms: float = 9200.0
var tire_friction_mu: float = 1.05
var spring_rate_n_per_m: float = 34000.0
var damper_rate_ns_per_m: float = 4200.0
var max_steer_angle_deg: float = 31.0


func longitudinal_step(speed_ms: float, throttle: float, brake: float, dt: float) -> float:
    var signed_throttle := clampf(throttle, -1.0, 1.0)
    var brake_input := clampf(brake, 0.0, 1.0)
    var drive_force := signed_throttle * engine_force_n
    var drag_force := aero_drag_coefficient * speed_ms * absf(speed_ms)
    var rolling_force := 0.0
    if absf(speed_ms) > 0.02:
        rolling_force = rolling_resistance_n * signf(speed_ms)
    var brake_force := 0.0
    if absf(speed_ms) > 0.02:
        brake_force = brake_force_n * brake_input * signf(speed_ms)
    var acceleration := (drive_force - drag_force - rolling_force - brake_force) / mass_kg
    var next_speed := speed_ms + acceleration * maxf(dt, 0.0)
    if brake_input > 0.0 and signf(next_speed) != signf(speed_ms):
        next_speed = 0.0
    return next_speed


func suspension_force(compression_m: float, compression_velocity_ms: float) -> float:
    var compression := maxf(compression_m, 0.0)
    return maxf(0.0, spring_rate_n_per_m * compression - damper_rate_ns_per_m * compression_velocity_ms)


func lateral_tire_force(lateral_speed_ms: float, normal_load_n: float) -> float:
    var desired := -lateral_speed_ms * cornering_stiffness_n_per_ms
    var limit := maxf(normal_load_n, 0.0) * tire_friction_mu
    return clampf(desired, -limit, limit)


func steer_angle_deg(input_axis: float, speed_ms: float) -> float:
    var speed_factor := lerpf(1.0, 0.38, clampf(absf(speed_ms) / 32.0, 0.0, 1.0))
    return clampf(input_axis, -1.0, 1.0) * max_steer_angle_deg * speed_factor


func static_wheel_load_n(wheel_count: int = 4) -> float:
    return mass_kg * 9.8 / maxf(float(wheel_count), 1.0)
