extends Node

const TELEPORT_GUARD_M := 6.0
const MAX_VISUAL_SPEED_MPS := 2.2
const GAIT_REFERENCE_SPEED_MPS := 1.0
const MAX_LEG_SWING_RAD := 0.42
const ARM_SWING_RATIO := 0.90

var _last_positions: Dictionary = {}
var _phases: Dictionary = {}
var _tracked_pedestrians: int = 0
var _animated_pedestrians: int = 0
var _last_max_speed_mps: float = 0.0

func _process(delta: float) -> void:
    _update_profiled_gait(delta)

func _update_profiled_gait(delta: float) -> void:
    if delta <= 0.0:
        return
    var tracked := 0
    var animated := 0
    var max_speed := 0.0
    var live_ids: Dictionary = {}
    for raw: Node in get_tree().get_nodes_in_group("ambient_pedestrian"):
        var person := raw as Node3D
        if person == null:
            continue
        var proxy := person.get_node_or_null("ProfiledNpcProxy") as Node3D
        if proxy == null:
            continue
        var visual := proxy.get_node_or_null("VisualUpgrade") as Node3D
        if visual == null:
            continue
        var left_leg := visual.get_node_or_null("LeftLeg") as Node3D
        var right_leg := visual.get_node_or_null("RightLeg") as Node3D
        var left_arm := visual.get_node_or_null("LeftArm") as Node3D
        var right_arm := visual.get_node_or_null("RightArm") as Node3D
        if left_leg == null or right_leg == null or left_arm == null or right_arm == null:
            continue

        var instance_id := person.get_instance_id()
        live_ids[instance_id] = true
        tracked += 1
        var current_position := person.global_position
        if not _last_positions.has(instance_id):
            _last_positions[instance_id] = current_position
            _phases[instance_id] = float(instance_id % 23) * 0.37
            _set_limb_swing(left_leg, right_leg, left_arm, right_arm, 0.0)
            continue

        var previous: Vector3 = _last_positions[instance_id]
        _last_positions[instance_id] = current_position
        var displacement := current_position.distance_to(previous)
        var speed := 0.0
        if displacement <= TELEPORT_GUARD_M:
            speed = clampf(displacement / delta, 0.0, MAX_VISUAL_SPEED_MPS)
        max_speed = maxf(max_speed, speed)

        var activity := clampf(speed / GAIT_REFERENCE_SPEED_MPS, 0.0, 1.0)
        var phase := float(_phases.get(instance_id, 0.0))
        if activity > 0.01:
            phase += delta * lerpf(4.0, 9.0, activity)
            _phases[instance_id] = fmod(phase, TAU)
        var swing := sin(phase) * MAX_LEG_SWING_RAD * activity
        _set_limb_swing(left_leg, right_leg, left_arm, right_arm, swing)
        if absf(swing) > 0.025:
            animated += 1

    _tracked_pedestrians = tracked
    _animated_pedestrians = animated
    _last_max_speed_mps = max_speed
    _prune_stale(live_ids)

func _set_limb_swing(left_leg: Node3D, right_leg: Node3D, left_arm: Node3D, right_arm: Node3D, swing: float) -> void:
    left_leg.rotation.x = swing
    right_leg.rotation.x = -swing
    left_arm.rotation.x = -swing * ARM_SWING_RATIO
    right_arm.rotation.x = swing * ARM_SWING_RATIO

func _prune_stale(live_ids: Dictionary) -> void:
    for key: Variant in _last_positions.keys():
        if not live_ids.has(key):
            _last_positions.erase(key)
            _phases.erase(key)

func gait_stats() -> Dictionary:
    return {
        "tracked_pedestrians": _tracked_pedestrians,
        "animated_pedestrians": _animated_pedestrians,
        "max_measured_speed_mps": _last_max_speed_mps,
        "changes_behavior_owner": false,
        "changes_navigation": false,
        "movement_source": "observed transform delta from existing midi_urban_life.gd ambient path",
        "teleport_guard_m": TELEPORT_GUARD_M,
    }
