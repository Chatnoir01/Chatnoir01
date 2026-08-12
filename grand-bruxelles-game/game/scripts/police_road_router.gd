extends Node

@export_file("*.json") var road_data_path: String = "res://data/osm/vertical_slice_01.game.json"
@export var junction_tolerance: float = 3.5

var _segments: Array[Dictionary] = []


func _ready() -> void:
    _load_network()


func _load_network() -> void:
    _segments.clear()
    if not FileAccess.file_exists(road_data_path):
        push_warning("Police road router data missing: %s" % road_data_path)
        return

    var text: String = FileAccess.get_file_as_string(road_data_path)
    var parsed: Variant = JSON.parse_string(text)
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Police road router invalid JSON: %s" % road_data_path)
        return

    var city_data: Dictionary = parsed as Dictionary
    var roads: Array = city_data.get("roads", []) as Array
    for road_value: Variant in roads:
        if not road_value is Dictionary:
            continue
        var road: Dictionary = road_value as Dictionary
        if not bool(road.get("drivable", false)):
            continue
        var points: Array = road.get("points", []) as Array
        for index: int in range(points.size() - 1):
            var a: Vector3 = _point(points[index])
            var b: Vector3 = _point(points[index + 1])
            if a.distance_to(b) < 1.0:
                continue
            _segments.append({"a": a, "b": b})

    print("Grand Bruxelles police road router: %d drivable segments" % _segments.size())


func _point(raw: Variant) -> Vector3:
    var coordinates: Array = raw as Array
    if coordinates.size() < 2:
        return Vector3.ZERO
    return Vector3(float(coordinates[0]), 0.0, float(coordinates[1]))


func get_segment_count() -> int:
    return _segments.size()


func nearest_road_point(position: Vector3) -> Vector3:
    var segment_index: int = _nearest_segment_index(position)
    if segment_index < 0:
        return position
    var segment: Dictionary = _segments[segment_index]
    var a: Vector3 = segment.get("a", Vector3.ZERO)
    var b: Vector3 = segment.get("b", Vector3.ZERO)
    return _closest_on_segment(position, a, b)


func road_tangent_near(position: Vector3) -> Vector3:
    var segment_index: int = _nearest_segment_index(position)
    if segment_index < 0:
        return Vector3(0.0, 0.0, -1.0)
    var segment: Dictionary = _segments[segment_index]
    var a: Vector3 = segment.get("a", Vector3.ZERO)
    var b: Vector3 = segment.get("b", Vector3.ZERO)
    var tangent: Vector3 = b - a
    tangent.y = 0.0
    if tangent.length_squared() < 0.001:
        return Vector3(0.0, 0.0, -1.0)
    return tangent.normalized()


func next_pursuit_point(position: Vector3, target: Vector3, heading: Vector3 = Vector3.ZERO) -> Vector3:
    var segment_index: int = _nearest_segment_index(position)
    if segment_index < 0:
        return target

    var segment: Dictionary = _segments[segment_index]
    var a: Vector3 = segment.get("a", Vector3.ZERO)
    var b: Vector3 = segment.get("b", Vector3.ZERO)
    var anchor: Vector3 = a if a.distance_squared_to(target) < b.distance_squared_to(target) else b

    var candidates: Array[Vector3] = [a, b]
    for candidate_segment: Dictionary in _segments:
        var candidate_a: Vector3 = candidate_segment.get("a", Vector3.ZERO)
        var candidate_b: Vector3 = candidate_segment.get("b", Vector3.ZERO)
        if candidate_a.distance_to(anchor) <= junction_tolerance:
            candidates.append(candidate_b)
        elif candidate_b.distance_to(anchor) <= junction_tolerance:
            candidates.append(candidate_a)

    var normalized_heading: Vector3 = heading
    normalized_heading.y = 0.0
    if normalized_heading.length_squared() > 0.001:
        normalized_heading = normalized_heading.normalized()

    var best: Vector3 = anchor
    var best_score: float = INF
    for candidate: Vector3 in candidates:
        var direction: Vector3 = candidate - position
        direction.y = 0.0
        if direction.length() < 1.0:
            continue
        var score: float = candidate.distance_to(target)
        if normalized_heading.length_squared() > 0.001:
            var alignment: float = normalized_heading.dot(direction.normalized())
            score += (1.0 - alignment) * 5.0
        if score < best_score:
            best_score = score
            best = candidate

    if best.distance_to(position) < 2.0:
        return Vector3(target.x, 0.0, target.z)
    return best


func distance_to_road(position: Vector3) -> float:
    var nearest: Vector3 = nearest_road_point(position)
    var flat_delta: Vector3 = nearest - position
    flat_delta.y = 0.0
    return flat_delta.length()


func _nearest_segment_index(position: Vector3) -> int:
    if _segments.is_empty():
        return -1
    var best_index: int = -1
    var best_distance: float = INF
    for index: int in range(_segments.size()):
        var segment: Dictionary = _segments[index]
        var a: Vector3 = segment.get("a", Vector3.ZERO)
        var b: Vector3 = segment.get("b", Vector3.ZERO)
        var closest: Vector3 = _closest_on_segment(position, a, b)
        var flat_delta: Vector3 = closest - position
        flat_delta.y = 0.0
        var distance: float = flat_delta.length_squared()
        if distance < best_distance:
            best_distance = distance
            best_index = index
    return best_index


func _closest_on_segment(position: Vector3, a: Vector3, b: Vector3) -> Vector3:
    var p: Vector2 = Vector2(position.x, position.z)
    var start: Vector2 = Vector2(a.x, a.z)
    var finish: Vector2 = Vector2(b.x, b.z)
    var segment: Vector2 = finish - start
    var length_squared: float = segment.length_squared()
    if length_squared < 0.0001:
        return Vector3(a.x, 0.0, a.z)
    var ratio: float = clampf((p - start).dot(segment) / length_squared, 0.0, 1.0)
    var result: Vector2 = start + segment * ratio
    return Vector3(result.x, 0.0, result.y)
