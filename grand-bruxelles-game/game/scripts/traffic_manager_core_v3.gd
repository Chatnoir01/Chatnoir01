extends "res://game/scripts/traffic_manager_core_v2.gd"

@export var max_crossing_pedestrians: int = 6
@export var crossing_spawn_radius_m: float = 420.0
@export var crossing_maintenance_interval_s: float = 1.0

const CROSSING_SYSTEM_SCRIPT := preload("res://game/scripts/traffic_crossing_system.gd")
const CROSSING_PEDESTRIAN_SCRIPT := preload("res://game/scripts/traffic_crossing_pedestrian.gd")

var _crossing_system: RefCounted
var _crossing_root: Node3D
var _crossing_elapsed: float = 0.0
var _pedestrian_serial: int = 1


func _ready() -> void:
    _crossing_system = CROSSING_SYSTEM_SCRIPT.new()
    super._ready()
    _crossing_system.call("rebuild", _roads, _traffic_controls)

    _crossing_root = Node3D.new()
    _crossing_root.name = "CrossingPedestrians"
    add_child(_crossing_root)

    _attach_crossing_system_to_vehicles()
    _replenish_crossing_pedestrians()
    print(
        "Grand Bruxelles crossings: %d mapped crossings, %d unsignalized, %d active pedestrians" %
        [
            get_crossing_count(),
            get_unsignalized_crossing_count(),
            get_active_crossing_pedestrian_count(),
        ]
    )


func _process(delta: float) -> void:
    super._process(delta)
    _attach_crossing_system_to_vehicles()

    _crossing_elapsed += delta
    if _crossing_elapsed < crossing_maintenance_interval_s:
        return
    _crossing_elapsed = 0.0
    _despawn_far_crossing_pedestrians()
    _replenish_crossing_pedestrians()


func _spawn_one_vehicle() -> bool:
    var spawned := super._spawn_one_vehicle()
    if spawned:
        _attach_crossing_system_to_vehicles()
    return spawned


func _attach_crossing_system_to_vehicles() -> void:
    if _traffic_root == null or _crossing_system == null:
        return
    for child: Node in _traffic_root.get_children():
        if child.has_method("set_crossing_system"):
            child.call("set_crossing_system", _crossing_system)


func _replenish_crossing_pedestrians() -> void:
    if _crossing_root == null or _crossing_system == null or max_crossing_pedestrians <= 0:
        return

    var active_crossings := {}
    for child: Node in _crossing_root.get_children():
        if child.is_queued_for_deletion():
            continue
        if child.has_method("get_crossing_id"):
            active_crossings[int(child.call("get_crossing_id"))] = true

    var candidates: Array = _crossing_system.call(
        "get_crossings_near",
        _anchor_position(),
        crossing_spawn_radius_m,
        true
    )
    if candidates.is_empty():
        candidates = _crossing_system.call("get_crossings_near", _anchor_position(), 100000.0, true)
    if candidates.is_empty():
        return

    var attempts := 0
    while get_active_crossing_pedestrian_count() < max_crossing_pedestrians and attempts < candidates.size() * 3:
        attempts += 1
        var descriptor: Dictionary = candidates[_rng.randi_range(0, candidates.size() - 1)]
        var crossing_id := int(descriptor.get("id", 0))
        if crossing_id <= 0 or active_crossings.has(crossing_id):
            continue
        _spawn_crossing_pedestrian(descriptor)
        active_crossings[crossing_id] = true


func _spawn_crossing_pedestrian(descriptor: Dictionary) -> void:
    var pedestrian := Node3D.new()
    pedestrian.name = "CrossingPedestrian_%03d" % _pedestrian_serial
    pedestrian.set_script(CROSSING_PEDESTRIAN_SCRIPT)
    pedestrian.add_to_group("traffic_crossing_pedestrian")

    var body := MeshInstance3D.new()
    body.name = "Body"
    var capsule := CapsuleMesh.new()
    capsule.radius = 0.25
    capsule.height = 1.15
    body.mesh = capsule
    body.position.y = 0.78
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.28 + 0.07 * float(_pedestrian_serial % 5), 0.34, 0.42, 1.0)
    material.roughness = 0.85
    body.material_override = material
    pedestrian.add_child(body)

    var head := MeshInstance3D.new()
    head.name = "Head"
    var sphere := SphereMesh.new()
    sphere.radius = 0.18
    sphere.height = 0.36
    head.mesh = sphere
    head.position.y = 1.55
    pedestrian.add_child(head)

    _crossing_root.add_child(pedestrian)
    pedestrian.connect("crossing_finished", Callable(self, "_on_crossing_pedestrian_finished"))
    pedestrian.call(
        "configure",
        descriptor,
        _crossing_system,
        _pedestrian_serial,
        bool(_rng.randi_range(0, 1)),
        _rng.randf_range(0.7, 2.2)
    )
    _pedestrian_serial += 1


func _on_crossing_pedestrian_finished(pedestrian: Node) -> void:
    if is_instance_valid(pedestrian):
        pedestrian.queue_free()
    call_deferred("_replenish_crossing_pedestrians")


func _despawn_far_crossing_pedestrians() -> void:
    if _crossing_root == null:
        return
    var anchor := _anchor_position()
    for child: Node in _crossing_root.get_children():
        if not child is Node3D or child.is_queued_for_deletion():
            continue
        var node := child as Node3D
        if node.global_position.distance_to(anchor) > despawn_radius_m:
            node.queue_free()


func get_crossing_count() -> int:
    if _crossing_system == null:
        return 0
    return int(_crossing_system.call("get_crossing_count"))


func get_unsignalized_crossing_count() -> int:
    if _crossing_system == null:
        return 0
    return int(_crossing_system.call("get_unsignalized_crossing_count"))


func get_active_crossing_count() -> int:
    if _crossing_system == null:
        return 0
    return int(_crossing_system.call("get_active_crossing_count"))


func get_active_crossing_pedestrian_count() -> int:
    if _crossing_root == null:
        return 0
    var count := 0
    for child: Node in _crossing_root.get_children():
        if not child.is_queued_for_deletion():
            count += 1
    return count
