extends Node3D

class FakeBehavior:
    extends RefCounted
    var target_position := Vector3.ZERO

var behavior := FakeBehavior.new()
var active: bool = true
var transit_state: int = 0
var movement_held: bool = false

func set_destination(destination: Vector3) -> void:
    behavior.target_position = destination

func get_world_position() -> Vector3:
    return global_position

func update_crossing_context(_signal_value: int, traffic_gap_safe: bool, _waiting_seconds: float) -> int:
    if traffic_gap_safe:
        movement_held = false
        return 2
    movement_held = true
    return 1

func clear_pedestrian_hold() -> void:
    movement_held = false
