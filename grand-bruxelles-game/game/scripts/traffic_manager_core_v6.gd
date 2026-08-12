extends "res://game/scripts/traffic_manager_core_v5.gd"

@export var max_parked_vehicles: int = 8
@export var parking_spawn_radius_m: float = 360.0
@export var parking_refresh_interval_s: float = 3.0

const PARKING_MODEL_SCRIPT := preload("res://game/scripts/traffic_parking_model.gd")
const PARKED_CAR_SIZE := Vector3(1.82, 1.08, 4.12)

var _parking_model: RefCounted
var _parking_candidates: Array[Dictionary] = []
var _parking_root: Node3D
var _parking_rng := RandomNumberGenerator.new()
var _parking_elapsed: float = 0.0


func _ready() -> void:
    _parking_model = PARKING_MODEL_SCRIPT.new()
    _parking_rng.seed = traffic_seed + 911
    super._ready()
    _parking_candidates = _parking_model.call("build_candidates", _roads, _traffic_controls)
    _parking_root = Node3D.new()
    _parking_root.name = "ParkedVehicles"
    add_child(_parking_root)
    _replenish_parked_vehicles()
    print(
        "Grand Bruxelles parking simulation: %d safe curb candidates, %d parked vehicles" %
        [get_parking_candidate_count(), get_parked_vehicle_count()]
    )


func _process(delta: float) -> void:
    super._process(delta)
    _parking_elapsed += delta
    if _parking_elapsed < parking_refresh_interval_s:
        return
    _parking_elapsed = 0.0
    _despawn_far_parked_vehicles()
    _replenish_parked_vehicles()


func _replenish_parked_vehicles() -> void:
    if _parking_root == null or _parking_model == null or max_parked_vehicles <= 0:
        return
    var anchor := _anchor_position()
    var nearby: Array = _parking_model.call("candidates_near", _parking_candidates, anchor, parking_spawn_radius_m)
    if nearby.is_empty():
        nearby = _parking_model.call("candidates_near", _parking_candidates, anchor, 100000.0)
    if nearby.is_empty():
        return

    var occupied := {}
    for child: Node in _parking_root.get_children():
        if child.is_queued_for_deletion():
            continue
        occupied[int(child.get_meta("parking_candidate_id", -1))] = true

    var attempts := 0
    while get_parked_vehicle_count() < max_parked_vehicles and attempts < nearby.size() * 3:
        attempts += 1
        var candidate: Dictionary = nearby[_parking_rng.randi_range(0, nearby.size() - 1)]
        var candidate_id := int(candidate.get("id", -1))
        if candidate_id < 0 or occupied.has(candidate_id):
            continue
        _spawn_parked_vehicle(candidate)
        occupied[candidate_id] = true


func _spawn_parked_vehicle(candidate: Dictionary) -> void:
    var body := StaticBody3D.new()
    body.name = "ParkedCar_%03d" % int(candidate.get("id", 0))
    body.collision_layer = 1
    body.collision_mask = 1
    body.set_meta("parking_candidate_id", int(candidate.get("id", -1)))
    body.set_meta("simulated_occupancy", true)
    body.set_meta("road_name", str(candidate.get("road_name", "")))
    body.set_meta("source_osm_id", int(candidate.get("osm_id", 0)))
    body.position = candidate.get("position", Vector3.ZERO)
    body.rotation.y = float(candidate.get("yaw", 0.0))

    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = PARKED_CAR_SIZE
    collision.shape = shape
    body.add_child(collision)

    var color := MIXED_COLORS[int(candidate.get("id", 0)) % MIXED_COLORS.size()].darkened(0.05)
    var lower := _box_mesh(Vector3(1.82, 0.70, 4.12), color, Vector3(0.0, -0.10, 0.0))
    lower.name = "Body"
    body.add_child(lower)
    var cabin := _box_mesh(Vector3(1.48, 0.62, 1.88), color.lightened(0.06), Vector3(0.0, 0.46, -0.12))
    cabin.name = "Cabin"
    body.add_child(cabin)

    _parking_root.add_child(body)


func _despawn_far_parked_vehicles() -> void:
    if _parking_root == null:
        return
    var anchor := _anchor_position()
    var limit := maxf(parking_spawn_radius_m * 1.6, 120.0)
    for child: Node in _parking_root.get_children():
        if child is Node3D and not child.is_queued_for_deletion():
            if (child as Node3D).global_position.distance_to(anchor) > limit:
                child.queue_free()


func get_parking_candidate_count() -> int:
    return _parking_candidates.size()


func get_parked_vehicle_count() -> int:
    if _parking_root == null:
        return 0
    var count := 0
    for child: Node in _parking_root.get_children():
        if not child.is_queued_for_deletion():
            count += 1
    return count
