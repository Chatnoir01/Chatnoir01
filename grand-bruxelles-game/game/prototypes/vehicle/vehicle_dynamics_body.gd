extends RigidBody3D
class_name GrandBruxellesVehicleDynamicsBody

const MODEL := preload("res://game/prototypes/vehicle/vehicle_dynamics_60hz.gd")

const WHEEL_OFFSETS: Array[Vector3] = [
    Vector3(-0.72, 0.0, -1.35),
    Vector3(0.72, 0.0, -1.35),
    Vector3(-0.72, 0.0, 1.35),
    Vector3(0.72, 0.0, 1.35),
]

var dynamics := MODEL.new()
var throttle: float = 0.0
var brake: float = 0.0
var steering: float = 0.0
var suspension_rest_length_m: float = 0.85
var suspension_ray_length_m: float = 1.15
var _suspension_rays: Array[RayCast3D] = []

func _ready() -> void:
    mass = dynamics.mass_kg
    can_sleep = false
    continuous_cd = true
    contact_monitor = true
    max_contacts_reported = 8
    # The first prototype keeps roll/pitch locked so we can validate the 60 Hz
    # spring/tire/drivetrain stack independently. Production tuning can unlock
    # these axes once wheel placement and center of mass use real car geometry.
    axis_lock_angular_x = true
    axis_lock_angular_z = true
    _ensure_suspension_rays()

func _ensure_suspension_rays() -> void:
    if not _suspension_rays.is_empty():
        return
    for index: int in range(WHEEL_OFFSETS.size()):
        var ray := RayCast3D.new()
        ray.name = "SuspensionRay%d" % index
        ray.position = WHEEL_OFFSETS[index]
        ray.target_position = Vector3(0.0, -suspension_ray_length_m, 0.0)
        ray.enabled = true
        ray.exclude_parent = true
        add_child(ray)
        _suspension_rays.append(ray)

func set_control_state(new_throttle: float, new_brake: float, new_steering: float) -> void:
    throttle = clampf(new_throttle, -1.0, 1.0)
    brake = clampf(new_brake, 0.0, 1.0)
    steering = clampf(new_steering, -1.0, 1.0)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
    var dt := maxf(state.step, 0.0001)
    var basis := global_transform.basis.orthonormalized()
    var up := basis.y.normalized()
    var forward := -basis.z.normalized()
    var right := basis.x.normalized()

    # Four raycast springs hold the chassis above the road. The old runtime
    # prototype rested the bare box collider on the floor, so chassis friction
    # cancelled nearly all drivetrain motion even though the deterministic
    # engine model was correct.
    var supported_wheels := 0
    var suspension_force_total := 0.0
    var vertical_speed := state.linear_velocity.dot(up)
    for ray: RayCast3D in _suspension_rays:
        ray.force_raycast_update()
        if not ray.is_colliding():
            continue
        var distance_m := ray.global_position.distance_to(ray.get_collision_point())
        if distance_m > suspension_rest_length_m:
            continue
        var compression_m := suspension_rest_length_m - distance_m
        suspension_force_total += dynamics.suspension_force(compression_m, vertical_speed)
        supported_wheels += 1
    if supported_wheels > 0 and suspension_force_total > 0.0:
        state.apply_central_force(up * suspension_force_total)

    var velocity_now := state.linear_velocity
    var forward_speed := velocity_now.dot(forward)
    var next_forward_speed := dynamics.longitudinal_step(forward_speed, throttle, brake, dt)
    var longitudinal_acceleration := (next_forward_speed - forward_speed) / dt
    state.apply_central_force(forward * longitudinal_acceleration * dynamics.mass_kg)

    # Friction-limited lateral tire force removes sideways sliding without using
    # the chassis/floor contact as fake tire grip.
    var lateral_speed := velocity_now.dot(right)
    var normal_load := dynamics.static_wheel_load_n(4) * maxf(float(supported_wheels), 1.0)
    var lateral_force := dynamics.lateral_tire_force(lateral_speed, normal_load)
    state.apply_central_force(right * lateral_force)

    var steer_deg := dynamics.steer_angle_deg(steering, next_forward_speed)
    var steer_response := clampf(absf(next_forward_speed) / 8.0, 0.0, 1.0)
    var target_yaw_rate := -deg_to_rad(steer_deg) * steer_response * 1.35
    state.angular_velocity.y = move_toward(state.angular_velocity.y, target_yaw_rate, dt * 4.5)

func forward_speed_ms() -> float:
    return linear_velocity.dot(-global_transform.basis.z.normalized())

func supported_wheel_count() -> int:
    var count := 0
    for ray: RayCast3D in _suspension_rays:
        ray.force_raycast_update()
        if ray.is_colliding() and ray.global_position.distance_to(ray.get_collision_point()) <= suspension_rest_length_m:
            count += 1
    return count
