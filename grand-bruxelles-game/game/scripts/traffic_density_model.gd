extends RefCounted

const LOCAL_RADIUS_M := 150.0
const OFFICIAL_PROFILE_SCRIPT := preload("res://game/scripts/traffic_official_density_profile.gd")
const DEFAULT_OFFICIAL_RADIUS_M := 2000.0
const DEFAULT_OFFICIAL_BLEND_WEIGHT := 0.72
const MIN_SPATIAL_FACTOR := 0.58
const MAX_SPATIAL_FACTOR := 1.42

var _official_profile: RefCounted = OFFICIAL_PROFILE_SCRIPT.new()
var _official_radius_m: float = DEFAULT_OFFICIAL_RADIUS_M
var _official_blend_weight: float = DEFAULT_OFFICIAL_BLEND_WEIGHT

func time_factor(_hour: float) -> float:
    # No authoritative corridor/time traffic-volume series is wired into production yet.
    # Keep temporal shaping neutral rather than manufacturing a Brussels daily profile.
    return 1.0

func configure_official_snapshot(
    snapshot: Dictionary,
    max_radius_m: float = DEFAULT_OFFICIAL_RADIUS_M,
    blend_weight: float = DEFAULT_OFFICIAL_BLEND_WEIGHT
) -> bool:
    _official_radius_m = maxf(1.0, max_radius_m)
    _official_blend_weight = clampf(blend_weight, 0.0, 1.0)
    return bool(_official_profile.call("configure", snapshot))

func clear_official_snapshot() -> void:
    _official_profile.call("clear")

func has_official_calibration() -> bool:
    return bool(_official_profile.call("is_configured"))

func get_official_sensor_count() -> int:
    return int(_official_profile.call("get_sensor_count"))

func get_official_capture_timestamp() -> String:
    return str(_official_profile.call("get_captured_at_utc"))

func official_calibration_for(position: Vector3) -> Dictionary:
    return _official_profile.call("calibration_for", position, _official_radius_m)

func nearest_official_sample(position: Vector3) -> Dictionary:
    return _official_profile.call("nearest_sample", position)

func local_capacity_factor(roads: Array[Dictionary], position: Vector3) -> float:
    var weighted_sum := 0.0
    var samples := 0
    for road: Dictionary in roads:
        var points: Array = road.get("points", [])
        if points.size() < 2:
            continue
        if _road_distance_to_point(points, position) > LOCAL_RADIUS_M:
            continue
        var road_class := str(road.get("class", ""))
        var class_weight := 0.72
        if road_class in ["motorway", "trunk", "primary"]:
            class_weight = 1.18
        elif road_class == "secondary":
            class_weight = 1.08
        elif road_class == "tertiary":
            class_weight = 0.96
        elif road_class in ["residential", "unclassified"]:
            class_weight = 0.78
        elif road_class in ["service", "living_street"]:
            class_weight = 0.58
        var lanes := _safe_int(road.get("lanes", null))
        var lane_factor := 1.0
        if lanes >= 4:
            lane_factor = 1.12
        elif lanes >= 2:
            lane_factor = 1.05
        weighted_sum += class_weight * lane_factor
        samples += 1
    if samples == 0:
        return 0.85
    return clampf(weighted_sum / float(samples), 0.62, 1.15)

func spatial_factor(roads: Array[Dictionary], position: Vector3) -> float:
    var heuristic := local_capacity_factor(roads, position)
    if not has_official_calibration() or _official_blend_weight <= 0.0:
        return heuristic
    var calibration := official_calibration_for(position)
    if not bool(calibration.get("available", false)):
        return heuristic
    var official := float(calibration.get("factor", 1.0))
    var distance_confidence := clampf(float(calibration.get("distance_confidence", 0.0)), 0.0, 1.0)
    var effective_blend := _official_blend_weight * distance_confidence
    return clampf(lerpf(heuristic, official, effective_blend), MIN_SPATIAL_FACTOR, MAX_SPATIAL_FACTOR)

func density_factor(hour: float, roads: Array[Dictionary], position: Vector3) -> float:
    return time_factor(hour) * spatial_factor(roads, position)

func target_vehicle_count(base_max: int, hour: float, roads: Array[Dictionary], position: Vector3) -> int:
    if base_max <= 0:
        return 0
    var factor := density_factor(hour, roads, position)
    # base_max is the neutral fleet size, not a hard ceiling. The density factor is already
    # bounded by MAX_SPATIAL_FACTOR and time_factor() <= 1.0, so official high-flow evidence
    # can raise the runtime population without allowing unbounded spawning.
    return maxi(1, int(round(float(base_max) * factor)))

func nearest_sector(anchors: Array, position: Vector3) -> String:
    var best_name := "corridor"
    var best_distance := INF
    for raw_anchor: Variant in anchors:
        if typeof(raw_anchor) != TYPE_DICTIONARY:
            continue
        var anchor: Dictionary = raw_anchor
        var anchor_position := Vector3(float(anchor.get("x", 0.0)), position.y, float(anchor.get("z", 0.0)))
        var distance := anchor_position.distance_to(position)
        if distance < best_distance:
            best_distance = distance
            best_name = str(anchor.get("id", anchor.get("name", "corridor")))
    return best_name

func _road_distance_to_point(points: Array, position: Vector3) -> float:
    var best := INF
    for index: int in range(points.size() - 1):
        var start := Vector3(float(points[index][0]), position.y, float(points[index][1]))
        var finish := Vector3(float(points[index + 1][0]), position.y, float(points[index + 1][1]))
        best = minf(best, _point_segment_distance(position, start, finish))
    return best

func _point_segment_distance(point: Vector3, start: Vector3, finish: Vector3) -> float:
    var segment := finish - start
    segment.y = 0.0
    var length_squared := segment.length_squared()
    if length_squared <= 0.0001:
        return point.distance_to(start)
    var relative := point - start
    relative.y = 0.0
    var t := clampf(relative.dot(segment) / length_squared, 0.0, 1.0)
    return point.distance_to(start + segment * t)

func _safe_int(raw: Variant) -> int:
    if raw == null:
        return 0
    if typeof(raw) in [TYPE_INT, TYPE_FLOAT]:
        return maxi(0, int(raw))
    if typeof(raw) == TYPE_STRING and str(raw).is_valid_int():
        return maxi(0, int(str(raw)))
    return 0
