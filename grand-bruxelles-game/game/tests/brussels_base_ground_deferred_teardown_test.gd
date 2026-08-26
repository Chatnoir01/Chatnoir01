extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_BASE_GROUND_DEFERRED_TEARDOWN_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var canonical := root.get_node_or_null("BrusselsBaseGroundSurfaceRuntime")
    if canonical != null:
        root.remove_child(canonical)
        canonical.queue_free()

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
    var ground := scene.get_node_or_null("Ground") as CSGBox3D
    if ground == null:
        _fail("production Ground missing")
        return
    var original_material: Material = ground.material

    var runtime_script := load("res://game/scripts/brussels_base_ground_surface_runtime.gd") as Script
    if runtime_script == null:
        _fail("base-ground runtime script missing")
        return
    var runtime := runtime_script.new() as Node
    if runtime == null:
        _fail("base-ground runtime did not instantiate")
        return

    root.add_child(runtime)
    var callback := Callable(runtime, "_on_node_added")
    if not node_added.is_connected(callback):
        _fail("runtime did not register node_added watcher")
        return

    # _ready() queues _bind_existing_main. Remove the runtime before that deferred
    # callback executes: neither the queued bind nor the watcher may outlive owner teardown.
    root.remove_child(runtime)

    if node_added.is_connected(callback):
        _fail("node_added watcher survived runtime teardown")
        return

    await process_frame
    await process_frame

    if ground.material != original_material:
        _fail("deferred bind mutated Ground material after runtime teardown")
        return
    if bool(runtime.call("ready_complete")):
        _fail("runtime became ready after teardown")
        return

    print("BRUSSELS_BASE_GROUND_DEFERRED_TEARDOWN_OK: watcher_disconnected=true no_post_teardown_bind=true material_unchanged=true")
    quit(0)
