extends RefCounted
class_name TrafficLanePathAdapter

## Lane-centerline continuity adapter for the existing Brussels road graph.
##
## Design inspiration: RoadLaneAgent from TheDuckCow/godot-road-generator
## (MIT License, copyright (c) 2025 Moo-Ack! Productions).
## We do not import the road mesh/editor plugin. This adapter keeps Grand
## Bruxelles' own UrbIS/OSM road graph and only applies the useful lane-following
## idea: consecutive directed road segments should share one continuous lane
## centerline instead of independently shifted endpoints.

const MAX_MITER_DISTANCE_M := 5.0
const CONNECTED_NODE_TOLERANCE_M := 0.75
const PARALLEL_EPSILON := 0.00001

func build_bundle(
    edge_ids: Array,
    road_graph: RefCounted,
    fallback_speed_kmh: float = 30.0
) -> Dictionary:
    var segments: Array[Dictionary] = []
    var first_road_name := ""
    var first_osm_id := 0

    for raw_edge_id: Variant in edge_ids:
        var edge: Dictionary = road_graph.call("get_edge", int(raw_edge_id))
        if edge.is_empty():
            continue
        var road: Dictionary = edge.get("road", {})
        var raw_start: Vector3 = edge.get("from", Vector3.ZERO)
        var raw_finish: Vector3 = edge.get("to", Vector3.ZERO)
        var direction := raw_finish - raw_start
        direction.y = 0.0
        if direction.length_squared() <= 0.001:
            continue
        direction = direction.normalized()
        var right := Vector3(-direction.z, 0.0, direction.x)
        var lane_offset := _lane_offset_for_road(road)
        var speed_limit := _speed_limit_for_road(road, fallback_speed_kmh)
        segments.append({
            "raw_start": raw_start,
            "raw_finish": raw_finish,
            "shifted_start": raw_start + right * lane_offset,
            "shifted_finish": raw_finish + right * lane_offset,
            "speed_limit_kmh": speed_limit,
        })
        if first_osm_id == 0:
            first_osm_id = int(edge.get("osm_id", 0))
            first_road_name = str(road.get("name", ""))

    var points := PackedVector3Array()
    var speed_limits := PackedFloat32Array()
    if segments.is_empty():
        return {
            "points": points,
            "speed_limits_kmh": speed_limits,
            "road_name": first_road_name,
            "osm_id": first_osm_id,
            "lane_join_count": 0,
            "lane_join_fallback_count": 0,
        }

    var first_segment: Dictionary = segments[0]
    points.append(first_segment["shifted_start"])
    speed_limits.append(float(first_segment["speed_limit_kmh"]))

    var join_count := 0
    var fallback_count := 0
    for index: int in range(segments.size() - 1):
        var current: Dictionary = segments[index]
        var following: Dictionary = segments[index + 1]
        var current_raw_finish: Vector3 = current["raw_finish"]
        var following_raw_start: Vector3 = following["raw_start"]
        if current_raw_finish.distance_to(following_raw_start) > CONNECTED_NODE_TOLERANCE_M:
            _append_distinct(points, speed_limits, current["shifted_finish"], float(current["speed_limit_kmh"]))
            _append_distinct(points, speed_limits, following["shifted_start"], float(following["speed_limit_kmh"]))
            fallback_count += 1
            continue

        var join_result := _joined_lane_point(current, following)
        var join_point: Vector3 = join_result.get("point", current["shifted_finish"])
        if bool(join_result.get("used_miter", false)):
            join_count += 1
        else:
            fallback_count += 1
        _append_distinct(
            points,
            speed_limits,
            join_point,
            minf(float(current["speed_limit_kmh"]), float(following["speed_limit_kmh"]))
        )

    var last_segment: Dictionary = segments[segments.size() - 1]
    _append_distinct(points, speed_limits, last_segment["shifted_finish"], float(last_segment["speed_limit_kmh"]))
    return {
        "points": points,
        "speed_limits_kmh": speed_limits,
        "road_name": first_road_name,
        "osm_id": first_osm_id,
        "lane_join_count": join_count,
        "lane_join_fallback_count": fallback_count,
    }

func _joined_lane_point(current: Dictionary, following: Dictionary) -> Dictionary:
    var a: Vector3 = current["shifted_start"]
    var b: Vector3 = current["shifted_finish"]
    var c: Vector3 = following["shifted_start"]
    var d: Vector3 = following["shifted_finish"]
    var intersection := _line_intersection_xz(a, b, c, d)
    var raw_node := (current["raw_finish"] as Vector3).lerp(following["raw_start"] as Vector3, 0.5)
    if bool(intersection.get("valid", false)):
        var candidate: Vector3 = intersection["point"]
        if candidate.distance_to(raw_node) <= MAX_MITER_DISTANCE_M:
            candidate.y = (b.y + c.y) * 0.5
            return {"point": candidate, "used_miter": true}

    var fallback := (b + c) * 0.5
    fallback.y = (b.y + c.y) * 0.5
    return {"point": fallback, "used_miter": false}

func _line_intersection_xz(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> Dictionary:
    var p := Vector2(a.x, a.z)
    var r := Vector2(b.x - a.x, b.z - a.z)
    var q := Vector2(c.x, c.z)
    var s := Vector2(d.x - c.x, d.z - c.z)
    var denominator := _cross2(r, s)
    if absf(denominator) <= PARALLEL_EPSILON:
        return {"valid": false}
    var t := _cross2(q - p, s) / denominator
    var point2 := p + r * t
    return {"valid": true, "point": Vector3(point2.x, (b.y + c.y) * 0.5, point2.y)}

func _cross2(a: Vector2, b: Vector2) -> float:
    return a.x * b.y - a.y * b.x

func _append_distinct(points: PackedVector3Array, speeds: PackedFloat32Array, point: Vector3, speed_kmh: float) -> void:
    if not points.is_empty() and points[points.size() - 1].distance_to(point) <= 0.05:
        if not speeds.is_empty():
            speeds[speeds.size() - 1] = minf(float(speeds[speeds.size() - 1]), speed_kmh)
        return
    points.append(point)
    speeds.append(speed_kmh)

func _lane_offset_for_road(road: Dictionary) -> float:
    var width := maxf(3.0, _safe_float(road.get("width", 5.6), 5.6))
    var oneway := _normalized_oneway(road)
    var lanes := _safe_nonnegative_int(road.get("lanes", null))
    if oneway != 0:
        if lanes >= 2:
            return clampf(width * 0.18, 0.7, 1.65)
        return clampf(width * 0.08, 0.25, 0.65)
    return clampf(width * 0.23, 1.0, 2.05)

func _speed_limit_for_road(road: Dictionary, fallback_speed_kmh: float) -> float:
    var raw_limit: Variant = road.get("maxspeed_kmh", null)
    if raw_limit != null and (typeof(raw_limit) == TYPE_INT or typeof(raw_limit) == TYPE_FLOAT):
        var tagged_limit := float(raw_limit)
        if tagged_limit > 0.0:
            return clampf(tagged_limit, 5.0, 90.0)
    var road_class := str(road.get("class", ""))
    if road_class in ["living_street", "service"]:
        return minf(fallback_speed_kmh, 20.0)
    return fallback_speed_kmh

func _normalized_oneway(road: Dictionary) -> int:
    var raw: Variant = road.get("oneway", 0)
    if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT:
        var numeric := int(raw)
        if numeric < 0:
            return -1
        if numeric > 0:
            return 1
        return 0
    var text := str(raw).strip_edges().to_lower()
    if text == "-1":
        return -1
    if text in ["1", "yes", "true"]:
        return 1
    if str(road.get("junction", "")).to_lower() == "roundabout":
        return 1
    return 0

func _safe_nonnegative_int(raw: Variant) -> int:
    if raw == null:
        return 0
    if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT:
        return maxi(0, int(raw))
    if typeof(raw) == TYPE_STRING and str(raw).is_valid_int():
        return maxi(0, int(str(raw)))
    return 0

func _safe_float(raw: Variant, fallback: float) -> float:
    if raw == null:
        return fallback
    if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT:
        return float(raw)
    if typeof(raw) == TYPE_STRING and str(raw).is_valid_float():
        return float(str(raw))
    return fallback
