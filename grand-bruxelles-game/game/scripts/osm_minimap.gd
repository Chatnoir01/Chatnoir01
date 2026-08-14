extends Control

@export_file("*.json") var data_path: String = "res://data/osm/vertical_slice_01.game.json"
@export var padding: float = 12.0
@export var route_refresh_interval_s: float = 0.65
@export var route_rebuild_distance_m: float = 18.0

@onready var player: CharacterBody3D = get_node("../Player")
@onready var mission: Node = get_node("../MissionDriveToCenter")
@onready var return_mission: Node = get_node("../MissionReturnToBourse")

var _roads: Array = []
var _bounds: Vector4 = Vector4(-900.0, -900.0, 350.0, 950.0)
var _major_color: Color = Color(0.75, 0.75, 0.79, 0.72)
var _minor_color: Color = Color(0.43, 0.44, 0.48, 0.62)
var _background_color: Color = Color(0.035, 0.038, 0.048, 0.92)
var _player_color: Color = Color(1.0, 0.82, 0.16, 1.0)
var _checkpoint_color: Color = Color(1.0, 0.33, 0.12, 1.0)
var _route_color: Color = Color(0.18, 0.74, 1.0, 0.94)

# This graph is built only from committed OSM road polyline vertices. It is an
# indicative mission guide, not a claim about legal turn restrictions, one-way
# direction or live traffic routing.
var _graph_points: Dictionary = {} # String -> Vector2
var _graph_neighbors: Dictionary = {} # String -> Dictionary(String -> distance)
var _route_world_points: Array[Vector2] = []
var _route_distance_m: float = 0.0
var _route_elapsed_s: float = 0.0
var _last_route_actor := Vector2(INF, INF)
var _last_route_target := Vector2(INF, INF)

const MISSION_TARGETS: Array[Vector3] = [
    Vector3(-272.04, 0.0, -217.07),
    Vector3(81.54, 0.0, -664.58),
    Vector3(319.01, 0.0, -535.20),
]
const RETURN_BOURSE := Vector3(81.54, 0.0, -664.58)
const RETURN_ACTIVE_STATE := 2
const GRAPH_KEY_SCALE := 1000.0


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _load_map_data()
    _build_road_graph()
    _refresh_route(true)
    queue_redraw()


func _process(delta: float) -> void:
    _route_elapsed_s += maxf(0.0, delta)
    if _route_elapsed_s >= maxf(0.1, route_refresh_interval_s):
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
    _roads = data.get("roads", [])
    var raw_bounds: Array = data.get("bounds_m", [])
    if raw_bounds.size() == 4:
        _bounds = Vector4(
            float(raw_bounds[0]),
            float(raw_bounds[1]),
            float(raw_bounds[2]),
            float(raw_bounds[3])
        )


func _build_road_graph() -> void:
    _graph_points.clear()
    _graph_neighbors.clear()
    for road_variant: Variant in _roads:
        if typeof(road_variant) != TYPE_DICTIONARY:
            continue
        var road: Dictionary = road_variant
        if not bool(road.get("drivable", false)):
            continue
        var points: Array = road.get("points", [])
        if points.size() < 2:
            continue
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
                var distance := previous_point.distance_to(point)
                if distance > 0.001:
                    var previous_neighbors: Dictionary = _graph_neighbors.get(previous_key, {})
                    previous_neighbors[key] = minf(float(previous_neighbors.get(key, INF)), distance)
                    _graph_neighbors[previous_key] = previous_neighbors
                    var current_neighbors: Dictionary = _graph_neighbors.get(key, {})
                    current_neighbors[previous_key] = minf(float(current_neighbors.get(previous_key, INF)), distance)
                    _graph_neighbors[key] = current_neighbors
            previous_key = key
            previous_point = point


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
    var actor := _active_actor()
    var target_value: Variant = _active_mission_target()
    if actor == null or not target_value is Vector3 or _graph_points.is_empty():
        _route_world_points.clear()
        _route_distance_m = 0.0
        _last_route_target = Vector2(INF, INF)
        return

    var actor_point := Vector2(actor.global_position.x, actor.global_position.z)
    var target3 := target_value as Vector3
    var target_point := Vector2(target3.x, target3.z)
    var actor_moved := actor_point.distance_to(_last_route_actor) >= maxf(1.0, route_rebuild_distance_m)
    var target_changed := target_point.distance_to(_last_route_target) >= 0.5
    if not force and not actor_moved and not target_changed:
        return

    _last_route_actor = actor_point
    _last_route_target = target_point
    _route_world_points = _compute_route(actor_point, target_point)
    _route_distance_m = _polyline_length(_route_world_points)


func _nearest_graph_key(point: Vector2) -> String:
    var best_key := ""
    var best_distance_sq := INF
    for key_variant: Variant in _graph_points.keys():
        var key := str(key_variant)
        var candidate_value: Variant = _graph_points[key]
        if not candidate_value is Vector2:
            continue
        var distance_sq := point.distance_squared_to(candidate_value as Vector2)
        if distance_sq < best_distance_sq:
            best_distance_sq = distance_sq
            best_key = key
    return best_key


func _compute_route(start_world: Vector2, target_world: Vector2) -> Array[Vector2]:
    var result: Array[Vector2] = []
    var start_key := _nearest_graph_key(start_world)
    var target_key := _nearest_graph_key(target_world)
    if start_key.is_empty() or target_key.is_empty():
        return result

    var frontier: Array[String] = [start_key]
    var distance: Dictionary = {start_key: 0.0}
    var previous: Dictionary = {}
    var visited: Dictionary = {}

    while not frontier.is_empty():
        var best_index := 0
        var best_key := frontier[0]
        var best_cost := float(distance.get(best_key, INF))
        for index in range(1, frontier.size()):
            var candidate_key := frontier[index]
            var candidate_cost := float(distance.get(candidate_key, INF))
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

        var neighbors_value: Variant = _graph_neighbors.get(best_key, {})
        if not neighbors_value is Dictionary:
            continue
        var neighbors: Dictionary = neighbors_value
        for neighbor_variant: Variant in neighbors.keys():
            var neighbor := str(neighbor_variant)
            if visited.has(neighbor):
                continue
            var new_cost := best_cost + float(neighbors[neighbor])
            if new_cost < float(distance.get(neighbor, INF)):
                distance[neighbor] = new_cost
                previous[neighbor] = best_key
                if not frontier.has(neighbor):
                    frontier.append(neighbor)

    if start_key != target_key and not previous.has(target_key):
        return result

    var reverse_keys: Array[String] = [target_key]
    var cursor := target_key
    while cursor != start_key:
        if not previous.has(cursor):
            return []
        cursor = str(previous[cursor])
        reverse_keys.append(cursor)
    reverse_keys.reverse()

    result.append(start_world)
    for key: String in reverse_keys:
        var point_value: Variant = _graph_points.get(key, null)
        if point_value is Vector2:
            var point := point_value as Vector2
            if result.is_empty() or point.distance_to(result[result.size() - 1]) > 0.25:
                result.append(point)
    if result.is_empty() or target_world.distance_to(result[result.size() - 1]) > 0.25:
        result.append(target_world)
    return _simplify_route(result)


func _simplify_route(points: Array[Vector2]) -> Array[Vector2]:
    if points.size() <= 2:
        return points
    var simplified: Array[Vector2] = [points[0]]
    for index in range(1, points.size() - 1):
        var previous_point := simplified[simplified.size() - 1]
        var current := points[index]
        var next := points[index + 1]
        var a := (current - previous_point).normalized()
        var b := (next - current).normalized()
        if a.dot(b) < 0.997:
            simplified.append(current)
    simplified.append(points[points.size() - 1])
    return simplified


func _polyline_length(points: Array[Vector2]) -> float:
    var total := 0.0
    for index in range(points.size() - 1):
        total += points[index].distance_to(points[index + 1])
    return total


func _world_to_map(world_x: float, world_z: float) -> Vector2:
    var usable_width: float = maxf(size.x - padding * 2.0, 1.0)
    var usable_height: float = maxf(size.y - padding * 2.0, 1.0)
    var span_x: float = maxf(_bounds.z - _bounds.x, 1.0)
    var span_z: float = maxf(_bounds.w - _bounds.y, 1.0)
    var normalized_x: float = (world_x - _bounds.x) / span_x
    var normalized_z: float = (world_z - _bounds.y) / span_z
    return Vector2(
        padding + normalized_x * usable_width,
        padding + normalized_z * usable_height
    )


func _draw() -> void:
    draw_style_box(_panel_style(), Rect2(Vector2.ZERO, size))

    for road_variant: Variant in _roads:
        var road: Dictionary = road_variant
        var points: Array = road.get("points", [])
        if points.size() < 2:
            continue
        var road_class: String = str(road.get("class", ""))
        var is_major: bool = road_class in ["primary", "secondary", "tertiary"]
        var road_color: Color = _major_color if is_major else _minor_color
        var road_width: float = 1.8 if is_major else 1.0
        for index: int in range(points.size() - 1):
            var start_point: Variant = points[index]
            var end_point: Variant = points[index + 1]
            draw_line(
                _world_to_map(float(start_point[0]), float(start_point[1])),
                _world_to_map(float(end_point[0]), float(end_point[1])),
                road_color,
                road_width,
                true
            )

    if _route_world_points.size() >= 2:
        for index in range(_route_world_points.size() - 1):
            var start_route := _route_world_points[index]
            var end_route := _route_world_points[index + 1]
            draw_line(
                _world_to_map(start_route.x, start_route.y),
                _world_to_map(end_route.x, end_route.y),
                Color(0.01, 0.02, 0.03, 0.78),
                6.0,
                true
            )
            draw_line(
                _world_to_map(start_route.x, start_route.y),
                _world_to_map(end_route.x, end_route.y),
                _route_color,
                3.2,
                true
            )

    var actor := _active_actor()
    if actor != null:
        var actor_point: Vector2 = _world_to_map(actor.global_position.x, actor.global_position.z)
        draw_circle(actor_point, 5.5, _player_color)
        draw_circle(actor_point, 8.5, Color(1.0, 0.82, 0.16, 0.25), false, 1.5)

    var target_value: Variant = _active_mission_target()
    if target_value is Vector3:
        var target := target_value as Vector3
        var checkpoint_point: Vector2 = _world_to_map(target.x, target.z)
        draw_circle(checkpoint_point, 6.0, _checkpoint_color, false, 2.0)
        draw_circle(checkpoint_point, 2.3, _checkpoint_color)

    if _route_distance_m > 1.0:
        var distance_text := "GPS · %.0f m" % _route_distance_m
        draw_string(
            ThemeDB.fallback_font,
            Vector2(14.0, size.y - 11.0),
            distance_text,
            HORIZONTAL_ALIGNMENT_LEFT,
            -1.0,
            13,
            Color(0.72, 0.90, 1.0, 0.96)
        )


func _panel_style() -> StyleBoxFlat:
    var style: StyleBoxFlat = StyleBoxFlat.new()
    style.bg_color = _background_color
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
