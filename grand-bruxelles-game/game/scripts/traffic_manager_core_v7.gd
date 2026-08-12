extends "res://game/scripts/traffic_manager_core_v6.gd"

@export var max_delivery_vehicles: int = 2
@export var delivery_spawn_radius_m: float = 320.0
@export var delivery_refresh_interval_s: float = 2.0
@export var delivery_duration_min_s: float = 12.0
@export var delivery_duration_max_s: float = 24.0

const DELIVERY_VAN_SIZE := Vector3(2.02, 1.82, 5.15)
const DELIVERY_CLASSES := {
    "service": true,
    "tertiary": true,
    "secondary": true,
    "unclassified": true,
}

var _delivery_root: Node3D
var _delivery_rng := RandomNumberGenerator.new()
var _delivery_elapsed: float = 0.0
var _delivery_serial: int = 1


func _ready() -> void:
    _delivery_rng.seed = traffic_seed + 1777
    super._ready()
    _delivery_root = Node3D.new()
    _delivery_root.name = "DeliveryVehicles"
    add_child(_delivery_root)
    _replenish_deliveries()
    print("Grand Bruxelles deliveries: %d temporary curb stops" % get_delivery_vehicle_count())


func _process(delta: float) -> void:
    super._process(delta)
    expire_deliveries_at(float(Time.get_ticks_msec()) / 1000.0)
    _delivery_elapsed += delta
    if _delivery_elapsed < delivery_refresh_interval_s:
        return
    _delivery_elapsed = 0.0
    _despawn_far_deliveries()
    _replenish_deliveries()


func _replenish_deliveries() -> void:
    if _delivery_root == null or max_delivery_vehicles <= 0:
        return
    var anchor := _anchor_position()
    var eligible: Array[Dictionary] = []
    for candidate: Dictionary in _parking_candidates:
        if not DELIVERY_CLASSES.has(str(candidate.get("road_class", ""))):
            continue
        var position: Vector3 = candidate.get("position", Vector3.ZERO)
        if position.distance_to(anchor) > delivery_spawn_radius_m:
            continue
        var candidate_id := int(candidate.get("id", -1))
        if is_parking_candidate_available(candidate_id):
            eligible.append(candidate)

    if eligible.is_empty():
        return

    var attempts := 0
    while get_delivery_vehicle_count() < max_delivery_vehicles and attempts < eligible.size() * 3:
        attempts += 1
        var candidate: Dictionary = eligible[_delivery_rng.randi_range(0, eligible.size() - 1)]
        var candidate_id := int(candidate.get("id", -1))
        var owner := "delivery:%d" % _delivery_serial
        if not reserve_parking_candidate(candidate_id, owner):
            continue
        _spawn_delivery_vehicle(candidate, owner)
        eligible.erase(candidate)
        if eligible.is_empty():
            break


func _spawn_delivery_vehicle(candidate: Dictionary, reservation_owner: String) -> void:
    var van := StaticBody3D.new()
    van.name = "DeliveryVan_%03d" % _delivery_serial
    van.collision_layer = 1
    van.collision_mask = 1
    van.position = candidate.get("position", Vector3.ZERO)
    van.rotation.y = float(candidate.get("yaw", 0.0))
    van.set_meta("parking_candidate_id", int(candidate.get("id", -1)))
    van.set_meta("reservation_owner", reservation_owner)
    van.set_meta("simulated_delivery", true)
    van.set_meta("road_name", str(candidate.get("road_name", "")))
    van.set_meta("source_osm_id", int(candidate.get("osm_id", 0)))
    var min_duration := maxf(0.1, minf(delivery_duration_min_s, delivery_duration_max_s))
    var max_duration := maxf(min_duration, maxf(delivery_duration_min_s, delivery_duration_max_s))
    van.set_meta(
        "expires_at_s",
        float(Time.get_ticks_msec()) / 1000.0 + _delivery_rng.randf_range(min_duration, max_duration)
    )

    var collision := CollisionShape3D.new()
    collision.name = "CollisionShape3D"
    var shape := BoxShape3D.new()
    shape.size = DELIVERY_VAN_SIZE
    collision.shape = shape
    van.add_child(collision)

    var body := _box_mesh(Vector3(2.02, 1.42, 5.15), Color(0.78, 0.79, 0.77, 1.0), Vector3(0.0, 0.12, 0.0))
    body.name = "VanBody"
    van.add_child(body)
    var cab := _box_mesh(Vector3(1.88, 0.64, 1.48), Color(0.68, 0.70, 0.71, 1.0), Vector3(0.0, 0.78, -1.48))
    cab.name = "Cab"
    van.add_child(cab)

    _delivery_root.add_child(van)
    _delivery_serial += 1


func expire_deliveries_at(now_seconds: float) -> int:
    if _delivery_root == null:
        return 0
    var expired := 0
    for child: Node in _delivery_root.get_children():
        if child.is_queued_for_deletion():
            continue
        if now_seconds < float(child.get_meta("expires_at_s", INF)):
            continue
        _release_delivery_slot(child)
        child.queue_free()
        expired += 1
    return expired


func _despawn_far_deliveries() -> void:
    if _delivery_root == null:
        return
    var anchor := _anchor_position()
    var limit := maxf(delivery_spawn_radius_m * 1.7, 140.0)
    for child: Node in _delivery_root.get_children():
        if child is Node3D and not child.is_queued_for_deletion():
            if (child as Node3D).global_position.distance_to(anchor) > limit:
                _release_delivery_slot(child)
                child.queue_free()


func _release_delivery_slot(delivery: Node) -> void:
    var candidate_id := int(delivery.get_meta("parking_candidate_id", -1))
    var owner := str(delivery.get_meta("reservation_owner", ""))
    release_parking_candidate(candidate_id, owner)


func get_delivery_vehicle_count() -> int:
    if _delivery_root == null:
        return 0
    var count := 0
    for child: Node in _delivery_root.get_children():
        if not child.is_queued_for_deletion():
            count += 1
    return count
