extends RigidBody3D
class_name GrandBruxellesVehicleDynamicsBody

const MODEL := preload("res://game/prototypes/vehicle/vehicle_dynamics_60hz.gd")

var dynamics := MODEL.new()
var throttle: float = 0.0
var brake: float = 0.0
var steering: float = 0.0

func _ready() -> void:
    mass = dynamics.mass_kg
    can_sleep = false
    continuous_cd = true
    contact_monitor = true
    max_contacts_reported = 8

func set_control_state(new_throttle: float, new_brake: float, new_steering: float) -> void:
    throttle = clampf(new_throttle, -1.0, 1.0)
    brake = clampf(new_brake, 0.0, 1.0)
    steering = clampf(new_steering, -1.0, 1.0)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
    var dt := state.step
    var basis := global_transform.basis.orthonormalized()
    var forward := -basis.z
    var right := basis.x
    var velocity_now := state.linear_velocity
    var forward_speed := velocity_now.dot(forward)

    # Longitudinal target comes from the deterministic 60 Hz model.
    var next_forward_speed := dynamics.longitudinal_step(forward_speed, throttle, brake, dt)
    velocity_now += forward * (next_forward_speed - forward_speed)

    # Friction-limited lateral damping approximates tire grip without forcing the
    # whole project to a higher physics tick rate.
    var lateral_speed := velocity_now.dot(right)
    var normal_load := dynamics.static_wheel_load_n(4) * 4.0
    var lateral_force := dynamics.lateral_tire_force(lateral_speed, normal_load)
    velocity_now += right * (lateral_force / dynamics.mass_kg) * dt
    state.linear_velocity = velocity_now

    var steer_deg := dynamics.steer_angle_deg(steering, next_forward_speed)
    var steer_response := clampf(absf(next_forward_speed) / 8.0, 0.0, 1.0)
    var target_yaw_rate := -deg_to_rad(steer_deg) * steer_response * 1.35
    state.angular_velocity.y = move_toward(state.angular_velocity.y, target_yaw_rate, dt * 4.5)

func forward_speed_ms() -> float:
    return linear_velocity.dot(-global_transform.basis.z.normalized())
