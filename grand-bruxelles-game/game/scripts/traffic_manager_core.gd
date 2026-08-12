extends Node3D

@export var wreck_clear_delay_s: float = 18.0
@export var max_wrecks_before_fast_clear: int = 3

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
    if vehicle == null or not is_instance_valid(vehicle):
        return false
    if now_seconds < 0.0:
        now_seconds = float(Time.get_ticks_msec()) / 1000.0
    vehicle.set_meta("traffic_wrecked", true)
    vehicle.set_meta("traffic_wrecked_at_s", now_seconds)
    vehicle.set_meta("traffic_wreck_clear_after_s", _effective_wreck_delay())
    if not vehicle.is_in_group("traffic_wreck"):
        vehicle.add_to_group("traffic_wreck")
    return true

func _effective_wreck_delay() -> float:
    if get_wreck_count() >= max_wrecks_before_fast_clear:
        return maxf(4.0, wreck_clear_delay_s * 0.45)
    return maxf(1.0, wreck_clear_delay_s)

func cleanup_wrecks_at(now_seconds: float) -> int:
    _ensure_runtime_roots()
    var cleared := 0
    for child in _traffic_root.get_children():
        if child.is_queued_for_deletion() or not bool(child.get_meta("traffic_wrecked", false)):
            continue
        var wrecked_at := float(child.get_meta("traffic_wrecked_at_s", now_seconds))
        var delay := float(child.get_meta("traffic_wreck_clear_after_s", wreck_clear_delay_s))
        if now_seconds < wrecked_at + maxf(0.0, delay):
            continue
        child.queue_free()
        cleared += 1
    return cleared

func process_tow_services_at(now_seconds: float) -> int:
    _ensure_runtime_roots()
    var completed := 0
    for tow in _tow_root.get_children():
        if tow.is_queued_for_deletion():
            continue
        var complete_at := float(tow.get_meta("tow_complete_at_s", INF))
        if now_seconds < complete_at:
            continue
        var wreck_id := int(tow.get_meta("wreck_instance_id", 0))
        if wreck_id > 0:
            var target := instance_from_id(wreck_id)
            if target != null and is_instance_valid(target):
                target.queue_free()
        tow.queue_free()
        completed += 1
    return completed

func register_tow_service(tow_node: Node3D, wreck: Node, complete_at_s: float) -> bool:
    if tow_node == null or wreck == null or not is_instance_valid(wreck):
        return false
    _ensure_runtime_roots()
    if tow_node.get_parent() != null:
        tow_node.reparent(_tow_root)
    else:
        _tow_root.add_child(tow_node)
    tow_node.set_meta("wreck_instance_id", wreck.get_instance_id())
    tow_node.set_meta("tow_complete_at_s", complete_at_s)
    return true

func reserve_parking_candidate(candidate_id: int, owner: String) -> bool:
    if candidate_id < 0 or owner.is_empty() or _reserved_parking_candidate_ids.has(candidate_id):
        return false
    _reserved_parking_candidate_ids[candidate_id] = owner
    return true

func release_parking_candidate(candidate_id: int, owner: String = "") -> void:
    if not _reserved_parking_candidate_ids.has(candidate_id):
        return
    if not owner.is_empty() and str(_reserved_parking_candidate_ids[candidate_id]) != owner:
        return
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

func get_active_crossing_pedestrian_count() -> int:
    _ensure_runtime_roots()
    return _live_child_count(_crossing_root)

func get_parked_vehicle_count() -> int:
    _ensure_runtime_roots()
    return _live_child_count(_parking_root)

func get_delivery_vehicle_count() -> int:
    _ensure_runtime_roots()
    return _live_child_count(_delivery_root)

func get_reserved_parking_candidate_count() -> int:
    return _reserved_parking_candidate_ids.size()

func get_active_vehicle_count() -> int:
    _ensure_runtime_roots()
    var count := 0
    for child in _traffic_root.get_children():
        if not child.is_queued_for_deletion() and not bool(child.get_meta("traffic_wrecked", false)):
            count += 1
    return count

func get_wreck_count() -> int:
    _ensure_runtime_roots()
    var count := 0
    for child in _traffic_root.get_children():
        if not child.is_queued_for_deletion() and bool(child.get_meta("traffic_wrecked", false)):
            count += 1
    return count

func get_tow_service_count() -> int:
    _ensure_runtime_roots()
    return _live_child_count(_tow_root)

func get_visible_tow_service_count() -> int:
    _ensure_runtime_roots()
    var count := 0
    for child in _tow_root.get_children():
        if child is Node3D and not child.is_queued_for_deletion() and (child as Node3D).visible:
            count += 1
    return count

func _live_child_count(root: Node) -> int:
    var count := 0
    for child in root.get_children():
        if not child.is_queued_for_deletion():
            count += 1
    return count
