extends Node

## Canonical traffic manager surface.
## This file intentionally has no dependency on traffic_manager_core_v*.

const ROOT_TRAFFIC := "TrafficVehicles"
const ROOT_CROSSINGS := "CrossingPedestrians"
const ROOT_PARKING := "ParkedVehicles"
const ROOT_DELIVERIES := "DeliveryVehicles"

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
var _reserved_parking: Dictionary = {}

var _traffic_root: Node3D
var _crossing_root: Node3D
var _parking_root: Node3D
var _delivery_root: Node3D

func _ready() -> void:
    _ensure_runtime_roots()

func _ensure_runtime_roots() -> void:
    _traffic_root = _ensure_root(ROOT_TRAFFIC)
    _crossing_root = _ensure_root(ROOT_CROSSINGS)
    _parking_root = _ensure_root(ROOT_PARKING)
    _delivery_root = _ensure_root(ROOT_DELIVERIES)

func _ensure_root(root_name: String) -> Node3D:
    var existing := get_node_or_null(root_name)
    if existing is Node3D:
        return existing as Node3D
    var created := Node3D.new()
    created.name = root_name
    add_child(created)
    return created

func configure_runtime_snapshot(snapshot: Dictionary) -> void:
    _route_count = maxi(0, int(snapshot.get("route_count", _route_count)))
    _graph_node_count = maxi(0, int(snapshot.get("graph_node_count", _graph_node_count)))
    _graph_edge_count = maxi(0, int(snapshot.get("graph_edge_count", _graph_edge_count)))
    _intersection_count = maxi(0, int(snapshot.get("intersection_count", _intersection_count)))
    _right_priority_count = clampi(int(snapshot.get("right_priority_count", _right_priority_count)), 0, _intersection_count)
    _traffic_control_count = maxi(0, int(snapshot.get("traffic_control_count", _traffic_control_count)))
    _signal_count = clampi(int(snapshot.get("signal_count", _signal_count)), 0, _traffic_control_count)
    _crossing_count = maxi(0, int(snapshot.get("crossing_count", _crossing_count)))
    _unsignalized_crossing_count = clampi(int(snapshot.get("unsignalized_crossing_count", _unsignalized_crossing_count)), 0, _crossing_count)
    _parking_candidate_count = maxi(0, int(snapshot.get("parking_candidate_count", _parking_candidate_count)))

func get_route_count() -> int:
    return _route_count

func get_graph_node_count() -> int:
    return _graph_node_count

func get_graph_edge_count() -> int:
    return _graph_edge_count

func get_intersection_count() -> int:
    return _intersection_count

func get_right_priority_count() -> int:
    return _right_priority_count

func get_traffic_control_count() -> int:
    return _traffic_control_count

func get_signal_count() -> int:
    return _signal_count

func get_crossing_count() -> int:
    return _crossing_count

func get_unsignalized_crossing_count() -> int:
    return _unsignalized_crossing_count

func get_active_crossing_pedestrian_count() -> int:
    return _live_child_count(_crossing_root)

func get_parking_candidate_count() -> int:
    return _parking_candidate_count

func get_parked_vehicle_count() -> int:
    return _live_child_count(_parking_root)

func get_delivery_vehicle_count() -> int:
    return _live_child_count(_delivery_root)

func get_reserved_parking_candidate_count() -> int:
    return _reserved_parking.size()

func get_active_vehicle_count() -> int:
    return _live_child_count(_traffic_root, true)

func get_wreck_count() -> int:
    if _traffic_root == null:
        return 0
    var count := 0
    for child: Node in _traffic_root.get_children():
        if child.is_queued_for_deletion():
            continue
        if bool(child.get_meta("traffic_wrecked", false)):
            count += 1
    return count

func cleanup_wrecks_at(now_seconds: float) -> int:
    if _traffic_root == null:
        return 0
    var cleared := 0
    for child: Node in _traffic_root.get_children():
        if child.is_queued_for_deletion() or not bool(child.get_meta("traffic_wrecked", false)):
            continue
        var wrecked_at := float(child.get_meta("traffic_wrecked_at_s", now_seconds))
        var clear_after := maxf(0.0, float(child.get_meta("traffic_wreck_clear_after_s", 18.0)))
        if now_seconds < wrecked_at + clear_after:
            continue
        child.queue_free()
        cleared += 1
    return cleared

func reserve_parking_candidate(candidate_id: int, owner: String) -> bool:
    if candidate_id < 0 or owner.is_empty():
        return false
    if _reserved_parking.has(candidate_id):
        return str(_reserved_parking[candidate_id]) == owner
    _reserved_parking[candidate_id] = owner
    return true

func release_parking_candidate(candidate_id: int, owner: String = "") -> bool:
    if not _reserved_parking.has(candidate_id):
        return false
    if not owner.is_empty() and str(_reserved_parking[candidate_id]) != owner:
        return false
    _reserved_parking.erase(candidate_id)
    return true

func _live_child_count(root_node: Node, exclude_wrecks: bool = false) -> int:
    if root_node == null:
        return 0
    var count := 0
    for child: Node in root_node.get_children():
        if child.is_queued_for_deletion():
            continue
        if exclude_wrecks and bool(child.get_meta("traffic_wrecked", false)):
            continue
        count += 1
    return count
