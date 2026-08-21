extends "res://game/scripts/traffic_manager_rgsdev_vehicle_extension.gd"
class_name TrafficManagerNpcCrossingExtension

const AMBULANCE_VEHICLE_SCRIPT := preload("res://game/scripts/ambulance_vehicle.gd")
const AMBULANCE_VISUAL_SCRIPT := preload("res://game/scripts/rgsdev_vehicle_visual.gd")

@export var pedestrian_gap_reaction_s: float = 0.8
@export var pedestrian_gap_min_clearance_m: float = 3.2
@export var pedestrian_gap_max_lookahead_m: float = 22.0
@export var pedestrian_gap_extra_buffer_m: float = 1.5
@export var pedestrian_gap_min_closing_speed_mps: float = 0.35
@export var dedicated_ambulance_count: int = 2
@export var dedicated_ambulance_spacing_m: float = 4.8
@export var dedicated_ambulance_offset: Vector3 = Vector3(8.0, 1.10, 5.0)

var _ambulance_root: Node3D = null

func _ready() -> void:
    super._ready()
    call_deferred("_spawn_dedicated_ambulances")

func _spawn_dedicated_ambulances() -> void:
    if dedicated_ambulance_count <= 0:
        return
    if _ambulance_root == null or not is_instance_valid(_ambulance_root):
        _ambulance_root = get_node_or_null("Ambulances") as Node3D
        if _ambulance_root == null:
            _ambulance_root = Node3D.new()
            _ambulance_root.name = "Ambulances"
            add_child(_ambulance_root)
    if _ambulance_root.get_child_count() > 0:
        return

    var anchor := _anchor_position()
    for index: int in range(dedicated_ambulance_count):
        var ambulance := AMBULANCE_VEHICLE_SCRIPT.new() as AmbulanceVehicle
        ambulance.name = "Ambulance_%02d" % [index + 1]
        ambulance.collision_layer = 1
        ambulance.collision_mask = 1
        ambulance.add_to_group("vehicle")
        ambulance.add_to_group("ambulance")
        ambulance.add_to_group("emergency_vehicle")

        var collision := CollisionShape3D.new()
        collision.name = "CollisionShape3D"
        var box := BoxShape3D.new()
        box.size = Vector3(2.08, 2.12, 5.28)
        collision.shape = box
        ambulance.add_child(collision)

        var visual := AMBULANCE_VISUAL_SCRIPT.new()
        visual.name = "RgsdevVisual"
        visual.call("configure_model", "ambulance")
        ambulance.add_child(visual)

        ambulance.configure_archetype("car")
        ambulance.set_meta("dedicated_special_vehicle", true)
        ambulance.set_meta("special_vehicle_kind", "ambulance")
        _ambulance_root.add_child(ambulance)
        ambulance.global_position = anchor + dedicated_ambulance_offset + Vector3(float(index) * dedicated_ambulance_spacing_m, 0.0, 0.0)
        ambulance.rotation.y = deg_to_rad(-38.0)
        ambulance.call("configure_as_parked")

func get_ambulance_count() -> int:
    if _ambulance_root == null:
        return 0
    var count := 0
    for child: Node in _ambulance_root.get_children():
        if not child.is_queued_for_deletion():
            count += 1
    return count

func get_npc_crossing_system() -> RefCounted:
    return _crossing_system

func is_crossing_gap_safe(crossing_id: int, pedestrian_position: Vector3 = Vector3.ZERO) -> bool:
    if _crossing_system == null or _traffic_root == null:
        return false
    var crossing: Dictionary = _crossing_system.call("get_crossing", crossing_id)
    if crossing.is_empty():
        return false
    var crossing_position: Vector3 = crossing.get("position", pedestrian_position)
    var minimum_clearance := maxf(1.0, pedestrian_gap_min_clearance_m)
    var maximum_lookahead := maxf(minimum_clearance, pedestrian_gap_max_lookahead_m)

    for child: Node in _traffic_root.get_children():
        if child.is_queued_for_deletion() or not child is Node3D:
            continue
        var vehicle := child as Node3D
        var offset := crossing_position - vehicle.global_position
        offset.y = 0.0
        var distance := offset.length()
        if distance <= minimum_clearance:
            return false
        if distance > maximum_lookahead:
            continue
        if bool(child.get_meta("traffic_wrecked", false)):
            continue

        var planar_velocity := Vector3.ZERO
        if child is CharacterBody3D:
            planar_velocity = (child as CharacterBody3D).velocity
            planar_velocity.y = 0.0
        var speed := planar_velocity.length()
        if speed < maxf(0.05, pedestrian_gap_min_closing_speed_mps):
            continue
        var closing_speed := planar_velocity.dot(offset.normalized())
        if closing_speed < pedestrian_gap_min_closing_speed_mps:
            continue

        var braking_mps2 := 7.5
        if child is TrafficVehicleCore:
            braking_mps2 = maxf(1.0, (child as TrafficVehicleCore).braking_mps2)
        var stopping_distance := (
            closing_speed * maxf(0.0, pedestrian_gap_reaction_s)
            + (closing_speed * closing_speed) / (2.0 * braking_mps2)
            + maxf(0.0, pedestrian_gap_extra_buffer_m)
        )
        if distance <= maxf(minimum_clearance, stopping_distance):
            return false
    return true
