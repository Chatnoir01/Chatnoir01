extends RefCounted

var _edges: Array[Dictionary] = []
var _outgoing: Dictionary = {}
var _incoming: Dictionary = {}
var _node_positions: Dictionary = {}

func rebuild(roads: Array[Dictionary]) -> void:
    _edges.clear()
    _outgoing.clear()
    _incoming.clear()
    _node_positions.clear()
    for road: Dictionary in roads:
        var points: Array = road.get("points", [])
        if points.size() < 2:
            continue
        var oneway := _normalized_oneway(road)
        for index: int in range(points.size() - 1):
            var start := _raw_point(points[index])
            var finish := _raw_point(points[index + 1])
            if start.distance_to(finish) < 1.0:
                continue
            if oneway != -1:
                _append_edge(start, finish, road, index, 1)
            if oneway != 1:
                _append_edge(finish, start, road, index, -1)

func _append_edge(start: Vector3, finish: Vector3, road: Dictionary, segment_index: int, travel_direction: int) -> void:
    var from_key := _node_key(start)
    var to_key := _node_key(finish)
    if from_key == to_key:
        return
    var edge_id := _edges.size()
    var edge := {"id": edge_id, "from_key": from_key, "to_key": to_key, "from": start, "to": finish, "length_m": start.distance_to(finish), "road": road, "osm_id": int(road.get("osm_id", 0)), "segment_index": segment_index, "travel_direction": travel_direction}
    _edges.append(edge)
    _node_positions[from_key] = start
    _node_positions[to_key] = finish
    if not _outgoing.has(from_key): _outgoing[from_key] = []
    var outgoing_edges: Array = _outgoing[from_key]
    outgoing_edges.append(edge_id)
    _outgoing[from_key] = outgoing_edges
    if not _incoming.has(to_key): _incoming[to_key] = []
    var incoming_edges: Array = _incoming[to_key]
    incoming_edges.append(edge_id)
    _incoming[to_key] = incoming_edges

func _raw_point(raw: Variant) -> Vector3:
    return Vector3(float(raw[0]), 0.68, float(raw[1]))

func _node_key(point: Vector3) -> String:
    return "%.3f|%.3f" % [point.x, point.z]

func _normalized_oneway(road: Dictionary) -> int:
    var raw: Variant = road.get("oneway", 0)
    if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT:
        var numeric := int(raw)
        if numeric < 0: return -1
        if numeric > 0: return 1
        return 0
    var text := str(raw).strip_edges().to_lower()
    if text == "-1": return -1
    if text in ["1", "yes", "true"]: return 1
    if str(road.get("junction", "")).to_lower() == "roundabout": return 1
    return 0

func find_candidate_edge_ids(anchor: Vector3, radius_m: float) -> Array[int]:
    var result: Array[int] = []
    var radius_squared := radius_m * radius_m
    for edge: Dictionary in _edges:
        var midpoint := ((edge["from"] as Vector3) + (edge["to"] as Vector3)) * 0.5
        midpoint.y = anchor.y
        if midpoint.distance_squared_to(anchor) <= radius_squared:
            result.append(int(edge["id"]))
    return result

func build_random_walk(start_edge_id: int, rng: RandomNumberGenerator, target_length_m: float, max_length_m: float, max_edges: int) -> Array[int]:
    var route: Array[int] = []
    if start_edge_id < 0 or start_edge_id >= _edges.size() or max_edges <= 0:
        return route
    var current_edge_id := start_edge_id
    var total_length := 0.0
    var visited: Dictionary = {}
    while route.size() < max_edges:
        var current: Dictionary = _edges[current_edge_id]
        route.append(current_edge_id)
        visited[current_edge_id] = true
        total_length += float(current.get("length_m", 0.0))
        if total_length >= target_length_m or total_length >= max_length_m:
            break
        var outgoing_raw: Array = _outgoing.get(str(current["to_key"]), [])
        var candidates: Array[int] = []
        var unvisited: Array[int] = []
        for raw_id in outgoing_raw:
            var candidate_id := int(raw_id)
            if candidate_id < 0 or candidate_id >= _edges.size(): continue
            var candidate: Dictionary = _edges[candidate_id]
            if str(candidate["to_key"]) == str(current["from_key"]): continue
            candidates.append(candidate_id)
            if not visited.has(candidate_id): unvisited.append(candidate_id)
        if not unvisited.is_empty(): candidates = unvisited
        if candidates.is_empty(): break
        current_edge_id = _choose_next_edge(current, candidates, rng)
        if current_edge_id < 0: break
    return route

func _choose_next_edge(current: Dictionary, candidates: Array[int], rng: RandomNumberGenerator) -> int:
    if candidates.is_empty(): return -1
    if candidates.size() == 1: return candidates[0]
    if rng.randf() >= 0.68: return candidates[rng.randi_range(0, candidates.size() - 1)]
    var current_direction: Vector3 = current["to"] - current["from"]
    current_direction.y = 0.0
    current_direction = current_direction.normalized()
    var best_id := candidates[0]
    var best_dot := -2.0
    for candidate_id in candidates:
        var candidate: Dictionary = _edges[candidate_id]
        var direction: Vector3 = candidate["to"] - candidate["from"]
        direction.y = 0.0
        if direction.length_squared() <= 0.001: continue
        direction = direction.normalized()
        var alignment := current_direction.dot(direction)
        if int(candidate.get("osm_id", 0)) == int(current.get("osm_id", 0)): alignment += 0.18
        if alignment > best_dot:
            best_dot = alignment
            best_id = candidate_id
    return best_id

func get_edge(edge_id: int) -> Dictionary:
    if edge_id < 0 or edge_id >= _edges.size(): return {}
    return _edges[edge_id]

func get_node_count() -> int: return _node_positions.size()
func get_edge_count() -> int: return _edges.size()
func get_intersection_count() -> int:
    var count := 0
    for raw_key in _node_positions.keys():
        var key := str(raw_key)
        var neighbors: Dictionary = {}
        for raw_id in _outgoing.get(key, []):
            var edge := get_edge(int(raw_id))
            if not edge.is_empty(): neighbors[str(edge["to_key"])] = true
        for raw_id in _incoming.get(key, []):
            var edge := get_edge(int(raw_id))
            if not edge.is_empty(): neighbors[str(edge["from_key"])] = true
        if neighbors.size() >= 3: count += 1
    return count
