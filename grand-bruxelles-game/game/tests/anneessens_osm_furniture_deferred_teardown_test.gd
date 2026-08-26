extends SceneTree

const RUNTIME_PATH := "res://game/scripts/anneessens_osm_furniture_runtime.gd"

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
    var runtime := runtime_script.new() as Node
    if runtime == null:
        _fail("runtime is not a Node")
        return

    runtime.name = "AnneessensOsmFurnitureTeardownWitness"
    root.add_child(runtime)
    # _ready() schedules _try_bind and connects SceneTree.node_added. Remove the
    # runtime before either deferred work or a later production mount may bind.
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
        _fail("deferred/watcher bind mutated production scene after runtime teardown")
        return
    if int(runtime.call("tree_count")) != 0:
        _fail("tree count changed after runtime teardown")
        return

    print("ANNEESSENS_OSM_FURNITURE_DEFERRED_TEARDOWN_OK: no_post_teardown_bind=true trees=0")
    quit(0)
