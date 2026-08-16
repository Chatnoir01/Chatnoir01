extends SceneTree

const EXPECTED_AMBIENT := 24
const MIN_MOVING_PEDESTRIANS := 20
const MIN_ANIMATED_PROFILED_PEDESTRIANS := 16
const MIN_CADENCE_PROFILES := 5
const MIN_CADENCE_MULTIPLIER := 0.90
const MAX_CADENCE_MULTIPLIER := 1.10
const MIN_CADENCE_SPAN := 0.12
const MIN_AMPLITUDE_PROFILES := 5
const MIN_AMPLITUDE_MULTIPLIER := 0.86
const MAX_AMPLITUDE_MULTIPLIER := 1.14
const MIN_AMPLITUDE_SPAN := 0.18
const MIN_IDLE_POSTURE_PROFILES := 4
const MIN_IDLE_ARM_SPREAD_RAD := 0.025
const MAX_IDLE_ARM_SPREAD_RAD := 0.095
const MIN_IDLE_ARM_SPAN_RAD := 0.025
const MIN_CACHED_RIGS := 20
const EXPECTED_DETAIL_UPDATE_DISTANCE_M := 100.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_PROFILED_NPC_GAIT_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    for _frame: int in range(8):
        await process_frame

    var ambient := get_nodes_in_group("ambient_pedestrian")
    if ambient.size() != EXPECTED_AMBIENT:
        _fail("expected %d ambient pedestrians, got %d" % [EXPECTED_AMBIENT, ambient.size()])
        return

    var start_positions: Dictionary = {}
    for raw: Node in ambient:
        var person := raw as Node3D
        if person != null:
            start_positions[person.get_instance_id()] = person.global_position

    for _frame: int in range(12):
        await process_frame

    var moved := 0
    var animated := 0
    for raw: Node in ambient:
        var person := raw as Node3D
        if person == null:
            continue
        var previous: Vector3 = start_positions.get(person.get_instance_id(), person.global_position)
        if person.global_position.distance_to(previous) > 0.005:
            moved += 1

        var proxy := person.get_node_or_null("ProfiledNpcProxy") as Node3D
        if proxy == null:
            _fail("%s has no ProfiledNpcProxy" % person.name)
            return
        if proxy.process_mode != Node.PROCESS_MODE_DISABLED:
            _fail("%s proxy must remain simulation-disabled" % person.name)
            return
        var visual := proxy.get_node_or_null("VisualUpgrade") as Node3D
        if visual == null:
            _fail("%s has no profiled VisualUpgrade" % person.name)
            return
        var left_leg := visual.get_node_or_null("LeftLeg") as Node3D
        var right_leg := visual.get_node_or_null("RightLeg") as Node3D
        var left_arm := visual.get_node_or_null("LeftArm") as Node3D
        var right_arm := visual.get_node_or_null("RightArm") as Node3D
        if left_leg == null or right_leg == null or left_arm == null or right_arm == null:
            _fail("%s profiled visual is missing gait limbs" % person.name)
            return
        var max_swing := maxf(maxf(absf(left_leg.rotation.x), absf(right_leg.rotation.x)), maxf(absf(left_arm.rotation.x), absf(right_arm.rotation.x)))
        var opposition_error := maxf(absf(left_leg.rotation.x + right_leg.rotation.x), absf(left_arm.rotation.x + right_arm.rotation.x))
        if max_swing > 0.025 and opposition_error < 0.03:
            animated += 1

    if moved < MIN_MOVING_PEDESTRIANS:
        _fail("ambient path did not move enough pedestrians: %d" % moved)
        return
    if animated < MIN_ANIMATED_PROFILED_PEDESTRIANS:
        _fail("profiled pedestrians glide without visible gait: animated=%d moved=%d" % [animated, moved])
        return

    var runtime := root.get_node_or_null("MidiProfiledNpcGaitRuntime")
    if runtime == null or not runtime.has_method("gait_stats"):
        _fail("profiled gait runtime stats unavailable")
        return
    var stats: Dictionary = runtime.call("gait_stats")
    if int(stats.get("tracked_pedestrians", 0)) < MIN_MOVING_PEDESTRIANS:
        _fail("runtime is not tracking the moving crowd")
        return
    if bool(stats.get("changes_behavior_owner", true)):
        _fail("visual gait must not take ownership of pedestrian movement")
        return
    if bool(stats.get("changes_navigation", true)):
        _fail("visual gait must not change navigation")
        return

    var rig_cache_size := int(stats.get("rig_cache_size", 0))
    var rig_discovery_count := int(stats.get("rig_discovery_count", 0))
    if rig_cache_size < MIN_CACHED_RIGS:
        _fail("gait rig references are not cached for the active crowd: cache=%d" % rig_cache_size)
        return
    if rig_discovery_count < rig_cache_size:
        _fail("rig discovery accounting is inconsistent: discoveries=%d cache=%d" % [rig_discovery_count, rig_cache_size])
        return
    for _frame: int in range(12):
        await process_frame
    var warmed_stats: Dictionary = runtime.call("gait_stats")
    if int(warmed_stats.get("rig_cache_size", 0)) != rig_cache_size:
        _fail("stable crowd should retain the warmed rig cache")
        return
    if int(warmed_stats.get("rig_discovery_count", 0)) != rig_discovery_count:
        _fail("stable crowd rediscovered gait rig nodes after cache warmup")
        return
    if not bool(warmed_stats.get("rig_cache_stable_after_warmup", false)):
        _fail("runtime does not declare stable per-pedestrian rig caching")
        return

    if not bool(warmed_stats.get("distance_lod_culling_active", false)):
        _fail("detailed gait work must stop beyond the profiled NPC distance LOD")
        return
    if absf(float(warmed_stats.get("detail_update_distance_m", 0.0)) - EXPECTED_DETAIL_UPDATE_DISTANCE_M) > 0.001:
        _fail("detailed gait distance must match the 90m LOD plus 10m fade margin")
        return
    if not bool(warmed_stats.get("simulation_continues_when_detail_culled", false)):
        _fail("distance gait culling must never take ownership of pedestrian simulation")
        return

    var profile_count := int(stats.get("cadence_profile_count", 0))
    var cadence_min := float(stats.get("cadence_multiplier_min", 1.0))
    var cadence_max := float(stats.get("cadence_multiplier_max", 1.0))
    if profile_count < MIN_CADENCE_PROFILES:
        _fail("crowd gait cadence is too synchronized: profiles=%d" % profile_count)
        return
    if cadence_min < MIN_CADENCE_MULTIPLIER or cadence_max > MAX_CADENCE_MULTIPLIER:
        _fail("cadence variation escaped visual-only safe range: min=%.3f max=%.3f" % [cadence_min, cadence_max])
        return
    if cadence_max - cadence_min < MIN_CADENCE_SPAN:
        _fail("cadence spread is too small to desynchronize crowd: min=%.3f max=%.3f" % [cadence_min, cadence_max])
        return
    if not bool(stats.get("cadence_is_stable_per_pedestrian", false)):
        _fail("cadence must be deterministic per pedestrian, not random per frame")
        return

    var amplitude_profile_count := int(stats.get("amplitude_profile_count", 0))
    var amplitude_min := float(stats.get("amplitude_multiplier_min", 1.0))
    var amplitude_max := float(stats.get("amplitude_multiplier_max", 1.0))
    if amplitude_profile_count < MIN_AMPLITUDE_PROFILES:
        _fail("crowd stride amplitude is too uniform: profiles=%d" % amplitude_profile_count)
        return
    if amplitude_min < MIN_AMPLITUDE_MULTIPLIER or amplitude_max > MAX_AMPLITUDE_MULTIPLIER:
        _fail("stride amplitude variation escaped visual-only safe range: min=%.3f max=%.3f" % [amplitude_min, amplitude_max])
        return
    if amplitude_max - amplitude_min < MIN_AMPLITUDE_SPAN:
        _fail("stride amplitude spread is too small to vary body language: min=%.3f max=%.3f" % [amplitude_min, amplitude_max])
        return
    if not bool(stats.get("amplitude_is_stable_per_pedestrian", false)):
        _fail("stride amplitude must be deterministic per pedestrian, not random per frame")
        return

    var idle_profile_count := int(stats.get("idle_posture_profile_count", 0))
    var idle_spread_min := float(stats.get("idle_arm_spread_min_rad", 0.0))
    var idle_spread_max := float(stats.get("idle_arm_spread_max_rad", 0.0))
    if idle_profile_count < MIN_IDLE_POSTURE_PROFILES:
        _fail("idle posture is too uniform or unavailable: profiles=%d" % idle_profile_count)
        return
    if idle_spread_min < MIN_IDLE_ARM_SPREAD_RAD or idle_spread_max > MAX_IDLE_ARM_SPREAD_RAD:
        _fail("idle arm spread escaped safe visual range: min=%.4f max=%.4f" % [idle_spread_min, idle_spread_max])
        return
    if idle_spread_max - idle_spread_min < MIN_IDLE_ARM_SPAN_RAD:
        _fail("idle posture spread is too small: min=%.4f max=%.4f" % [idle_spread_min, idle_spread_max])
        return
    if not bool(stats.get("idle_posture_is_stable_per_pedestrian", false)):
        _fail("idle posture must be deterministic per pedestrian")
        return
    if not bool(stats.get("idle_posture_speed_blended", false)):
        _fail("idle posture must fade out as walking activity rises")
        return

    print("MIDI_PROFILED_NPC_GAIT_OK moved=%d animated=%d tracked=%d cadence_profiles=%d cadence_range=%.3f..%.3f amplitude_profiles=%d amplitude_range=%.3f..%.3f idle_profiles=%d idle_spread=%.4f..%.4f rig_cache=%d rig_discoveries=%d detail_update_m=%.1f" % [moved, animated, int(stats.get("tracked_pedestrians", 0)), profile_count, cadence_min, cadence_max, amplitude_profile_count, amplitude_min, amplitude_max, idle_profile_count, idle_spread_min, idle_spread_max, rig_cache_size, rig_discovery_count, float(warmed_stats.get("detail_update_distance_m", 0.0))])
    scene.queue_free()
    quit(0)
