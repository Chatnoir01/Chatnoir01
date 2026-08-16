extends SceneTree

const EXPECTED_AMBIENT := 24
const MIN_IDLE_PROFILES := 4
const MIN_IDLE_SPREAD_RAD := 0.025
const MAX_IDLE_SPREAD_RAD := 0.095
const MIN_IDLE_SPAN_RAD := 0.025

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_PROFILED_NPC_IDLE_POSTURE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    for _frame: int in range(24):
        await process_frame

    var ambient := get_nodes_in_group("ambient_pedestrian")
    if ambient.size() != EXPECTED_AMBIENT:
        _fail("expected %d ambient pedestrians, got %d" % [EXPECTED_AMBIENT, ambient.size()])
        return

    var runtime := root.get_node_or_null("MidiProfiledNpcGaitRuntime")
    if runtime == null or not runtime.has_method("gait_stats"):
        _fail("profiled gait runtime stats unavailable")
        return
    var stats: Dictionary = runtime.call("gait_stats")

    var profile_count := int(stats.get("idle_posture_profile_count", 0))
    var spread_min := float(stats.get("idle_arm_spread_min_rad", 0.0))
    var spread_max := float(stats.get("idle_arm_spread_max_rad", 0.0))
    if profile_count < MIN_IDLE_PROFILES:
        _fail("idle posture is too uniform or unavailable: profiles=%d" % profile_count)
        return
    if spread_min < MIN_IDLE_SPREAD_RAD or spread_max > MAX_IDLE_SPREAD_RAD:
        _fail("idle arm spread escaped safe range: min=%.4f max=%.4f" % [spread_min, spread_max])
        return
    if spread_max - spread_min < MIN_IDLE_SPAN_RAD:
        _fail("idle posture spread is too small: min=%.4f max=%.4f" % [spread_min, spread_max])
        return
    if not bool(stats.get("idle_posture_is_stable_per_pedestrian", false)):
        _fail("idle posture must be deterministic per pedestrian")
        return
    if not bool(stats.get("idle_posture_speed_blended", false)):
        _fail("idle posture must fade out as walking activity rises")
        return
    if bool(stats.get("changes_behavior_owner", true)) or bool(stats.get("changes_navigation", true)):
        _fail("idle posture must remain visual-only")
        return

    print("MIDI_PROFILED_NPC_IDLE_POSTURE_OK profiles=%d spread=%.4f..%.4f" % [profile_count, spread_min, spread_max])
    scene.queue_free()
    quit(0)
