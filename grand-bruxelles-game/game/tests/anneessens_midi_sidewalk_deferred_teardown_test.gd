extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ANNEESSENS_MIDI_SIDEWALK_DEFERRED_TEARDOWN_FAIL: %s" % message)
    quit(1)

func _load_production_main() -> Node3D:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("production main scene missing")
        return null
    var scene := packed.instantiate() as Node3D
    if scene == null:
        _fail("production main did not instantiate as Node3D")
        return null
    root.add_child(scene)
    if scene.get_node_or_null("BrusselsOSM") == null or scene.get_node_or_null("UrbISMidiExact") == null or scene.get_node_or_null("Player") == null:
        _fail("production scene anchors missing")
        return null
    return scene

func _new_runtime() -> Node:
    var runtime_script := load("res://game/scripts/anneessens_midi_sidewalk_runtime.gd") as Script
    if runtime_script == null:
        _fail("Anneessens runtime script missing")
        return null
    var runtime := runtime_script.new() as Node
    if runtime == null:
        _fail("Anneessens runtime did not instantiate")
        return null
    return runtime

func _assert_proxy_collision_disabled(kit: Node) -> bool:
    for child: Node in kit.get_children():
        if not child is CSGBox3D:
            _fail("non-CSG sidewalk child leaked into owned root")
            return false
        if (child as CSGBox3D).use_collision:
            _fail("unverified authored sidewalk proxy owns collision before teardown")
            return false
    return true

func _run() -> void:
    var canonical := root.get_node_or_null("AnneessensMidiSidewalkRuntime")
    if canonical != null:
        root.remove_child(canonical)

    var deferred_scene := _load_production_main()
    if deferred_scene == null:
        return
    var deferred_runtime := _new_runtime()
    if deferred_runtime == null:
        return
    root.add_child(deferred_runtime)
    root.remove_child(deferred_runtime)

    await process_frame
    await process_frame

    if deferred_scene.get_node_or_null("AnneessensMidiSidewalkKit") != null:
        _fail("deferred bind mutated production scene after runtime teardown")
        return
    if int(deferred_runtime.call("diagnostic_sidewalk_count")) != 0:
        _fail("sidewalk count changed after deferred runtime teardown")
        return
    if int(deferred_runtime.call("diagnostic_collision_count")) != 0:
        _fail("collision count changed after deferred runtime teardown")
        return

    root.remove_child(deferred_scene)
    deferred_scene.queue_free()
    deferred_runtime.queue_free()
    await process_frame

    var bound_scene := _load_production_main()
    if bound_scene == null:
        return
    var bound_runtime := _new_runtime()
    if bound_runtime == null:
        return
    root.add_child(bound_runtime)

    for _frame in range(12):
        await process_frame
        if bound_scene.get_node_or_null("AnneessensMidiSidewalkKit") != null:
            break

    var owned_root := bound_scene.get_node_or_null("AnneessensMidiSidewalkKit")
    if owned_root == null:
        _fail("successful bind never created AnneessensMidiSidewalkKit")
        return
    var sidewalks := int(bound_runtime.call("diagnostic_sidewalk_count"))
    var collisions := int(bound_runtime.call("diagnostic_collision_count"))
    if sidewalks <= 0:
        _fail("successful bind produced no sidewalk visuals")
        return
    if collisions != 0:
        _fail("successful bind claimed unverified proxy collision ownership")
        return
    if not _assert_proxy_collision_disabled(owned_root):
        return

    root.remove_child(bound_runtime)

    if int(bound_runtime.call("diagnostic_sidewalk_count")) != 0:
        _fail("sidewalk ownership registry not cleared synchronously")
        return
    if int(bound_runtime.call("diagnostic_collision_count")) != 0:
        _fail("collision ownership registry not cleared synchronously")
        return
    if not is_instance_valid(owned_root) or not owned_root.is_queued_for_deletion():
        _fail("owned sidewalk root was not queued for teardown-safe destruction")
        return

    await process_frame

    if bound_scene.get_node_or_null("AnneessensMidiSidewalkKit") != null:
        _fail("owned sidewalk root survived deferred teardown destruction")
        return

    print("ANNEESSENS_MIDI_SIDEWALK_DEFERRED_TEARDOWN_OK: no_post_teardown_bind=true owned_root_queued=true owned_root_released=true sidewalks=%d proxy_collisions=0" % sidewalks)
    quit(0)
