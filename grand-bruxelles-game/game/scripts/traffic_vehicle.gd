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
var route_index: int = 1
var speed_mps: float = 0.0
var speed_limit_mps: float = 8.333333
var road_name: String = ""
var source_osm_id: int = 0
var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
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
    route_points = new_route.duplicate()
    route_index = 1
    speed_mps = 0.0
    speed_limit_mps = maxf(1.4, new_speed_limit_kmh / 3.6)
    road_name = new_road_name
    source_osm_id = new_source_osm_id
    _finishing = false

    if route_points.size() < 2:
        _finish_route()
        return

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

    var desired_speed := speed_limit_mps * speed_factor
    var deceleration := braking_mps2

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
