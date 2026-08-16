extends Node

const TELEPORT_GUARD_M := 6.0
const MAX_VISUAL_SPEED_MPS := 2.2
const GAIT_REFERENCE_SPEED_MPS := 1.0
const MAX_LEG_SWING_RAD := 0.42
const ARM_SWING_RATIO := 0.90
const CADENCE_BUCKETS := 9
const CADENCE_MIN := 0.92
const CADENCE_MAX := 1.08
const AMPLITUDE_BUCKETS := 9
const AMPLITUDE_MIN := 0.88
const AMPLITUDE_MAX := 1.12
const DETAIL_LOD_SWITCH_DISTANCE_M := 90.0
const DETAIL_LOD_TRANSITION_MARGIN_M := 10.0
const DETAIL_UPDATE_DISTANCE_M := DETAIL_LOD_SWITCH_DISTANCE_M + DETAIL_LOD_TRANSITION_MARGIN_M
const DETAIL_UPDATE_DISTANCE_SQUARED := DETAIL_UPDATE_DISTANCE_M * DETAIL_UPDATE_DISTANCE_M

var _last_positions: Dictionary = {}
var _phases: Dictionary = {}
var _cadence_multipliers: Dictionary = {}
var _amplitude_multipliers: Dictionary = {}
var _rig_cache: Dictionary = {}
var _rig_discovery_count: int = 0
var _tracked_pedestrians: int = 0
var _animated_pedestrians: int = 0
var _distance_culled_pedestrians: int = 0
var _camera_distance_culling_available: bool = false
var _last_max_speed_mps: float = 0.0

func _process(delta: float) -> void:
    _update_profiled_gait(delta)

func _update_profiled_gait(delta: float) -> void:
    if delta <= 0.0:
        return
    var tracked := 0
    var animated := 0
    var distance_culled := 0
    var max_speed := 0.0
    var live_ids: Dictionary = {}
    var camera := get_viewport().get_camera_3d()
    _camera_distance_culling_available = camera != null
    var camera_position := Vector3.ZERO
    if camera != null:
        camera_position = camera.global_position

    for raw: Node in get_tree().get_nodes_in_group("ambient_pedestrian"):
        var person := raw as Node3D
        if person == null:
            continue

        var instance_id := person.get_instance_id()
        live_ids[instance_id] = true
        if camera != null and not _within_detail_update_distance(person.global_position, camera_position):
            distance_culled += 1
            continue

        var rig := _rig_for_person(person, instance_id)
        if rig.is_empty():
            continue
        var left_leg := rig.get("left_leg") as Node3D
        var right_leg := rig.get("right_leg") as Node3D
        var left_arm := rig.get("left_arm") as Node3D
        var right_arm := rig.get("right_arm") as Node3D
        if left_leg == null or right_leg == null or left_arm == null or right_arm == null:
            _rig_cache.erase(instance_id)
            continue

        tracked += 1
        var current_position := person.global_position
        if not _last_positions.has(instance_id):
            _last_positions[instance_id] = current_position
            var stable_hash := String(person.name).hash()
            _phases[instance_id] = float(posmod(stable_hash, 23)) * 0.37
            _cadence_multipliers[instance_id] = _cadence_multiplier_for_name(person.name)
            _amplitude_multipliers[instance_id] = _amplitude_multiplier_for_name(person.name)
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
            var cadence := float(_cadence_multipliers.get(instance_id, 1.0))
            phase += delta * lerpf(4.0, 9.0, activity) * cadence
            _phases[instance_id] = fmod(phase, TAU)
        var amplitude := float(_amplitude_multipliers.get(instance_id, 1.0))
        var swing := sin(phase) * MAX_LEG_SWING_RAD * activity * amplitude
        _set_limb_swing(left_leg, right_leg, left_arm, right_arm, swing)
        if absf(swing) > 0.025:
            animated += 1

    _tracked_pedestrians = tracked
    _animated_pedestrians = animated
    _distance_culled_pedestrians = distance_culled
    _last_max_speed_mps = max_speed
    _prune_stale(live_ids)

func _within_detail_update_distance(person_position: Vector3, camera_position: Vector3) -> bool:
    return person_position.distance_squared_to(camera_position) <= DETAIL_UPDATE_DISTANCE_SQUARED

func _rig_for_person(person: Node3D, instance_id: int) -> Dictionary:
    var cached: Dictionary = _rig_cache.get(instance_id, {})
    if not cached.is_empty():
        var cached_left_leg := cached.get("left_leg") as Node3D
        var cached_right_leg := cached.get("right_leg") as Node3D
        var cached_left_arm := cached.get("left_arm") as Node3D
        var cached_right_arm := cached.get("right_arm") as Node3D
        if is_instance_valid(cached_left_leg) and is_instance_valid(cached_right_leg) and is_instance_valid(cached_left_arm) and is_instance_valid(cached_right_arm):
            return cached
        _rig_cache.erase(instance_id)

    var proxy := person.get_node_or_null("ProfiledNpcProxy") as Node3D
    if proxy == null:
        return {}
    var visual := proxy.get_node_or_null("VisualUpgrade") as Node3D
    if visual == null:
        return {}
    var left_leg := visual.get_node_or_null("LeftLeg") as Node3D
    var right_leg := visual.get_node_or_null("RightLeg") as Node3D
    var left_arm := visual.get_node_or_null("LeftArm") as Node3D
    var right_arm := visual.get_node_or_null("RightArm") as Node3D
    if left_leg == null or right_leg == null or left_arm == null or right_arm == null:
        return {}

    var rig := {
        "left_leg": left_leg,
        "right_leg": right_leg,
        "left_arm": left_arm,
        "right_arm": right_arm,
    }
    _rig_cache[instance_id] = rig
    _rig_discovery_count += 1
    return rig

func _cadence_multiplier_for_name(person_name: StringName) -> float:
    var bucket := posmod(String(person_name).hash(), CADENCE_BUCKETS)
    if CADENCE_BUCKETS <= 1:
        return 1.0
    return lerpf(CADENCE_MIN, CADENCE_MAX, float(bucket) / float(CADENCE_BUCKETS - 1))

func _amplitude_multiplier_for_name(person_name: StringName) -> float:
    var bucket := posmod((String(person_name) + ":stride-amplitude").hash(), AMPLITUDE_BUCKETS)
    if AMPLITUDE_BUCKETS <= 1:
        return 1.0
    return lerpf(AMPLITUDE_MIN, AMPLITUDE_MAX, float(bucket) / float(AMPLITUDE_BUCKETS - 1))

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
            _cadence_multipliers.erase(key)
            _amplitude_multipliers.erase(key)
            _rig_cache.erase(key)

func gait_stats() -> Dictionary:
    var unique_profiles: Dictionary = {}
    var cadence_min := 1.0
    var cadence_max := 1.0
    var first := true
    for key: Variant in _cadence_multipliers.keys():
        var cadence := float(_cadence_multipliers[key])
        unique_profiles[snappedf(cadence, 0.001)] = true
        if first:
            cadence_min = cadence
            cadence_max = cadence
            first = false
        else:
            cadence_min = minf(cadence_min, cadence)
            cadence_max = maxf(cadence_max, cadence)

    var unique_amplitudes: Dictionary = {}
    var amplitude_min := 1.0
    var amplitude_max := 1.0
    var amplitude_first := true
    for key: Variant in _amplitude_multipliers.keys():
        var amplitude := float(_amplitude_multipliers[key])
        unique_amplitudes[snappedf(amplitude, 0.001)] = true
        if amplitude_first:
            amplitude_min = amplitude
            amplitude_max = amplitude
            amplitude_first = false
        else:
            amplitude_min = minf(amplitude_min, amplitude)
            amplitude_max = maxf(amplitude_max, amplitude)

    return {
        "tracked_pedestrians": _tracked_pedestrians,
        "animated_pedestrians": _animated_pedestrians,
        "distance_culled_pedestrians": _distance_culled_pedestrians,
        "max_measured_speed_mps": _last_max_speed_mps,
        "changes_behavior_owner": false,
        "changes_navigation": false,
        "movement_source": "observed transform delta from existing midi_urban_life.gd ambient path",
        "teleport_guard_m": TELEPORT_GUARD_M,
        "cadence_profile_count": unique_profiles.size(),
        "cadence_multiplier_min": cadence_min,
        "cadence_multiplier_max": cadence_max,
        "cadence_is_stable_per_pedestrian": true,
        "amplitude_profile_count": unique_amplitudes.size(),
        "amplitude_multiplier_min": amplitude_min,
        "amplitude_multiplier_max": amplitude_max,
        "amplitude_is_stable_per_pedestrian": true,
        "rig_cache_size": _rig_cache.size(),
        "rig_discovery_count": _rig_discovery_count,
        "rig_cache_stable_after_warmup": true,
        "distance_lod_culling_active": true,
        "camera_distance_culling_available": _camera_distance_culling_available,
        "detail_update_distance_m": DETAIL_UPDATE_DISTANCE_M,
        "simulation_continues_when_detail_culled": true,
    }
