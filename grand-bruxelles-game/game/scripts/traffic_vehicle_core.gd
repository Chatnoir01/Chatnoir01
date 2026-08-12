extends CharacterBody3D

## Canonical traffic vehicle surface with no legacy core dependency.

@export var acceleration_mps2: float = 3.4
@export var braking_mps2: float = 7.5
@export_range(0.65, 1.05, 0.01) var speed_factor: float = 0.90

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
var _crossing_system: RefCounted = null

func configure_route_profile(
    new_route: PackedVector3Array,
    new_speed_limits_kmh: PackedFloat32Array,
    new_road_name: String,
    new_source_osm_id: int,
    new_route_edge_count: int,
    new_route_controls: Array = [],
    new_route_intersections: Array = []
) -> void:
    route_points = new_route.duplicate()
    route_speed_limits_kmh = new_speed_limits_kmh.duplicate()
    route_controls = new_route_controls.duplicate(true)
    route_intersections = new_route_intersections.duplicate(true)
    route_index = 1
    route_edge_count = maxi(1, new_route_edge_count)
    road_name = new_road_name
    source_osm_id = new_source_osm_id
    speed_mps = 0.0
    if not route_speed_limits_kmh.is_empty():
        speed_limit_mps = maxf(1.4, float(route_speed_limits_kmh[0]) / 3.6)
    elif route_points.size() > 1:
        speed_limit_mps = 30.0 / 3.6

func set_crossing_system(crossing_system: RefCounted) -> void:
    _crossing_system = crossing_system

func get_speed_kmh() -> float:
    return maxf(0.0, speed_mps * 3.6)

func get_speed_limit_kmh() -> float:
    return maxf(0.0, speed_limit_mps * 3.6)

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

func set_test_speed_kmh(speed_kmh: float) -> void:
    speed_mps = maxf(0.0, speed_kmh) / 3.6

func apply_speed_target(target_speed_mps: float, delta: float) -> float:
    var target := clampf(target_speed_mps, 0.0, speed_limit_mps * speed_factor)
    if target > speed_mps:
        speed_mps = move_toward(speed_mps, target, acceleration_mps2 * maxf(0.0, delta))
    else:
        speed_mps = move_toward(speed_mps, target, braking_mps2 * maxf(0.0, delta))
    return speed_mps
