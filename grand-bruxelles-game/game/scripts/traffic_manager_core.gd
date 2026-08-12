extends Node3D

@export_file("*.json") var fallback_data_path: String = "res://data/osm/vertical_slice_01.game.json"
@export var wreck_clear_delay_s: float = 18.0
@export var max_wrecks_before_fast_clear: int = 3

const ROAD_GRAPH_SCRIPT := preload("res://game/scripts/traffic_road_graph.gd")
const TRAFFIC_CONTROL_SCRIPT := preload("res://game/scripts/traffic_control_system.gd")

var _roads: Array[Dictionary] = []
var _traffic_controls: Array = []
var _road_graph: RefCounted = null
var _control_system: RefCounted = null
var _route_count: int = 0
var _graph_node_count: int = 0
var _graph_edge_count: int = 0
var _intersection_count: int = 0
var _right_priority_count: int = 0
var _traffic_control_count: int = 0
var _signal_count: int = 0
var _crossing_count: int = 0
var _unsignalized_crossing_count: int = 0
var _parking_candidate_count: int = 0
var _reserved_parking_candidate_ids: Dictionary = {}
var _traffic_root: Node3D
var _crossing_root: Node3D
var _parking_root: Node3D
var _delivery_root: Node3D
var _tow_root: Node3D

func _ready() -> void:
    _ensure_runtime_roots()

func initialize_runtime() -> bool:
    _ensure_runtime_roots()
    _road_graph = ROAD_GRAPH_SCRIPT.new()
    _control_system = TRAFFIC_CONTROL_SCRIPT.new()
    _roads.clear()
    _traffic_controls.clear()
    var payload := _read_json_dictionary(fallback_data_path)
    if payload.is_empty():
        return false
    _append_roads(payload.get("roads", []))
    _append_controls(payload.get("traffic_controls", []))
    _road_graph.call("rebuild", _roads)
    _control_system.call("rebuild", _traffic_controls)
    _route_count = _roads.size()
    _graph_node_count = int(_road_graph.call("get_node_count"))
    _graph_edge_count = int(_road_graph.call("get_edge_count"))
    _intersection_count = int(_road_graph.call("get_intersection_count"))
    _traffic_control_count = int(_control_system.call("get_control_count"))
    _signal_count = int(_control_system.call("get_signal_count"))
    _crossing_count = _count_controls_by_kind("crossing")
    _unsignalized_crossing_count = _crossing_count
    return _route_count > 0 and _graph_edge_count > 0

func _read_json_dictionary(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    return parsed as Dictionary

func _append_roads(raw_roads: Array) -> void:
    for raw in raw_roads:
        if typeof(raw) != TYPE_DICTIONARY:
            continue
        var road: Dictionary = raw
        if not bool(road.get("drivable", false)):
            continue
        if _road_is_access_restricted(road):
            continue
        var points: Array = road.get("points", [])
        if points.size() < 2:
            continue
        _roads.append(road)

func _append_controls(raw_controls: Array) -> void:
    for raw in raw_controls:
        if typeof(raw) == TYPE_DICTIONARY:
            _traffic_controls.append(raw)

func _road_is_access_restricted(road: Dictionary) -> bool:
    var access := str(road.get("access", "")).to_lower()
    var motor_vehicle := str(road.get("motor_vehicle", "")).to_lower()
    return access in ["no", "private"] or motor_vehicle in ["no", "private"]

func _count_controls_by_kind(kind: String) -> int:
    var count := 0
    for raw in _traffic_controls:
        if raw is Dictionary and str(raw.get("kind", "")) == kind:
            count += 1
    return count

func get_candidate_edge_ids(anchor: Vector3, radius_m: float) -> Array[int]:
    if _road_graph == null:
        return []
    return _road_graph.call("find_candidate_edge_ids", anchor, radius_m)

func build_random_route(start_edge_id: int, seed_value: int = 1, target_length_m: float = 320.0, max_length_m: float = 720.0, max_edges: int = 28) -> Dictionary:
    if _road_graph == null:
        return {}
    var rng := RandomNumberGenerator.new()
    rng.seed = seed_value
    var edge_ids: Array = _road_graph.call("build_random_walk", start_edge_id, rng, target_length_m, max_length_m, max_edges)
    if edge_ids.is_empty():
        return {}
    return _route_bundle_from_edges(edge_ids)

func _route_bundle_from_edges(edge_ids: Array) -> Dictionary:
    var points := PackedVector3Array()
    var speed_limits := PackedFloat32Array()
    var first_name := ""
    var first_osm_id := 0
    for raw_edge_id in edge_ids:
        var edge: Dictionary = _road_graph.call("get_edge", int(raw_edge_id))
        if edge.is_empty():
            continue
        var road: Dictionary = edge.get("road", {})
        var start: Vector3 = edge["from"]
        var finish: Vector3 = edge["to"]
        var direction := finish - start
        direction.y = 0.0
        if direction.length_squared() <= 0.001:
            continue
        direction = direction.normalized()
        var right := Vector3(-direction.z, 0.0, direction.x)
        var lane_offset := _lane_offset_for_road(road)
        var shifted_start := start + right * lane_offset
        var shifted_finish := finish + right * lane_offset
        var speed_limit := _speed_limit_for_road(road)
        if first_osm_id == 0:
            first_osm_id = int(edge.get("osm_id", 0))
            first_name = str(road.get("name", ""))
        if points.is_empty():
            points.append(shifted_start)
            speed_limits.append(speed_limit)
        elif points[points.size() - 1].distance_to(shifted_start) > 0.20:
            points.append(shifted_start)
            speed_limits.append(speed_limit)
        points.append(shifted_finish)
        speed_limits.append(speed_limit)
    var route_controls: Array = []
    if _control_system != null:
        route_controls = _control_system.call("controls_for_route", points)
    return {"points": points, "speed_limits_kmh": speed_limits, "road_name": first_name, "osm_id": first_osm_id, "edge_count": edge_ids.size(), "controls": route_controls}

func _lane_offset_for_road(road: Dictionary) -> float:
    var width := maxf(3.0, _safe_float(road.get("width", 5.6), 5.6))
    var lanes := _safe_nonnegative_int(road.get("lanes", null))
    var oneway := _normalized_oneway(road)
    if oneway != 0:
        if lanes >= 2:
            return clampf(width * 0.18, 0.7, 1.65)
        return clampf(width * 0.08, 0.25, 0.65)
    return clampf(width * 0.23, 1.0, 2.05)

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

func _normalized_oneway(road: Dictionary) -> int:
    var raw: Variant = road.get("oneway", 0)
    if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT:
        var value := int(raw)
        return -1 if value < 0 else (1 if value > 0 else 0)
    var text := str(raw).strip_edges().to_lower()
    if text == "-1": return -1
    if text in ["1", "yes", "true"]: return 1
    if str(road.get("junction", "")).to_lower() == "roundabout": return 1
    return 0

func _speed_limit_for_road(road: Dictionary) -> float:
    var raw_limit: Variant = road.get("maxspeed_kmh", null)
    if raw_limit != null and (typeof(raw_limit) == TYPE_INT or typeof(raw_limit) == TYPE_FLOAT):
        var value := float(raw_limit)
        if value > 0.0:
            return clampf(value, 5.0, 90.0)
    var road_class := str(road.get("class", ""))
    if road_class in ["living_street", "service"]:
        return 20.0
    return 30.0

func _ensure_runtime_roots() -> void:
    _traffic_root = _ensure_root("TrafficVehicles")
    _crossing_root = _ensure_root("CrossingPedestrians")
    _parking_root = _ensure_root("ParkedVehicles")
    _delivery_root = _ensure_root("DeliveryVehicles")
    _tow_root = _ensure_root("TowServices")

func _ensure_root(root_name: String) -> Node3D:
    var existing := get_node_or_null(root_name) as Node3D
    if existing != null:
        return existing
    var root := Node3D.new()
    root.name = root_name
    add_child(root)
    return root

func configure_topology(route_count: int, graph_nodes: int, graph_edges: int, intersection_count: int, right_priority_count: int, control_count: int, signal_count: int, crossing_count: int, unsignalized_crossing_count: int, parking_candidates: int) -> void:
    _route_count = maxi(0, route_count)
    _graph_node_count = maxi(0, graph_nodes)
    _graph_edge_count = maxi(0, graph_edges)
    _intersection_count = maxi(0, intersection_count)
    _right_priority_count = maxi(0, right_priority_count)
    _traffic_control_count = maxi(0, control_count)
    _signal_count = maxi(0, signal_count)
    _crossing_count = maxi(0, crossing_count)
    _unsignalized_crossing_count = maxi(0, unsignalized_crossing_count)
    _parking_candidate_count = maxi(0, parking_candidates)

func register_wreck(vehicle: Node, now_seconds: float = -1.0) -> bool:
    if vehicle == null or not is_instance_valid(vehicle): return false
    if now_seconds < 0.0: now_seconds = float(Time.get_ticks_msec()) / 1000.0
    vehicle.set_meta("traffic_wrecked", true)
    vehicle.set_meta("traffic_wrecked_at_s", now_seconds)
    vehicle.set_meta("traffic_wreck_clear_after_s", _effective_wreck_delay())
    if not vehicle.is_in_group("traffic_wreck"): vehicle.add_to_group("traffic_wreck")
    return true

func _effective_wreck_delay() -> float:
    if get_wreck_count() >= max_wrecks_before_fast_clear: return maxf(4.0, wreck_clear_delay_s * 0.45)
    return maxf(1.0, wreck_clear_delay_s)

func cleanup_wrecks_at(now_seconds: float) -> int:
    _ensure_runtime_roots()
    var cleared := 0
    for child in _traffic_root.get_children():
        if child.is_queued_for_deletion() or not bool(child.get_meta("traffic_wrecked", false)): continue
        var wrecked_at := float(child.get_meta("traffic_wrecked_at_s", now_seconds))
        var delay := float(child.get_meta("traffic_wreck_clear_after_s", wreck_clear_delay_s))
        if now_seconds < wrecked_at + maxf(0.0, delay): continue
        child.queue_free()
        cleared += 1
    return cleared

func process_tow_services_at(now_seconds: float) -> int:
    _ensure_runtime_roots()
    var completed := 0
    for tow in _tow_root.get_children():
        if tow.is_queued_for_deletion() or now_seconds < float(tow.get_meta("tow_complete_at_s", INF)): continue
        var wreck_id := int(tow.get_meta("wreck_instance_id", 0))
        if wreck_id > 0:
            var target := instance_from_id(wreck_id)
            if target != null and is_instance_valid(target): target.queue_free()
        tow.queue_free()
        completed += 1
    return completed

func register_tow_service(tow_node: Node3D, wreck: Node, complete_at_s: float) -> bool:
    if tow_node == null or wreck == null or not is_instance_valid(wreck): return false
    _ensure_runtime_roots()
    if tow_node.get_parent() != null: tow_node.reparent(_tow_root)
    else: _tow_root.add_child(tow_node)
    tow_node.set_meta("wreck_instance_id", wreck.get_instance_id())
    tow_node.set_meta("tow_complete_at_s", complete_at_s)
    return true

func reserve_parking_candidate(candidate_id: int, owner: String) -> bool:
    if candidate_id < 0 or owner.is_empty() or _reserved_parking_candidate_ids.has(candidate_id): return false
    _reserved_parking_candidate_ids[candidate_id] = owner
    return true
func release_parking_candidate(candidate_id: int, owner: String = "") -> void:
    if not _reserved_parking_candidate_ids.has(candidate_id): return
    if not owner.is_empty() and str(_reserved_parking_candidate_ids[candidate_id]) != owner: return
    _reserved_parking_candidate_ids.erase(candidate_id)

func get_route_count() -> int: return _route_count
func get_graph_node_count() -> int: return _graph_node_count
func get_graph_edge_count() -> int: return _graph_edge_count
func get_intersection_count() -> int: return _intersection_count
func get_right_priority_count() -> int: return _right_priority_count
func get_traffic_control_count() -> int: return _traffic_control_count
func get_signal_count() -> int: return _signal_count
func get_crossing_count() -> int: return _crossing_count
func get_unsignalized_crossing_count() -> int: return _unsignalized_crossing_count
func get_parking_candidate_count() -> int: return _parking_candidate_count
func get_active_crossing_pedestrian_count() -> int: _ensure_runtime_roots(); return _live_child_count(_crossing_root)
func get_parked_vehicle_count() -> int: _ensure_runtime_roots(); return _live_child_count(_parking_root)
func get_delivery_vehicle_count() -> int: _ensure_runtime_roots(); return _live_child_count(_delivery_root)
func get_reserved_parking_candidate_count() -> int: return _reserved_parking_candidate_ids.size()
func get_active_vehicle_count() -> int:
    _ensure_runtime_roots()
    var count := 0
    for child in _traffic_root.get_children():
        if not child.is_queued_for_deletion() and not bool(child.get_meta("traffic_wrecked", false)): count += 1
    return count
func get_wreck_count() -> int:
    _ensure_runtime_roots()
    var count := 0
    for child in _traffic_root.get_children():
        if not child.is_queued_for_deletion() and bool(child.get_meta("traffic_wrecked", false)): count += 1
    return count
func get_tow_service_count() -> int: _ensure_runtime_roots(); return _live_child_count(_tow_root)
func get_visible_tow_service_count() -> int:
    _ensure_runtime_roots()
    var count := 0
    for child in _tow_root.get_children():
        if child is Node3D and not child.is_queued_for_deletion() and (child as Node3D).visible: count += 1
    return count
func _live_child_count(root: Node) -> int:
    var count := 0
    for child in root.get_children():
        if not child.is_queued_for_deletion(): count += 1
    return count
