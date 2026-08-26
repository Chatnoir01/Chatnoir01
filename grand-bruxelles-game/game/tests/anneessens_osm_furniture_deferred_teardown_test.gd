extends SceneTree

const RUNTIME_PATH := "res://game/scripts/anneessens_osm_furniture_runtime.gd"
const EXPECTED_TREES := 7

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ANNEESSENS_OSM_FURNITURE_DEFERRED_TEARDOWN_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var canonical := root.get_node_or_null("AnneessensOsmFurnitureRuntime")
    if canonical != null:
        root.remove_child(canonical)

    var runtime_script := load(RUNTIME_PATH) as Script
    if runtime_script == null:
        _fail("runtime script missing")
        return

    # Phase 1: deferred/watcher work queued before teardown must never bind later.
    var runtime := runtime_script.new() as Node
    if runtime == null:
        _fail("runtime is not a Node")
        return
    runtime.name = "AnneessensOsmFurnitureTeardownWitness"
    root.add_child(runtime)
    root.remove_child(runtime)

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

    await process_frame
    await process_frame

    if scene.get_node_or_null("AnneessensOsmFurniture") != null:
        _fail("deferred/watcher bind mutated production scene after pre-bind teardown")
        return
    if int(runtime.call("tree_count")) != 0:
        _fail("tree count changed after pre-bind teardown")
        return

    # Phase 2: once bound, teardown must remove the runtime-owned root and all
    # seven source-backed tree/collision instances from the still-live Main.
    var bound_runtime := runtime_script.new() as Node
    if bound_runtime == null:
        _fail("bound runtime is not a Node")
        return
    bound_runtime.name = "AnneessensOsmFurnitureBoundTeardownWitness"
    root.add_child(bound_runtime)

    for _frame: int in range(20):
        if int(bound_runtime.call("tree_count")) == EXPECTED_TREES:
            break
        await process_frame

    if int(bound_runtime.call("tree_count")) != EXPECTED_TREES:
        _fail("runtime did not bind before teardown: trees=%d expected=%d" % [int(bound_runtime.call("tree_count")), EXPECTED_TREES])
        return
    if scene.get_node_or_null("AnneessensOsmFurniture") == null:
        _fail("runtime-owned furniture root missing before teardown")
        return

    root.remove_child(bound_runtime)
    await process_frame
    await process_frame

    if scene.get_node_or_null("AnneessensOsmFurniture") != null:
        _fail("runtime-owned furniture root survived teardown")
        return
    if int(bound_runtime.call("tree_count")) != 0:
        _fail("tree registry survived teardown")
        return

    print("ANNEESSENS_OSM_FURNITURE_DEFERRED_TEARDOWN_OK: no_post_teardown_bind=true owned_root_cleanup=true trees=0")
    quit(0)
