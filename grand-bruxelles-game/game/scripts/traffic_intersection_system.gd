extends RefCounted

const NODE_PRECISION := 3
const CONTROL_MATCH_RADIUS_M := 9.0
const ROUTE_SNAP_RADIUS_M := 6.5
const REQUEST_TTL_S := 0.55
const RESERVATION_TTL_S := 2.6
const APPROACH_WINDOW_M := 22.0
const GIVE_WAY_CONFLICT_WINDOW_M := 28.0
const RIGHT_DOT_THRESHOLD := 0.52

var _intersections: Array[Dictionary] = []
var _requests: Dictionary = {}
var _reservations: Dictionary = {}

func rebuild(roads: Array[Dictionary], controls: Array) -> void:
    _intersections.clear()
    _requests.clear()
    _reservations.clear()
    var node_positions: Dictionary = {}
    var node_neighbors: Dictionary = {}
    for road: Dictionary in roads:
        var points: Array = road.get("points", [])
        for index: int in range(points.size() - 1):
            var a := _raw_point(points[index])
            var b := _raw_point(points[index + 1])
            if a.distance_to(b) < 1.0:
                continue
            var a_key := _node_key(a)
            var b_key := _node_key(b)
            node_positions[a_key] = a
            node_positions[b_key] = b
            _add_neighbor(node_neighbors, a_key, b_key)
            _add_neighbor(node_neighbors, b_key, a_key)
    var serial := 0
    for raw_key: Variant in node_positions.keys():
        var key := str(raw_key)
        var neighbors: Dictionary = node_neighbors.get(key, {})
        if neighbors.size() < 3:
            continue
        var position: Vector3 = node_positions[key]
        var control_kind := _nearest_priority_control_kind(position, controls)
        _intersections.append({
            "id": serial,
            "key": key,
            "position": position,
            "degree": neighbors.size(),
            "control_kind": control_kind,
            "priority_to_right": false,
        })
        serial += 1

func _add_neighbor(store: Dictionary, from_key: String, to_key: String) -> void:
    var neighbors: Dictionary = store.get(from_key, {})
    neighbors[to_key] = true
    store[from_key] = neighbors

func _raw_point(raw: Variant) -> Vector3:
    return Vector3(float(raw[0]), 0.68, float(raw[1]))

func _node_key(point: Vector3) -> String:
    var format := "%%.%df|%%.%df" % [NODE_PRECISION, NODE_PRECISION]
    return format % [point.x, point.z]

func _nearest_priority_control_kind(position: Vector3, controls: Array) -> String:
    var best_distance := CONTROL_MATCH_RADIUS_M + 0.001
    var best_kind := ""
    for raw_control: Variant in controls:
        if typeof(raw_control) != TYPE_DICTIONARY:
            continue
        var control: Dictionary = raw_control
        var kind := str(control.get("kind", ""))
        if kind not in ["traffic_signals", "give_way", "stop"]:
            continue
        var raw_point: Variant = control.get("point", null)
        if raw_point == null or not raw_point is Array or raw_point.size() < 2:
            continue
        var control_position := Vector3(float(raw_point[0]), position.y, float(raw_point[1]))
        var distance := position.distance_to(control_position)
        if distance < best_distance:
            best_distance = distance
            best_kind = kind
    return best_kind

func intersections_for_route(route: PackedVector3Array) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    if route.size() < 2:
        return result
    for intersection: Dictionary in _intersections:
        var position: Vector3 = intersection["position"]
        var nearest := _nearest_route_segment(route, position)
        if float(nearest.get("distance_m", INF)) > ROUTE_SNAP_RADIUS_M:
            continue
        var segment_index := int(nearest.get("segment_index", -1))
        if segment_index < 0 or segment_index >= route.size() - 1:
            continue
        var approach := route[segment_index + 1] - route[segment_index]
        approach.y = 0.0
        if approach.length_squared() <= 0.001:
            continue
        approach = approach.normalized()
        var mapped := intersection.duplicate(true)
        mapped["route_index"] = segment_index + 1
        mapped["route_position"] = route[segment_index + 1]
        mapped["approach_direction"] = approach
        result.append(mapped)
    result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("route_index", 0)) < int(b.get("route_index", 0)))
    return result

func request_passage(intersection_id: int, vehicle_id: int, approach_direction: Vector3, distance_m: float, now_seconds: float = -1.0) -> bool:
    if now_seconds < 0.0:
        now_seconds = float(Time.get_ticks_msec()) / 1000.0
    _purge_expired(now_seconds)
    var requests := _register_request(intersection_id, vehicle_id, approach_direction, distance_m, false, now_seconds)
    var reservation_state := _reservation_permission(intersection_id, vehicle_id, now_seconds)
    if reservation_state != 0:
        return reservation_state > 0
    if distance_m > APPROACH_WINDOW_M:
        return true
    if _must_yield_to_right(vehicle_id, approach_direction, distance_m, requests):
        return false
    if distance_m <= 3.4:
        _reserve(intersection_id, vehicle_id, now_seconds)
    return true

func request_controlled_passage(intersection_id: int, vehicle_id: int, approach_direction: Vector3, distance_m: float, yielding_approach: bool, now_seconds: float = -1.0) -> bool:
    if now_seconds < 0.0:
        now_seconds = float(Time.get_ticks_msec()) / 1000.0
    _purge_expired(now_seconds)
    var requests := _register_request(intersection_id, vehicle_id, approach_direction, distance_m, yielding_approach, now_seconds)
    var reservation_state := _reservation_permission(intersection_id, vehicle_id, now_seconds)
    if reservation_state != 0:
        return reservation_state > 0
    if distance_m > GIVE_WAY_CONFLICT_WINDOW_M:
        return true
    if yielding_approach and _has_conflicting_priority_request(vehicle_id, approach_direction, requests):
        return false
    if yielding_approach and _has_competing_yield_request(vehicle_id, distance_m, requests):
        return false
    if distance_m <= 3.4:
        _reserve(intersection_id, vehicle_id, now_seconds)
    return true

func _register_request(intersection_id: int, vehicle_id: int, approach_direction: Vector3, distance_m: float, yielding_approach: bool, now_seconds: float) -> Dictionary:
    var requests: Dictionary = _requests.get(intersection_id, {})
    var normalized := approach_direction
    normalized.y = 0.0
    if normalized.length_squared() > 0.001:
        normalized = normalized.normalized()
    requests[vehicle_id] = {"vehicle_id": vehicle_id, "approach_direction": normalized, "distance_m": maxf(0.0, distance_m), "yielding": yielding_approach, "seen_s": now_seconds}
    _requests[intersection_id] = requests
    return requests

func _reservation_permission(intersection_id: int, vehicle_id: int, now_seconds: float) -> int:
    var reservation: Dictionary = _reservations.get(intersection_id, {})
    if reservation.is_empty():
        return 0
    var holder := int(reservation.get("vehicle_id", -1))
    if holder == vehicle_id:
        reservation["expires_s"] = now_seconds + RESERVATION_TTL_S
        _reservations[intersection_id] = reservation
        return 1
    return -1

func _reserve(intersection_id: int, vehicle_id: int, now_seconds: float) -> void:
    _reservations[intersection_id] = {"vehicle_id": vehicle_id, "expires_s": now_seconds + RESERVATION_TTL_S}

func _has_conflicting_priority_request(vehicle_id: int, approach_direction: Vector3, requests: Dictionary) -> bool:
    var current := approach_direction
    current.y = 0.0
    if current.length_squared() <= 0.001:
        return false
    current = current.normalized()
    for raw_other_id: Variant in requests.keys():
        var other_id := int(raw_other_id)
        if other_id == vehicle_id:
            continue
        var other: Dictionary = requests[other_id]
        if bool(other.get("yielding", false)):
            continue
        var other_distance := float(other.get("distance_m", INF))
        if other_distance > GIVE_WAY_CONFLICT_WINDOW_M:
            continue
        var other_approach: Vector3 = other.get("approach_direction", Vector3.ZERO)
        other_approach.y = 0.0
        if other_approach.length_squared() <= 0.001:
            continue
        other_approach = other_approach.normalized()
        if current.dot(other_approach) > 0.82:
            continue
        return true
    return false

func _has_competing_yield_request(vehicle_id: int, distance_m: float, requests: Dictionary) -> bool:
    for raw_other_id: Variant in requests.keys():
        var other_id := int(raw_other_id)
        if other_id == vehicle_id:
            continue
        var other: Dictionary = requests[other_id]
        if not bool(other.get("yielding", false)):
            continue
        var other_distance := float(other.get("distance_m", INF))
        if other_distance + 0.5 < distance_m:
            return true
        if absf(other_distance - distance_m) <= 0.5 and other_id < vehicle_id:
            return true
    return false

func release_vehicle(vehicle_id: int) -> void:
    for raw_id: Variant in _requests.keys():
        var intersection_id := int(raw_id)
        var requests: Dictionary = _requests.get(intersection_id, {})
        requests.erase(vehicle_id)
        if requests.is_empty():
            _requests.erase(intersection_id)
        else:
            _requests[intersection_id] = requests
    for raw_id: Variant in _reservations.keys():
        var intersection_id := int(raw_id)
        var reservation: Dictionary = _reservations.get(intersection_id, {})
        if int(reservation.get("vehicle_id", -1)) == vehicle_id:
            _reservations.erase(intersection_id)

func _must_yield_to_right(vehicle_id: int, approach_direction: Vector3, distance_m: float, requests: Dictionary) -> bool:
    var current := approach_direction
    current.y = 0.0
    if current.length_squared() <= 0.001:
        return false
    current = current.normalized()
    var current_right := Vector3(-current.z, 0.0, current.x)
    for raw_other_id: Variant in requests.keys():
        var other_id := int(raw_other_id)
        if other_id == vehicle_id:
            continue
        var other: Dictionary = requests[other_id]
        var other_distance := float(other.get("distance_m", INF))
        if other_distance > APPROACH_WINDOW_M:
            continue
        var other_approach: Vector3 = other.get("approach_direction", Vector3.ZERO)
        other_approach.y = 0.0
        if other_approach.length_squared() <= 0.001:
            continue
        other_approach = other_approach.normalized()
        var other_source_side := -other_approach
        var right_score := current_right.dot(other_source_side)
        if right_score < RIGHT_DOT_THRESHOLD:
            continue
        if other_distance <= distance_m + 4.0:
            return true
    return false

func _purge_expired(now_seconds: float) -> void:
    for raw_id: Variant in _requests.keys():
        var intersection_id := int(raw_id)
        var requests: Dictionary = _requests.get(intersection_id, {})
        for raw_vehicle_id: Variant in requests.keys():
            var vehicle_id := int(raw_vehicle_id)
            var request: Dictionary = requests[vehicle_id]
            if now_seconds - float(request.get("seen_s", 0.0)) > REQUEST_TTL_S:
                requests.erase(vehicle_id)
        if requests.is_empty():
            _requests.erase(intersection_id)
        else:
            _requests[intersection_id] = requests
    for raw_id: Variant in _reservations.keys():
        var intersection_id := int(raw_id)
        var reservation: Dictionary = _reservations.get(intersection_id, {})
        if float(reservation.get("expires_s", 0.0)) <= now_seconds:
            _reservations.erase(intersection_id)

func _nearest_route_segment(route: PackedVector3Array, point: Vector3) -> Dictionary:
    var best_distance := INF
    var best_index := -1
    for index: int in range(route.size() - 1):
        var distance := _point_segment_distance(point, route[index], route[index + 1])
        if distance < best_distance:
            best_distance = distance
            best_index = index
    return {"segment_index": best_index, "distance_m": best_distance}

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

func get_intersection_count() -> int:
    return _intersections.size()

func get_right_priority_count() -> int:
    var count := 0
    for intersection: Dictionary in _intersections:
        if bool(intersection.get("priority_to_right", false)):
            count += 1
    return count

func get_give_way_intersection_count() -> int:
    var count := 0
    for intersection: Dictionary in _intersections:
        if str(intersection.get("control_kind", "")) == "give_way":
            count += 1
    return count
