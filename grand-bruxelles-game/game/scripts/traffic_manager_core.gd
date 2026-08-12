extends Node

## Canonical traffic manager surface with no legacy core dependency.

@export var wreck_clear_delay_s: float = 18.0
@export var tow_arrival_delay_s: float = 7.0
@export var tow_service_duration_s: float = 5.0
@export var tow_spawn_distance_m: float = 6.2

const ROOT_TRAFFIC := "TrafficVehicles"
const ROOT_CROSSINGS := "CrossingPedestrians"
const ROOT_PARKING := "ParkedVehicles"
const ROOT_DELIVERIES := "DeliveryVehicles"
const ROOT_TOW := "TowServices"
const TOW_TRUCK_SIZE := Vector3(2.18, 1.86, 5.45)

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
var _tow_root: Node3D
var _tow_assignments: Dictionary = {}
var _tow_serial: int = 1

func _ready() -> void:
    _ensure_runtime_roots()

func _process(_delta: float) -> void:
    process_tow_services_at(float(Time.get_ticks_msec()) / 1000.0)

func _ensure_runtime_roots() -> void:
    _traffic_root = _ensure_root(ROOT_TRAFFIC)
    _crossing_root = _ensure_root(ROOT_CROSSINGS)
    _parking_root = _ensure_root(ROOT_PARKING)
    _delivery_root = _ensure_root(ROOT_DELIVERIES)
    _tow_root = _ensure_root(ROOT_TOW)

func _ensure_root(root_name: String) -> Node3D:
    var existing := get_node_or_null(root_name)
    if existing is Node3D:
        return existing as Node3D
    var created := Node3D.new()
    created.name = root_name
    add_child(created)
    return created

func _create_vehicle_node() -> CharacterBody3D:
    var vehicle := TrafficVehicleCore.new()
    if vehicle.has_signal("traffic_disabled"):
        vehicle.connect("traffic_disabled", Callable(self, "_on_traffic_vehicle_disabled"))
    return vehicle

func _on_traffic_vehicle_disabled(vehicle: Node) -> void:
    if not is_instance_valid(vehicle):
        return
    vehicle.set_meta("traffic_wrecked", true)
    if not vehicle.has_meta("traffic_wrecked_at_s"):
        vehicle.set_meta("traffic_wrecked_at_s", float(Time.get_ticks_msec()) / 1000.0)
    vehicle.set_meta("traffic_wreck_clear_after_s", maxf(1.0, wreck_clear_delay_s))
    _assign_tow_service(vehicle)

func _assign_tow_service(wreck: Node) -> void:
    if _tow_root == null or not is_instance_valid(wreck):
        return
    var wreck_id := wreck.get_instance_id()
    if _tow_assignments.has(wreck_id):
        return

    var wrecked_at := float(wreck.get_meta("traffic_wrecked_at_s", float(Time.get_ticks_msec()) / 1000.0))
    var arrival_delay := clampf(tow_arrival_delay_s, 0.0, maxf(0.0, wreck_clear_delay_s - 0.5))
    var service_duration := maxf(0.5, tow_service_duration_s)
    var complete_at := maxf(
        wrecked_at + arrival_delay + service_duration,
        wrecked_at + maxf(1.0, wreck_clear_delay_s)
    )
    wreck.set_meta("traffic_wreck_clear_after_s", complete_at - wrecked_at)

    var tow := _create_tow_truck(wreck)
    _tow_root.add_child(tow)
    _tow_assignments[wreck_id] = {
        "wreck": wreck,
        "tow": tow,
        "arrival_at_s": wrecked_at + arrival_delay,
        "complete_at_s": complete_at,
        "arrived": false,
    }
    _tow_serial += 1

func _create_tow_truck(wreck: Node) -> StaticBody3D:
    var tow := StaticBody3D.new()
    tow.name = "TowTruck_%03d" % _tow_serial
    tow.collision_layer = 1
    tow.collision_mask = 1
    tow.visible = false
    tow.set_meta("simulated_tow_service", true)
    tow.set_meta("wreck_instance_id", wreck.get_instance_id())

    if wreck is Node3D:
        var wreck_node := wreck as Node3D
        var forward := -wreck_node.global_transform.basis.z
        forward.y = 0.0
        if forward.length_squared() <= 0.001:
            forward = Vector3.FORWARD
        else:
            forward = forward.normalized()
        tow.global_position = wreck_node.global_position + forward * tow_spawn_distance_m
        tow.rotation.y = wreck_node.rotation.y

    var collision := CollisionShape3D.new()
    collision.name = "CollisionShape3D"
    var shape := BoxShape3D.new()
    shape.size = TOW_TRUCK_SIZE
    collision.shape = shape
    collision.disabled = true
    tow.add_child(collision)

    var body := _box_mesh(Vector3(2.18, 1.18, 5.45), Color(0.86, 0.70, 0.16, 1.0), Vector3(0.0, 0.08, 0.0))
    body.name = "TowBody"
    tow.add_child(body)
    var cab := _box_mesh(Vector3(2.02, 0.82, 1.72), Color(0.90, 0.75, 0.18, 1.0), Vector3(0.0, 0.76, -1.65))
    cab.name = "TowCab"
    tow.add_child(cab)
    var bed := _box_mesh(Vector3(1.94, 0.20, 2.72), Color(0.20, 0.22, 0.24, 1.0), Vector3(0.0, 0.66, 0.92))
    bed.name = "TowBed"
    tow.add_child(bed)
    return tow

func _box_mesh(size: Vector3, color: Color, offset: Vector3) -> MeshInstance3D:
    var mesh_instance := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    mesh.material = material
    mesh_instance.mesh = mesh
    mesh_instance.position = offset
    return mesh_instance

func process_tow_services_at(now_seconds: float) -> int:
    var completed := 0
    for raw_wreck_id: Variant in _tow_assignments.keys():
        var wreck_id := int(raw_wreck_id)
        var assignment: Dictionary = _tow_assignments.get(wreck_id, {})
        var wreck: Node = assignment.get("wreck", null)
        var tow: Node = assignment.get("tow", null)

        if wreck == null or not is_instance_valid(wreck) or wreck.is_queued_for_deletion():
            _remove_tow_assignment(wreck_id)
            continue

        if not bool(assignment.get("arrived", false)) and now_seconds >= float(assignment.get("arrival_at_s", INF)):
            assignment["arrived"] = true
            _tow_assignments[wreck_id] = assignment
            if tow != null and is_instance_valid(tow):
                tow.visible = true
                var collision := tow.get_node_or_null("CollisionShape3D") as CollisionShape3D
                if collision != null:
                    collision.disabled = false

        if now_seconds < float(assignment.get("complete_at_s", INF)):
            continue

        if tow != null and is_instance_valid(tow):
            tow.queue_free()
        wreck.queue_free()
        _tow_assignments.erase(wreck_id)
        completed += 1
    return completed

func _remove_tow_assignment(wreck_id: int) -> void:
    if not _tow_assignments.has(wreck_id):
        return
    var assignment: Dictionary = _tow_assignments[wreck_id]
    var tow: Node = assignment.get("tow", null)
    if tow != null and is_instance_valid(tow):
        tow.queue_free()
    _tow_assignments.erase(wreck_id)

func get_tow_service_count() -> int:
    return _tow_assignments.size()

func get_visible_tow_service_count() -> int:
    var count := 0
    for assignment_variant: Variant in _tow_assignments.values():
        if typeof(assignment_variant) != TYPE_DICTIONARY:
            continue
        var assignment: Dictionary = assignment_variant
        var tow: Node = assignment.get("tow", null)
        if tow != null and is_instance_valid(tow) and tow.visible and not tow.is_queued_for_deletion():
            count += 1
    return count

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
        var wreck_id := child.get_instance_id()
        if _tow_assignments.has(wreck_id):
            var assignment: Dictionary = _tow_assignments[wreck_id]
            if now_seconds < float(assignment.get("complete_at_s", INF)):
                continue
            var tow: Node = assignment.get("tow", null)
            if tow != null and is_instance_valid(tow):
                tow.queue_free()
            _tow_assignments.erase(wreck_id)
        else:
            var wrecked_at := float(child.get_meta("traffic_wrecked_at_s", now_seconds))
            var clear_after := maxf(0.0, float(child.get_meta("traffic_wreck_clear_after_s", wreck_clear_delay_s)))
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
