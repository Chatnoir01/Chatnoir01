extends "res://game/scripts/traffic_manager_official_density_extension.gd"
class_name TrafficManagerNpcCrossingExtension

@export var pedestrian_gap_reaction_s: float = 0.8
@export var pedestrian_gap_min_clearance_m: float = 3.2
@export var pedestrian_gap_max_lookahead_m: float = 22.0
@export var pedestrian_gap_extra_buffer_m: float = 1.5
@export var pedestrian_gap_min_closing_speed_mps: float = 0.35

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
