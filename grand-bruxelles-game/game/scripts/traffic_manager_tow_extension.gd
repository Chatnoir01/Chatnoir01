extends "res://game/scripts/traffic_manager_core.gd"
class_name TrafficManagerTowExtension

@export var tow_arrival_delay_s: float = 7.0
@export var tow_service_duration_s: float = 5.0
@export var tow_spawn_distance_m: float = 6.2

const TOW_TRUCK_SIZE := Vector3(2.18, 1.86, 5.45)

var _tow_root: Node3D = null
var _tow_assignments: Dictionary = {}
var _tow_serial: int = 1

func _ready() -> void:
    super._ready()
    _tow_root = get_node_or_null("TowServices") as Node3D
    if _tow_root == null:
        _tow_root = Node3D.new()
        _tow_root.name = "TowServices"
        add_child(_tow_root)

func _process(delta: float) -> void:
    super._process(delta)
    process_tow_services_at(float(Time.get_ticks_msec()) / 1000.0)

func _on_traffic_vehicle_disabled(vehicle: Node) -> void:
    super._on_traffic_vehicle_disabled(vehicle)
    if not is_instance_valid(vehicle):
        return
    if _tow_root == null:
        _tow_root = get_node_or_null("TowServices") as Node3D
    if _tow_root == null:
        return
    _assign_tow_service(vehicle)

func _assign_tow_service(wreck: Node) -> void:
    var wreck_id := wreck.get_instance_id()
    if _tow_assignments.has(wreck_id):
        return
    var wrecked_at := float(wreck.get_meta("traffic_wrecked_at_s", float(Time.get_ticks_msec()) / 1000.0))
    var arrival_delay := clampf(tow_arrival_delay_s, 0.0, maxf(0.0, wreck_clear_delay_s - 0.5))
    var service_duration := maxf(0.5, tow_service_duration_s)
    var complete_at := maxf(wrecked_at + arrival_delay + service_duration, wrecked_at + maxf(1.0, wreck_clear_delay_s))
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
    if completed > 0 and auto_spawn_runtime:
        call_deferred("_replenish_traffic")
    return completed

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
            var delay := float(child.get_meta("traffic_wreck_clear_after_s", wreck_clear_delay_s))
            if now_seconds < wrecked_at + maxf(0.0, delay):
                continue
        child.queue_free()
        cleared += 1
    if cleared > 0 and auto_spawn_runtime:
        call_deferred("_replenish_traffic")
    return cleared

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
