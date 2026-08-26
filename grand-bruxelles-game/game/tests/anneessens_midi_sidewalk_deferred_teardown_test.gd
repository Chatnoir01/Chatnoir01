extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ANNEESSENS_MIDI_SIDEWALK_DEFERRED_TEARDOWN_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var canonical := root.get_node_or_null("AnneessensMidiSidewalkRuntime")
    if canonical != null:
        root.remove_child(canonical)

    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("production main scene missing")
        return
    var scene := packed.instantiate() as Node3D
    if scene == null:
        _fail("production main did not instantiate as Node3D")
        return
    root.add_child(scene)

    if scene.get_node_or_null("BrusselsOSM") == null or scene.get_node_or_null("UrbISMidiExact") == null or scene.get_node_or_null("Player") == null:
        _fail("production scene anchors missing")
        return

    var runtime_script := load("res://game/scripts/anneessens_midi_sidewalk_runtime.gd") as Script
    if runtime_script == null:
        _fail("Anneessens runtime script missing")
        return
    var runtime := runtime_script.new() as Node
    if runtime == null:
        _fail("Anneessens runtime did not instantiate")
        return

    root.add_child(runtime)
    # _ready() schedules _try_bind with call_deferred(). Remove the runtime before
    # that callback executes. No queued callback may mutate the production scene.
    root.remove_child(runtime)

    await process_frame
    await process_frame

    if scene.get_node_or_null("AnneessensMidiSidewalkKit") != null:
        _fail("deferred bind mutated production scene after runtime teardown")
        return
    if int(runtime.call("diagnostic_sidewalk_count")) != 0:
        _fail("sidewalk count changed after runtime teardown")
        return
    if int(runtime.call("diagnostic_collision_count")) != 0:
        _fail("collision count changed after runtime teardown")
        return

    print("ANNEESSENS_MIDI_SIDEWALK_DEFERRED_TEARDOWN_OK: no_post_teardown_bind=true")
    quit(0)
