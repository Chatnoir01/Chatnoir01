extends RefCounted

const ROAD_MATCH_RADIUS_M := 9.0
const DEFAULT_ROAD_WIDTH_M := 5.6
const SIDEWALK_MARGIN_M := 1.4

var _crossings: Array[Dictionary] = []
var _crossings_by_id: Dictionary = {}
var _states: Dictionary = {}


func rebuild(roads: Array[Dictionary], controls: Array) -> void:
    _crossings.clear()
    _crossings_by_id.clear()
    _states.clear()

    for raw_control: Variant in controls:
        if typeof(raw_control) != TYPE_DICTIONARY:
            continue
        var control: Dictionary = raw_control
        if str(control.get("kind", "")) != "crossing":
            continue

        var raw_point: Variant = control.get("point", null)
        if raw_point == null or not raw_point is Array or raw_point.size() < 2:
            continue

        var crossing_id := int(control.get("osm_id", 0))
        if crossing_id <= 0 or _crossings_by_id.has(crossing_id):
            continue

        var position := Vector3(float(raw_point[0]), 0.68, float(raw_point[1]))
        var nearest := _nearest_road_segment(roads, position)
        if float(nearest.get("distance_m", INF)) > ROAD_MATCH_RADIUS_M:
            continue

        var start: Vector3 = nearest.get("start", Vector3.ZERO)
        var finish: Vector3 = nearest.get("finish", Vector3.ZERO)
        var road_direction := finish - start
        road_direction.y = 0.0
        if road_direction.length_squared() <= 0.001:
            continue
        road_direction = road_direction.normalized()

        var crossing_direction := Vector3(-road_direction.z, 0.0, road_direction.x)
        var road: Dictionary = nearest.get("road", {})
        var width := maxf(3.0, _safe_float(road.get("width", null), DEFAULT_ROAD_WIDTH_M))
        var half_span := maxf(3.2, width * 0.5 + SIDEWALK_MARGIN_M)

        var descriptor := {
            "id": crossing_id,
            "osm_id": crossing_id,
            "position": position,
            "start": position - crossing_direction * half_span,
            "finish": position + crossing_direction * half_span,
            "road_direction": road_direction,
            "crossing_direction": crossing_direction,
            "span_m": half_span * 2.0,
            "signalized": bool(control.get("crossing_signals", false)),
            "button_operated": bool(control.get("button_operated", false)),
            "crossing_type": str(control.get("crossing", "")),
        }
        _crossings.append(descriptor)
        _crossings_by_id[crossing_id] = descriptor


func register_waiting(crossing_id: int, pedestrian_id: int) -> bool:
    if not _crossings_by_id.has(crossing_id):
        return false
    var state := _state_for(crossing_id)
    var waiting: Dictionary = state.get("waiting", {})
    var crossing: Dictionary = state.get("crossing", {})
    waiting[pedestrian_id] = true
    crossing.erase(pedestrian_id)
    state["waiting"] = waiting
    state["crossing"] = crossing
    _states[crossing_id] = state
    return true


func begin_crossing(crossing_id: int, pedestrian_id: int) -> bool:
    if not _crossings_by_id.has(crossing_id):
        return false
    var state := _state_for(crossing_id)
    var waiting: Dictionary = state.get("waiting", {})
    var crossing: Dictionary = state.get("crossing", {})
    waiting.erase(pedestrian_id)
    crossing[pedestrian_id] = true
    state["waiting"] = waiting
    state["crossing"] = crossing
    _states[crossing_id] = state
    return true


func clear_pedestrian(crossing_id: int, pedestrian_id: int) -> void:
    if not _states.has(crossing_id):
        return
    var state: Dictionary = _states[crossing_id]
    var waiting: Dictionary = state.get("waiting", {})
    var crossing: Dictionary = state.get("crossing", {})
    waiting.erase(pedestrian_id)
    crossing.erase(pedestrian_id)
    if waiting.is_empty() and crossing.is_empty():
        _states.erase(crossing_id)
        return
    state["waiting"] = waiting
    state["crossing"] = crossing
    _states[crossing_id] = state


func crossing_requires_stop(crossing_id: int) -> bool:
    if not _states.has(crossing_id):
        return false
    var state: Dictionary = _states[crossing_id]
    var waiting: Dictionary = state.get("waiting", {})
    var crossing: Dictionary = state.get("crossing", {})
    return not waiting.is_empty() or not crossing.is_empty()


func get_crossing_state(crossing_id: int) -> Dictionary:
    var state := _state_for(crossing_id)
    var waiting: Dictionary = state.get("waiting", {})
    var crossing: Dictionary = state.get("crossing", {})
    return {
        "waiting": waiting.size(),
        "crossing": crossing.size(),
        "requires_stop": not waiting.is_empty() or not crossing.is_empty(),
    }


func get_crossings_near(position: Vector3, radius_m: float, unsignalized_only: bool = true) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    var radius := maxf(0.0, radius_m)
    for crossing: Dictionary in _crossings:
        if unsignalized_only and bool(crossing.get("signalized", false)):
            continue
        var crossing_position: Vector3 = crossing.get("position", Vector3.ZERO)
        if crossing_position.distance_to(position) <= radius:
            result.append(crossing.duplicate(true))
    return result


func get_crossing(crossing_id: int) -> Dictionary:
    if not _crossings_by_id.has(crossing_id):
        return {}
    return (_crossings_by_id[crossing_id] as Dictionary).duplicate(true)


func get_crossing_count() -> int:
    return _crossings.size()


func get_unsignalized_crossing_count() -> int:
    var count := 0
    for crossing: Dictionary in _crossings:
        if not bool(crossing.get("signalized", false)):
            count += 1
    return count


func get_active_crossing_count() -> int:
    var count := 0
    for raw_id: Variant in _states.keys():
        if crossing_requires_stop(int(raw_id)):
            count += 1
    return count


func _state_for(crossing_id: int) -> Dictionary:
    if _states.has(crossing_id):
        return (_states[crossing_id] as Dictionary).duplicate(true)
    return {"waiting": {}, "crossing": {}}


func _nearest_road_segment(roads: Array[Dictionary], point: Vector3) -> Dictionary:
    var best_distance := INF
    var best: Dictionary = {}
    for road: Dictionary in roads:
        var points: Array = road.get("points", [])
        for index: int in range(points.size() - 1):
            var start := _raw_point(points[index])
            var finish := _raw_point(points[index + 1])
            var distance := _point_segment_distance(point, start, finish)
            if distance < best_distance:
                best_distance = distance
                best = {
                    "distance_m": distance,
                    "start": start,
                    "finish": finish,
                    "road": road,
                }
    return best


func _raw_point(raw: Variant) -> Vector3:
    return Vector3(float(raw[0]), 0.68, float(raw[1]))


func _point_segment_distance(point: Vector3, start: Vector3, finish: Vector3) -> float:
    var segment := finish - start
    segment.y = 0.0
    var length_squared := segment.length_squared()
    if length_squared <= 0.0001:
        var flat_point := point
        flat_point.y = start.y
        return flat_point.distance_to(start)
    var relative := point - start
    relative.y = 0.0
    var t := clampf(relative.dot(segment) / length_squared, 0.0, 1.0)
    var nearest := start + segment * t
    var flat := point
    flat.y = nearest.y
    return flat.distance_to(nearest)


func _safe_float(raw: Variant, fallback: float) -> float:
    if raw == null:
        return fallback
    if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT:
        return float(raw)
    if typeof(raw) == TYPE_STRING and str(raw).is_valid_float():
        return float(str(raw))
    return fallback
