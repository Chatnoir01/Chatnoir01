extends CharacterBody3D

signal route_finished(vehicle: Node)

@export var acceleration_mps2: float = 3.4
@export var braking_mps2: float = 7.5
@export var emergency_braking_mps2: float = 12.0
@export var steering_response: float = 5.5
@export var waypoint_reach_distance_m: float = 2.4
@export var obstacle_lookahead_seconds: float = 1.8
@export var obstacle_min_lookahead_m: float = 7.0
@export var emergency_stop_distance_m: float = 3.2
@export_range(0.65, 1.05, 0.01) var speed_factor: float = 0.90

var route_points: PackedVector3Array = PackedVector3Array()
var route_speed_limits_kmh: PackedFloat32Array = PackedFloat32Array()
var route_controls: Array = []
var route_index: int = 1
var route_edge_count: int = 1
var speed_mps: float = 0.0
var speed_limit_mps: float = 8.333333
var road_name: String = ""
var source_osm_id: int = 0
var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var _control_system: RefCounted = null
var _handled_controls: Dictionary = {}
var _stop_hold_until_s: float = 0.0
var _finishing: bool = false

@onready var obstacle_ray: RayCast3D = get_node_or_null("ObstacleRay") as RayCast3D


func _ready() -> void:
    if obstacle_ray != null:
        obstacle_ray.enabled = true
        obstacle_ray.exclude_parent = true


func configure_route(
    new_route: PackedVector3Array,
    new_speed_limit_kmh: float,
    new_road_name: String,
    new_source_osm_id: int
) -> void:
    var profile := PackedFloat32Array()
    for _index: int in range(new_route.size()):
        profile.append(new_speed_limit_kmh)
    configure_route_profile(
        new_route,
        profile,
        new_road_name,
        new_source_osm_id,
        1
    )


func configure_route_profile(
    new_route: PackedVector3Array,
    new_speed_limits_kmh: PackedFloat32Array,
    new_road_name: String,
    new_source_osm_id: int,
    new_route_edge_count: int,
    new_route_controls: Array = [],
    new_control_system: RefCounted = null
) -> void:
    route_points = new_route.duplicate()
    route_speed_limits_kmh = new_speed_limits_kmh.duplicate()
    route_controls = new_route_controls.duplicate(true)
    route_index = 1
    route_edge_count = maxi(1, new_route_edge_count)
    speed_mps = 0.0
    road_name = new_road_name
    source_osm_id = new_source_osm_id
    _control_system = new_control_system
    _handled_controls.clear()
    _stop_hold_until_s = 0.0
    _finishing = false

    if route_points.size() < 2:
        _finish_route()
        return

    if route_speed_limits_kmh.size() != route_points.size():
        var fallback_limit := 30.0
        if not route_speed_limits_kmh.is_empty():
            fallback_limit = float(route_speed_limits_kmh[0])
        route_speed_limits_kmh.clear()
        for _index: int in range(route_points.size()):
            route_speed_limits_kmh.append(fallback_limit)

    speed_limit_mps = maxf(1.4, _speed_limit_at_index(route_index) / 3.6)
    global_position = route_points[0]
    var initial_direction := route_points[1] - route_points[0]
    initial_direction.y = 0.0
    if initial_direction.length_squared() > 0.001:
        initial_direction = initial_direction.normalized()
        rotation.y = _yaw_for_direction(initial_direction)
    set_physics_process(true)


func _physics_process(delta: float) -> void:
    if route_points.size() < 2 or route_index >= route_points.size():
        _finish_route()
        return

    if not is_on_floor():
        velocity.y -= gravity * delta
    else:
        velocity.y = -0.1

    var target := route_points[route_index]
    var to_target := target - global_position
    to_target.y = 0.0

    while to_target.length() <= waypoint_reach_distance_m:
        route_index += 1
        if route_index >= route_points.size():
            _finish_route()
            return
        target = route_points[route_index]
        to_target = target - global_position
        to_target.y = 0.0

    if to_target.length_squared() <= 0.001:
        return

    var desired_direction := to_target.normalized()
    var desired_yaw := _yaw_for_direction(desired_direction)
    rotation.y = lerp_angle(
        rotation.y,
        desired_yaw,
        clampf(steering_response * delta, 0.0, 1.0)
    )

    speed_limit_mps = maxf(1.4, _speed_limit_at_index(route_index) / 3.6)
    var desired_speed := speed_limit_mps * speed_factor
    var deceleration := braking_mps2

    desired_speed = minf(desired_speed, _traffic_control_speed_cap(desired_speed))

    if obstacle_ray != null:
        var lookahead := maxf(
            obstacle_min_lookahead_m,
            speed_mps * obstacle_lookahead_seconds + 3.0
        )
        obstacle_ray.target_position = Vector3(0.0, 0.0, -lookahead)
        obstacle_ray.force_raycast_update()
        if obstacle_ray.is_colliding():
            var obstacle_distance := global_position.distance_to(obstacle_ray.get_collision_point())
            var usable_distance := maxf(0.01, lookahead - emergency_stop_distance_m)
            var clearance_ratio := clampf(
                (obstacle_distance - emergency_stop_distance_m) / usable_distance,
                0.0,
                1.0
            )
            desired_speed *= clearance_ratio
            if obstacle_distance <= maxf(emergency_stop_distance_m, speed_mps * 0.8):
                deceleration = emergency_braking_mps2

    if desired_speed > speed_mps:
        speed_mps = move_toward(speed_mps, desired_speed, acceleration_mps2 * delta)
    else:
        speed_mps = move_toward(speed_mps, desired_speed, deceleration * delta)

    var forward := -global_transform.basis.z
    forward.y = 0.0
    forward = forward.normalized()
    velocity.x = forward.x * speed_mps
    velocity.z = forward.z * speed_mps
    move_and_slide()

    if is_on_wall():
        speed_mps = move_toward(speed_mps, 0.0, emergency_braking_mps2 * delta)


func _traffic_control_speed_cap(base_speed: float) -> float:
    if route_controls.is_empty():
        return base_speed

    var cap := base_speed
    var now_seconds := float(Time.get_ticks_msec()) / 1000.0
    if now_seconds < _stop_hold_until_s:
        return 0.0

    for control_variant: Variant in route_controls:
        if typeof(control_variant) != TYPE_DICTIONARY:
            continue
        var control: Dictionary = control_variant
        var control_route_index := int(control.get("route_index", -1))
        if control_route_index < route_index - 1 or control_route_index > route_index + 3:
            continue

        var control_position: Vector3 = control.get("route_position", Vector3.ZERO)
        var distance := global_position.distance_to(control_position)
        if distance > 32.0:
            continue

        var kind := str(control.get("kind", ""))
        var control_id := int(control.get("osm_id", 0))

        if kind == "traffic_signals" and _control_system != null:
            var approach: Vector3 = control.get("approach_direction", Vector3.ZERO)
            var state := str(_control_system.call("signal_state_for", control, approach))
            if state == "red":
                cap = minf(cap, _safe_approach_speed(distance, 2.6))
            elif state == "amber":
                var stopping_distance := speed_mps * speed_mps / maxf(0.1, 2.0 * braking_mps2) + 1.8
                if distance >= stopping_distance:
                    cap = minf(cap, _safe_approach_speed(distance, 2.6))

        elif kind == "give_way":
            if distance <= 18.0:
                cap = minf(cap, 3.0)
            if distance <= 6.0:
                cap = minf(cap, 1.5)

        elif kind == "crossing":
            if distance <= 16.0:
                cap = minf(cap, 5.56)

        elif kind == "stop" and not _handled_controls.has(control_id):
            cap = minf(cap, _safe_approach_speed(distance, 2.2))
            if distance <= 2.8 and speed_mps <= 0.45:
                _handled_controls[control_id] = true
                _stop_hold_until_s = now_seconds + 0.8
                cap = 0.0

    return cap


func _safe_approach_speed(distance: float, stop_margin_m: float) -> float:
    var usable_distance := maxf(0.0, distance - stop_margin_m)
    if usable_distance <= 0.01:
        return 0.0
    return sqrt(2.0 * braking_mps2 * usable_distance) * 0.82


func _speed_limit_at_index(index: int) -> float:
    if route_speed_limits_kmh.is_empty():
        return speed_limit_mps * 3.6
    var safe_index := clampi(index, 0, route_speed_limits_kmh.size() - 1)
    return maxf(5.0, float(route_speed_limits_kmh[safe_index]))


func _yaw_for_direction(direction: Vector3) -> float:
    return atan2(-direction.x, -direction.z)


func _finish_route() -> void:
    if _finishing:
        return
    _finishing = true
    speed_mps = 0.0
    velocity = Vector3.ZERO
    set_physics_process(false)
    route_finished.emit(self)


func get_speed_kmh() -> float:
    return speed_mps * 3.6


func get_speed_limit_kmh() -> float:
    return speed_limit_mps * 3.6


func get_road_name() -> String:
    return road_name


func get_source_osm_id() -> int:
    return source_osm_id


func get_route_point_count() -> int:
    return route_points.size()


func get_route_edge_count() -> int:
    return route_edge_count


func get_route_control_count() -> int:
    return route_controls.size()
