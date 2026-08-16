extends SceneTree

const GAIT_RUNTIME := preload("res://game/scripts/midi_profiled_npc_gait_runtime.gd")
const STEP_SECONDS := 0.1
const CULLED_STEPS := 70
const STEP_DISTANCE_M := 0.1
const MIN_REENTRY_SPEED_MPS := 0.75

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_PROFILED_NPC_GAIT_LOD_REENTRY_FAIL: %s" % message)
    quit(1)

func _limb(name_value: String, parent: Node3D) -> Node3D:
    var limb := Node3D.new()
    limb.name = name_value
    parent.add_child(limb)
    return limb

func _run() -> void:
    var scene := Node3D.new()
    scene.name = "GaitLodReentryFixture"
    root.add_child(scene)

    var camera := Camera3D.new()
    camera.name = "Camera3D"
    camera.current = true
    scene.add_child(camera)

    var person := Node3D.new()
    person.name = "AmbientPedestrianReentryFixture"
    person.add_to_group("ambient_pedestrian")
    scene.add_child(person)

    var proxy := Node3D.new()
    proxy.name = "ProfiledNpcProxy"
    person.add_child(proxy)
    var visual := Node3D.new()
    visual.name = "VisualUpgrade"
    proxy.add_child(visual)
    _limb("LeftLeg", visual)
    _limb("RightLeg", visual)
    _limb("LeftArm", visual)
    _limb("RightArm", visual)

    var runtime := GAIT_RUNTIME.new()
    runtime.name = "MidiProfiledNpcGaitRuntime"
    runtime.process_mode = Node.PROCESS_MODE_DISABLED
    root.add_child(runtime)
    await process_frame

    runtime.call("_update_profiled_gait", STEP_SECONDS)
    person.position.x += STEP_DISTANCE_M
    runtime.call("_update_profiled_gait", STEP_SECONDS)
    var warm_stats: Dictionary = runtime.call("gait_stats")
    if float(warm_stats.get("max_measured_speed_mps", 0.0)) < MIN_REENTRY_SPEED_MPS:
        _fail("fixture did not establish a moving gait before culling")
        return

    camera.position = Vector3(200.0, 0.0, 0.0)
    for _step: int in range(CULLED_STEPS):
        person.position.x += STEP_DISTANCE_M
        runtime.call("_update_profiled_gait", STEP_SECONDS)

    var culled_stats: Dictionary = runtime.call("gait_stats")
    if int(culled_stats.get("distance_culled_pedestrians", 0)) != 1:
        _fail("fixture did not exercise distance gait culling")
        return

    camera.position = person.position
    person.position.x += STEP_DISTANCE_M
    runtime.call("_update_profiled_gait", STEP_SECONDS)

    var reentry_stats: Dictionary = runtime.call("gait_stats")
    var reentry_speed := float(reentry_stats.get("max_measured_speed_mps", 0.0))
    if reentry_speed < MIN_REENTRY_SPEED_MPS:
        _fail("moving pedestrian froze for a frame after LOD re-entry: measured_speed=%.3f expected>=%.3f" % [reentry_speed, MIN_REENTRY_SPEED_MPS])
        return
    if bool(reentry_stats.get("changes_behavior_owner", true)) or bool(reentry_stats.get("changes_navigation", true)):
        _fail("LOD continuity fix must remain visual-only")
        return

    print("MIDI_PROFILED_NPC_GAIT_LOD_REENTRY_OK culled_steps=%d stale_distance_m=%.1f reentry_speed=%.3f" % [CULLED_STEPS, CULLED_STEPS * STEP_DISTANCE_M, reentry_speed])
    quit(0)
