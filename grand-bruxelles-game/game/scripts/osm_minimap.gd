extends Control

@export_file("*.json") var data_path: String = "res://data/osm/vertical_slice_01.game.json"
@export var padding: float = 12.0
@export var route_refresh_interval_s: float = 0.65
@export var route_rebuild_distance_m: float = 18.0
@export var max_route_connector_m: float = 140.0

@onready var player: CharacterBody3D = get_node("../Player")
@onready var mission: Node = get_node("../MissionDriveToCenter")
@onready var return_mission: Node = get_node("../MissionReturnToBourse")

const MISSION_TARGETS: Array[Vector3] = [
    Vector3(-272.04, 0.0, -217.07),
    Vector3(81.54, 0.0, -664.58),
    Vector3(319.01, 0.0, -535.20),
]
const RETURN_BOURSE := Vector3(81.54, 0.0, -664.58)
const RETURN_ACTIVE_STATE := 2
const GRAPH_KEY_SCALE := 1000.0

var _roads: Array = []
var _bounds := Vector4(-900.0, -900.0, 350.0, 950.0)
var _graph_points: Dictionary = {}
var _graph_neighbors: Dictionary = {}
var _graph_components: Dictionary = {}
var _route_world_points: Array[Vector2] = []
var _route_distance_m := 0.0
var _route_elapsed_s := 0.0
var _last_route_actor := Vector2(INF, INF)
var _last_route_target := Vector2(INF, INF)

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _load_map_data()
    _build_road_graph()
    _refresh_route(true)
    queue_redraw()

func _process(delta: float) -> void:
    _route_elapsed_s += maxf(delta, 0.0)
    if _route_elapsed_s >= maxf(route_refresh_interval_s, 0.1):
        _route_elapsed_s = 0.0
        _refresh_route(false)
    queue_redraw()

func _load_map_data() -> void:
    if not FileAccess.file_exists(data_path):
        push_warning("Minimap OSM data missing: %s" % data_path)
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_warning("Minimap could not parse OSM data")
        return
    var data: Dictionary = parsed
    _roads = data.get("roads", []) as Array
    var raw_bounds: Array = data.get("bounds_m", []) as Array
    if raw_bounds.size() == 4:
        _bounds = Vector4(float(raw_bounds[0]), float(raw_bounds[1]), float(raw_bounds[2]), float(raw_bounds[3]))

func _build_road_graph() -> void:
    _graph_points.clear()
    _graph_neighbors.clear()
    for road_value: Variant in _roads:
        if typeof(road_value) != TYPE_DICTIONARY:
            continue
        var road: Dictionary = road_value
        if not bool(road.get("drivable", false)):
            continue
        var points: Array = road.get("points", []) as Array
        var previous_key := ""
        var previous_point := Vector2.ZERO
        for raw_point: Variant in points:
            if not raw_point is Array or raw_point.size() < 2:
                continue
            var point := Vector2(float(raw_point[0]), float(raw_point[1]))
            var key := _graph_key(point)
            _graph_points[key] = point
            if not _graph_neighbors.has(key):
                _graph_neighbors[key] = {}
            if not previous_key.is_empty() and previous_key != key:
                var segment_length := previous_point.distance_to(point)
                if segment_length > 0.001:
                    _link_graph_nodes(previous_key, key, segment_length)
            previous_key = key
            previous_point = point
    _index_graph_components()

func _link_graph_nodes(a: String, b: String, distance_m: float) -> void:
    var a_neighbors: Dictionary = _graph_neighbors.get(a, {}) as Dictionary
    var b_neighbors: Dictionary = _graph_neighbors.get(b, {}) as Dictionary
    a_neighbors[b] = minf(float(a_neighbors.get(b, INF)), distance_m)
    b_neighbors[a] = minf(float(b_neighbors.get(a, INF)), distance_m)
    _graph_neighbors[a] = a_neighbors
    _graph_neighbors[b] = b_neighbors

func _index_graph_components() -> void:
    _graph_components.clear()
    var component_id := 0
    for seed_value: Variant in _graph_points.keys():
        var seed := str(seed_value)
        if _graph_components.has(seed):
            continue
        var pending: Array[String] = [seed]
        while not pending.is_empty():
            var key: String = pending.pop_back()
            if _graph_components.has(key):
                continue
            _graph_components[key] = component_id
            var neighbors: Dictionary = _graph_neighbors.get(key, {}) as Dictionary
            for neighbor_value: Variant in neighbors.keys():
                var neighbor := str(neighbor_value)
                if not _graph_components.has(neighbor):
                    pending.append(neighbor)
        component_id += 1

func _graph_key(point: Vector2) -> String:
    return "%d:%d" % [roundi(point.x * GRAPH_KEY_SCALE), roundi(point.y * GRAPH_KEY_SCALE)]

func _active_actor() -> Node3D:
    for candidate: Node in get_tree().get_nodes_in_group("vehicle"):
        if candidate is Node3D and candidate.has_method("has_driver") and bool(candidate.call("has_driver")):
            return candidate as Node3D
    return player

func _active_mission_target() -> Variant:
    var stage := int(mission.call("get_stage"))
    if stage >= 1 and stage <= MISSION_TARGETS.size():
        return MISSION_TARGETS[stage - 1]
    if return_mission != null and return_mission.has_method("get_state"):
        if int(return_mission.call("get_state")) == RETURN_ACTIVE_STATE:
            return RETURN_BOURSE
    return null

func _refresh_route(force: bool) -> void:
    var actor: Node3D = _active_actor()
    var target_value: Variant = _active_mission_target()
    if actor == null or not target_value is Vector3 or _graph_points.is_empty():
        _route_world_points.clear()
        _route_distance_m = 0.0
        return
    var actor_point := Vector2(actor.global_position.x, actor.global_position.z)
    var target3: Vector3 = target_value
    var target_point := Vector2(target3.x, target3.z)
    if not force:
        var actor_moved := actor_point.distance_to(_last_route_actor) >= maxf(route_rebuild_distance_m, 1.0)
        var target_changed := target_point.distance_to(_last_route_target) >= 0.5
        if not actor_moved and not target_changed:
            return
    _last_route_actor = actor_point
    _last_route_target = target_point
    _route_world_points = _compute_route(actor_point, target_point)
    _route_distance_m = _polyline_length(_route_world_points)

func _best_route_endpoints(start_world: Vector2, target_world: Vector2) -> Dictionary:
    var per_component: Dictionary = {}
    for key_value: Variant in _graph_points.keys():
        var key := str(key_value)
        var point_value: Variant = _graph_points.get(key)
        if not point_value is Vector2:
            continue
        var component_id := int(_graph_components.get(key, -1))
        if component_id < 0:
            continue
        var point: Vector2 = point_value
        var info: Dictionary = per_component.get(component_id, {
            "start_key": "", "start_dist": INF,
            "target_key": "", "target_dist": INF,
        }) as Dictionary
        var start_distance := start_world.distance_to(point)
        var target_distance := target_world.distance_to(point)
        if start_distance < float(info.get("start_dist", INF)):
            info["start_dist"] = start_distance
            info["start_key"] = key
        if target_distance < float(info.get("target_dist", INF)):
            info["target_dist"] = target_distance
            info["target_key"] = key
        per_component[component_id] = info
    var best: Dictionary = {}
    var best_cost := INF
    for info_value: Variant in per_component.values():
        if not info_value is Dictionary:
            continue
        var info: Dictionary = info_value
        var start_distance := float(info.get("start_dist", INF))
        var target_distance := float(info.get("target_dist", INF))
        if start_distance > max_route_connector_m or target_distance > max_route_connector_m:
            continue
        var cost := start_distance + target_distance
        if cost < best_cost:
            best_cost = cost
            best = info.duplicate()
    return best

func _compute_route(start_world: Vector2, target_world: Vector2) -> Array[Vector2]:
    var endpoints: Dictionary = _best_route_endpoints(start_world, target_world)
    if endpoints.is_empty():
        return []
    var start_key := str(endpoints.get("start_key", ""))
    var target_key := str(endpoints.get("target_key", ""))
    if start_key.is_empty() or target_key.is_empty():
        return []
    var frontier: Array[String] = [start_key]
    var distances: Dictionary = {start_key: 0.0}
    var previous: Dictionary = {}
    var visited: Dictionary = {}
    while not frontier.is_empty():
        var best_index := 0
        var best_key: String = frontier[0]
        var best_cost := float(distances.get(best_key, INF))
        for index in range(1, frontier.size()):
            var candidate_key: String = frontier[index]
            var candidate_cost := float(distances.get(candidate_key, INF))
            if candidate_cost < best_cost:
                best_index = index
                best_key = candidate_key
                best_cost = candidate_cost
        frontier.remove_at(best_index)
        if visited.has(best_key):
            continue
        visited[best_key] = true
        if best_key == target_key:
            break
        var neighbors: Dictionary = _graph_neighbors.get(best_key, {}) as Dictionary
        for neighbor_value: Variant in neighbors.keys():
            var neighbor := str(neighbor_value)
            if visited.has(neighbor):
                continue
            var new_cost := best_cost + float(neighbors[neighbor])
            if new_cost < float(distances.get(neighbor, INF)):
                distances[neighbor] = new_cost
                previous[neighbor] = best_key
                if not frontier.has(neighbor):
                    frontier.append(neighbor)
    if start_key != target_key and not previous.has(target_key):
        return []
    var route_keys: Array[String] = [target_key]
    var cursor := target_key
    while cursor != start_key:
        if not previous.has(cursor):
            return []
        cursor = str(previous[cursor])
        route_keys.append(cursor)
    route_keys.reverse()
    var result: Array[Vector2] = [start_world]
    for key: String in route_keys:
        var point_value: Variant = _graph_points.get(key)
        if point_value is Vector2:
            var point: Vector2 = point_value
            if result[result.size() - 1].distance_to(point) > 0.25:
                result.append(point)
    if result[result.size() - 1].distance_to(target_world) > 0.25:
        result.append(target_world)
    return _simplify_route(result)

func _simplify_route(points: Array[Vector2]) -> Array[Vector2]:
    if points.size() <= 2:
        return points
    var simplified: Array[Vector2] = [points[0]]
    for index in range(1, points.size() - 1):
        var a := (points[index] - simplified[simplified.size() - 1]).normalized()
        var b := (points[index + 1] - points[index]).normalized()
        if a.dot(b) < 0.997:
            simplified.append(points[index])
    simplified.append(points[points.size() - 1])
    return simplified

func _polyline_length(points: Array[Vector2]) -> float:
    var total := 0.0
    for index in range(points.size() - 1):
        total += points[index].distance_to(points[index + 1])
    return total

func _world_to_map(world_x: float, world_z: float) -> Vector2:
    var width := maxf(size.x - padding * 2.0, 1.0)
    var height := maxf(size.y - padding * 2.0, 1.0)
    var span_x := maxf(_bounds.z - _bounds.x, 1.0)
    var span_z := maxf(_bounds.w - _bounds.y, 1.0)
    return Vector2(
        padding + ((world_x - _bounds.x) / span_x) * width,
        padding + ((world_z - _bounds.y) / span_z) * height
    )

func _draw() -> void:
    draw_style_box(_panel_style(), Rect2(Vector2.ZERO, size))
    for road_value: Variant in _roads:
        if not road_value is Dictionary:
            continue
        var road: Dictionary = road_value
        var points: Array = road.get("points", []) as Array
        var road_class := str(road.get("class", ""))
        var is_major := road_class in ["primary", "secondary", "tertiary"]
        var road_color := Color(0.75, 0.75, 0.79, 0.72) if is_major else Color(0.43, 0.44, 0.48, 0.62)
        var road_width := 1.8 if is_major else 1.0
        for index in range(points.size() - 1):
            var a: Array = points[index]
            var b: Array = points[index + 1]
            draw_line(_world_to_map(float(a[0]), float(a[1])), _world_to_map(float(b[0]), float(b[1])), road_color, road_width, true)
    for index in range(_route_world_points.size() - 1):
        var a := _route_world_points[index]
        var b := _route_world_points[index + 1]
        draw_line(_world_to_map(a.x, a.y), _world_to_map(b.x, b.y), Color(0.01, 0.02, 0.03, 0.78), 6.0, true)
        draw_line(_world_to_map(a.x, a.y), _world_to_map(b.x, b.y), Color(0.18, 0.74, 1.0, 0.94), 3.2, true)
    var actor: Node3D = _active_actor()
    if actor != null:
        var actor_point := _world_to_map(actor.global_position.x, actor.global_position.z)
        draw_circle(actor_point, 5.5, Color(1.0, 0.82, 0.16, 1.0))
    var target_value: Variant = _active_mission_target()
    if target_value is Vector3:
        var target: Vector3 = target_value
        var target_point := _world_to_map(target.x, target.z)
        draw_circle(target_point, 6.0, Color(1.0, 0.33, 0.12, 1.0), false, 2.0)
    if _route_distance_m > 1.0:
        draw_string(ThemeDB.fallback_font, Vector2(14.0, size.y - 11.0), "GPS · %.0f m" % _route_distance_m, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(0.72, 0.90, 1.0, 0.96))

func _panel_style() -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.035, 0.038, 0.048, 0.92)
    style.border_color = Color(1.0, 1.0, 1.0, 0.16)
    style.set_border_width_all(1)
    style.set_corner_radius_all(18)
    return style

func force_route_for_test(start_world: Vector2, target_world: Vector2) -> Array[Vector2]:
    _route_world_points = _compute_route(start_world, target_world)
    _route_distance_m = _polyline_length(_route_world_points)
    return _route_world_points.duplicate()

func route_snapshot_for_test() -> Dictionary:
    return {
        "graph_points": _graph_points.size(),
        "graph_nodes_with_neighbors": _graph_neighbors.size(),
        "route_points": _route_world_points.duplicate(),
        "distance_m": _route_distance_m,
    }
