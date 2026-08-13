extends CharacterBody3D
class_name TrafficVehicleCore

signal route_finished(vehicle: Node)
signal traffic_disabled(vehicle: Node)

@export var acceleration_mps2: float = 3.4
@export var braking_mps2: float = 7.5
@export var emergency_braking_mps2: float = 12.0
@export var steering_response: float = 5.5
@export var waypoint_reach_distance_m: float = 2.4
@export var obstacle_lookahead_seconds: float = 1.8
@export var obstacle_min_lookahead_m: float = 7.0
@export var emergency_stop_distance_m: float = 3.2
@export_range(0.65, 1.05, 0.01) var speed_factor: float = 0.90
@export var traffic_impact_cooldown_ms: int = 450
@export_range(0.1, 1.0, 0.05) var transmitted_impact_factor: float = 0.78

const DAMAGE_MODEL_SCRIPT := preload("res://game/scripts/vehicle_damage_model.gd")

var route_points: PackedVector3Array = PackedVector3Array()
var route_speed_limits_kmh: PackedFloat32Array = PackedFloat32Array()
var route_controls: Array = []
var route_intersections: Array = []
var route_index: int = 1
var route_edge_count: int = 1
var speed_mps: float = 0.0
var speed_limit_mps: float = 8.333333
var road_name: String = ""
var source_osm_id: int = 0
var traffic_archetype: String = "car"
var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var _control_system: RefCounted = null
var _intersection_system: RefCounted = null
var _crossing_system: RefCounted = null
var _handled_controls: Dictionary = {}
var _finishing: bool = false
var _traffic_damage_model: RefCounted = null
var _traffic_next_impact_ms: int = 0
var _traffic_disabled_emitted: bool = false

@onready var obstacle_ray: RayCast3D = get_node_or_null("ObstacleRay") as RayCast3D

func _ready() -> void:
    _traffic_damage_model = DAMAGE_MODEL_SCRIPT.new()
    if obstacle_ray != null:
        obstacle_ray.enabled = true
        obstacle_ray.exclude_parent = true

func configure_archetype(archetype: String) -> void:
    traffic_archetype = archetype
    match traffic_archetype:
        "scooter":
            acceleration_mps2 = 4.1
            braking_mps2 = 8.2
            emergency_braking_mps2 = 12.5
            steering_response = 7.0
            speed_factor = 0.88
            obstacle_min_lookahead_m = 5.5
        "motorcycle":
            acceleration_mps2 = 4.8
            braking_mps2 = 8.8
            emergency_braking_mps2 = 13.0
            steering_response = 7.5
            speed_factor = 0.94
            obstacle_min_lookahead_m = 6.0
        _:
            traffic_archetype = "car"
            acceleration_mps2 = 3.4
            braking_mps2 = 7.5
            emergency_braking_mps2 = 12.0
            steering_response = 5.5
            speed_factor = 0.90
            obstacle_min_lookahead_m = 7.0

func get_traffic_archetype() -> String:
    return traffic_archetype

func set_crossing_system(crossing_system: RefCounted) -> void:
    _crossing_system = crossing_system

func configure_route(
    new_route: PackedVector3Array,
    new_speed_limit_kmh: float,
    new_road_name: String,
    new_source_osm_id: int
) -> void:
    var profile := PackedFloat32Array()
    for _index: int in range(new_route.size()):
        profile.append(new_speed_limit_kmh)
    configure_route_profile(new_route, profile, new_road_name, new_source_osm_id, 1)

func configure_route_profile(
    new_route: PackedVector3Array,
    new_speed_limits_kmh: PackedFloat32Array,
    new_road_name: String,
    new_source_osm_id: int,
    new_route_edge_count: int,
    new_route_controls: Array = [],
    new_control_system: RefCounted = null,
    new_route_intersections: Array = [],
    new_intersection_system: RefCounted = null
) -> void:
    route_points = new_route.duplicate()
    route_speed_limits_kmh = new_speed_limits_kmh.duplicate()
    route_controls = new_route_controls.duplicate(true)
    route_intersections = new_route_intersections.duplicate(true)
    route_index = 1
    route_edge_count = maxi(1, new_route_edge_count)
    speed_mps = 0.0
    road_name = new_road_name
    source_osm_id = new_source_osm_id
    _control_system = new_control_system
    _intersection_system = new_intersection_system
    _handled_controls.clear()
    _finishing = false
    _traffic_disabled_emitted = false

    if route_points.size() < 2:
        _finish_route()
        return

    if route_speed_limits_kmh.size() != route_points.size():
        var fallback_limit: float = 30.0
        if not route_speed_limits_kmh.is_empty():
            fallback_limit = float(route_speed_limits_kmh[0])
        route_speed_limits_kmh.clear()
        for _index: int in range(route_points.size()):
            route_speed_limits_kmh.append(fallback_limit)

    speed_limit_mps = maxf(1.4, _speed_limit_at_index(route_index) / 3.6)
    global_position = route_points[0]
    var initial_direction: Vector3 = route_points[1] - route_points[0]
    initial_direction.y = 0.0
    if initial_direction.length_squared() > 0.001:
        initial_direction = initial_direction.normalized()
        rotation.y = _yaw_for_direction(initial_direction)
    set_physics_process(true)

func _physics_process(delta: float) -> void:
    if is_traffic_disabled():
        speed_mps = 0.0
        velocity.x = 0.0
        velocity.z = 0.0
        if not is_on_floor():
            velocity.y -= gravity * delta
        else:
            velocity.y = -0.1
        move_and_slide()
        return

    var impact_speed_kmh: float = speed_mps * 3.6
    var pre_move_forward: Vector3 = -global_transform.basis.z
    pre_move_forward.y = 0.0
    if pre_move_forward.length_squared() > 0.001:
        pre_move_forward = pre_move_forward.normalized()

    _advance_route_motion(delta)

    if is_on_wall() and impact_speed_kmh > 0.0:
        _register_traffic_collision(impact_speed_kmh, pre_move_forward)

func _advance_route_motion(delta: float) -> void:
    if route_points.size() < 2 or route_index >= route_points.size():
        _finish_route()
        return
    if not is_on_floor():
        velocity.y -= gravity * delta
    else:
        velocity.y = -0.1

    var target: Vector3 = route_points[route_index]
    var to_target: Vector3 = target - global_position
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

    var desired_direction: Vector3 = to_target.normalized()
    var desired_yaw: float = _yaw_for_direction(desired_direction)
    rotation.y = lerp_angle(rotation.y, desired_yaw, clampf(steering_response * delta, 0.0, 1.0))
    speed_limit_mps = maxf(1.4, _speed_limit_at_index(route_index) / 3.6)
    var desired_speed: float = speed_limit_mps * speed_factor
    var deceleration: float = braking_mps2
    desired_speed = minf(desired_speed, _traffic_control_speed_cap(desired_speed))
    desired_speed = minf(desired_speed, _intersection_speed_cap(desired_speed))

    if obstacle_ray != null:
        var lookahead: float = maxf(obstacle_min_lookahead_m, speed_mps * obstacle_lookahead_seconds + 3.0)
        obstacle_ray.target_position = Vector3(0.0, 0.0, -lookahead)
        obstacle_ray.force_raycast_update()
        if obstacle_ray.is_colliding():
            var obstacle_distance: float = global_position.distance_to(obstacle_ray.get_collision_point())
            var usable_distance: float = maxf(0.01, lookahead - emergency_stop_distance_m)
            var clearance_ratio: float = clampf((obstacle_distance - emergency_stop_distance_m) / usable_distance, 0.0, 1.0)
            desired_speed *= clearance_ratio
            if obstacle_distance <= maxf(emergency_stop_distance_m, speed_mps * 0.8):
                deceleration = emergency_braking_mps2

    if desired_speed > speed_mps:
        speed_mps = move_toward(speed_mps, desired_speed, acceleration_mps2 * delta)
    else:
        speed_mps = move_toward(speed_mps, desired_speed, deceleration * delta)

    var forward: Vector3 = -global_transform.basis.z
    forward.y = 0.0
    if forward.length_squared() > 0.001:
        forward = forward.normalized()
    velocity.x = forward.x * speed_mps
    velocity.z = forward.z * speed_mps
    move_and_slide()
    if is_on_wall():
        speed_mps = move_toward(speed_mps, 0.0, emergency_braking_mps2 * delta)

func _traffic_control_speed_cap(base_speed: float) -> float:
    if route_controls.is_empty():
        return base_speed
    var cap: float = base_speed
    for control_variant: Variant in route_controls:
        if typeof(control_variant) != TYPE_DICTIONARY:
            continue
        var control: Dictionary = control_variant
        var control_route_index: int = int(control.get("route_index", -1))
        if control_route_index < route_index - 1 or control_route_index > route_index + 3:
            continue
        var control_position: Vector3 = control.get("route_position", Vector3.ZERO)
        var distance: float = global_position.distance_to(control_position)
        if distance > 32.0:
            continue
        var kind: String = str(control.get("kind", ""))
        var control_id: int = int(control.get("osm_id", 0))
        if kind == "traffic_signals" and _control_system != null:
            var approach: Vector3 = control.get("approach_direction", Vector3.ZERO)
            var state: String = str(_control_system.call("signal_state_for", control, approach))
            if state == "red":
                cap = minf(cap, _safe_approach_speed(distance, 2.6))
            elif state == "amber":
                var stopping_distance: float = speed_mps * speed_mps / maxf(0.1, 2.0 * braking_mps2) + 1.8
                if distance >= stopping_distance:
                    cap = minf(cap, _safe_approach_speed(distance, 2.6))
        elif kind == "give_way":
            if distance <= 18.0:
                cap = minf(cap, 3.0)
            if distance <= 6.0:
                cap = minf(cap, 1.5)
        elif kind == "crossing":
            var occupied: bool = false
            if _crossing_system != null and control_id > 0:
                occupied = bool(_crossing_system.call("crossing_requires_stop", control_id))
            if occupied:
                cap = minf(cap, _safe_approach_speed(distance, 2.8))
                if distance <= 3.0:
                    cap = 0.0
        elif kind == "stop" and not _handled_controls.has(control_id):
            cap = minf(cap, _safe_approach_speed(distance, 2.2))
            if distance <= 2.8 and speed_mps <= 0.45:
                _handled_controls[control_id] = true
                cap = 0.0
    return cap

func _intersection_speed_cap(base_speed: float) -> float:
    if _intersection_system == null or route_intersections.is_empty():
        return base_speed
    var cap: float = base_speed
    for raw_intersection: Variant in route_intersections:
        if typeof(raw_intersection) != TYPE_DICTIONARY:
            continue
        var intersection: Dictionary = raw_intersection
        var mapped_index: int = int(intersection.get("route_index", -1))
        if mapped_index < route_index - 1 or mapped_index > route_index + 3:
            continue
        var position: Vector3 = intersection.get("route_position", Vector3.ZERO)
        var distance: float = global_position.distance_to(position)
        if distance > 29.0:
            continue
        var intersection_id: int = int(intersection.get("id", -1))
        var approach: Vector3 = intersection.get("approach_direction", Vector3.ZERO)
        var control_kind: String = str(intersection.get("control_kind", ""))
        var allowed: bool = true
        var yielding_approach: bool = false
        if bool(intersection.get("priority_to_right", false)):
            allowed = bool(_intersection_system.call("request_passage", intersection_id, get_instance_id(), approach, distance))
        elif control_kind == "give_way":
            yielding_approach = _has_route_control_near("give_way", position, 12.0)
            allowed = bool(_intersection_system.call("request_controlled_passage", intersection_id, get_instance_id(), approach, distance, yielding_approach))
        else:
            continue
        if not allowed:
            cap = minf(cap, _safe_approach_speed(distance, 2.7))
            if distance <= 3.0:
                cap = 0.0
        elif yielding_approach and distance <= 12.0:
            cap = minf(cap, 4.17)
        elif distance <= 14.0:
            cap = minf(cap, 6.94)
    return cap

func _has_route_control_near(kind: String, position: Vector3, radius_m: float) -> bool:
    for raw_control: Variant in route_controls:
        if typeof(raw_control) != TYPE_DICTIONARY:
            continue
        var control: Dictionary = raw_control
        if str(control.get("kind", "")) != kind:
            continue
        var control_position: Vector3 = control.get("route_position", Vector3.ZERO)
        if control_position.distance_to(position) <= radius_m:
            return true
    return false

func _safe_approach_speed(distance: float, stop_margin_m: float) -> float:
    var usable_distance: float = maxf(0.0, distance - stop_margin_m)
    if usable_distance <= 0.01:
        return 0.0
    return sqrt(2.0 * braking_mps2 * usable_distance) * 0.82

func _speed_limit_at_index(index: int) -> float:
    if route_speed_limits_kmh.is_empty():
        return speed_limit_mps * 3.6
    var safe_index: int = clampi(index, 0, route_speed_limits_kmh.size() - 1)
    return maxf(5.0, float(route_speed_limits_kmh[safe_index]))

func _yaw_for_direction(direction: Vector3) -> float:
    return atan2(-direction.x, -direction.z)

func _finish_route() -> void:
    if _finishing:
        return
    _finishing = true
    if _intersection_system != null:
        _intersection_system.call("release_vehicle", get_instance_id())
    speed_mps = 0.0
    velocity = Vector3.ZERO
    set_physics_process(false)
    route_finished.emit(self)

func _register_traffic_collision(impact_speed_kmh: float, forward_direction: Vector3) -> void:
    if _traffic_damage_model == null or Time.get_ticks_msec() < _traffic_next_impact_ms:
        return
    var alignment: float = 0.42
    for index: int in range(get_slide_collision_count()):
        var collision: KinematicCollision3D = get_slide_collision(index)
        if collision == null:
            continue
        var normal: Vector3 = collision.get_normal()
        if absf(normal.y) > 0.65:
            continue
        normal.y = 0.0
        if normal.length_squared() <= 0.001:
            continue
        normal = normal.normalized()
        if forward_direction.length_squared() > 0.001:
            alignment = maxf(alignment, absf(forward_direction.dot(normal)))
    _traffic_damage_model.call("register_impact", impact_speed_kmh, alignment)
    _traffic_next_impact_ms = Time.get_ticks_msec() + traffic_impact_cooldown_ms
    _apply_damage_performance()
    _emit_disabled_if_needed()
    _transmit_collision_damage(impact_speed_kmh, alignment)

func _transmit_collision_damage(impact_speed_kmh: float, alignment: float) -> void:
    var seen: Dictionary = {}
    for index: int in range(get_slide_collision_count()):
        var collision: KinematicCollision3D = get_slide_collision(index)
        if collision == null:
            continue
        var collider: Object = collision.get_collider()
        if collider == null or collider == self:
            continue
        var collider_id: int = collider.get_instance_id()
        if seen.has(collider_id):
            continue
        seen[collider_id] = true
        _transmit_impact_to_collider(collider, impact_speed_kmh * transmitted_impact_factor, alignment)

func _transmit_impact_to_collider(collider: Object, speed_kmh: float, alignment: float) -> bool:
    if collider == null or collider == self:
        return false
    if collider.has_method("apply_external_impact"):
        collider.call("apply_external_impact", speed_kmh, alignment)
        return true
    if collider.has_method("apply_external_vehicle_impact"):
        collider.call("apply_external_vehicle_impact", speed_kmh, alignment)
        return true
    return false

func apply_external_impact(speed_kmh: float, alignment: float = 1.0) -> Dictionary:
    if _traffic_damage_model == null:
        _traffic_damage_model = DAMAGE_MODEL_SCRIPT.new()
    if Time.get_ticks_msec() < _traffic_next_impact_ms:
        return {"ignored_cooldown": true, "health": get_traffic_vehicle_health()}
    var result: Dictionary = _traffic_damage_model.call("register_impact", speed_kmh, alignment)
    _traffic_next_impact_ms = Time.get_ticks_msec() + traffic_impact_cooldown_ms
    _apply_damage_performance()
    _emit_disabled_if_needed()
    return result

func _apply_damage_performance() -> void:
    if _traffic_damage_model == null:
        return
    var performance: float = float(_traffic_damage_model.call("get_performance_factor"))
    if performance <= 0.0:
        speed_mps = 0.0
        return
    speed_mps = minf(speed_mps, speed_limit_mps * speed_factor * performance)

func _emit_disabled_if_needed() -> void:
    if not is_traffic_disabled() or _traffic_disabled_emitted:
        return
    _traffic_disabled_emitted = true
    speed_mps = 0.0
    velocity = Vector3.ZERO
    set_meta("traffic_wrecked", true)
    set_meta("traffic_wrecked_at_s", float(Time.get_ticks_msec()) / 1000.0)
    if _intersection_system != null:
        _intersection_system.call("release_vehicle", get_instance_id())
    traffic_disabled.emit(self)

func apply_traffic_test_impact(speed_kmh: float, alignment: float = 1.0) -> Dictionary:
    if _traffic_damage_model == null:
        _traffic_damage_model = DAMAGE_MODEL_SCRIPT.new()
    var result: Dictionary = _traffic_damage_model.call("register_impact", speed_kmh, alignment)
    _apply_damage_performance()
    _emit_disabled_if_needed()
    return result

func get_traffic_vehicle_health() -> float:
    if _traffic_damage_model == null:
        return 100.0
    return float(_traffic_damage_model.call("get_health"))

func get_traffic_vehicle_performance_factor() -> float:
    if _traffic_damage_model == null:
        return 1.0
    return float(_traffic_damage_model.call("get_performance_factor"))

func is_traffic_disabled() -> bool:
    if _traffic_damage_model == null:
        return false
    return bool(_traffic_damage_model.call("is_disabled"))

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

func get_route_intersection_count() -> int:
    return route_intersections.size()
