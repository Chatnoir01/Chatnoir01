extends SceneTree

const EXPECTED_AMBIENT := 24
const MIN_MOVING_PEDESTRIANS := 20
const MIN_ANIMATED_PROFILED_PEDESTRIANS := 16

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

    print("MIDI_PROFILED_NPC_GAIT_OK moved=%d animated=%d tracked=%d" % [moved, animated, int(stats.get("tracked_pedestrians", 0))])
    scene.queue_free()
    quit(0)
