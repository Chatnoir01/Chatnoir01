extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/anneessens_osm_furniture_runtime.gd")
const ANNEESSENS := Vector3(-272.04, 0.0, -217.07)
const EXPECTED_TREE_COUNT := 7

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ANNEESSENS_OSM_LAZY_ACTIVATION_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var scene := Node3D.new()
    scene.name = "LazyActivationHarness"
    root.add_child(scene)

    var player := Node3D.new()
    player.name = "Player"
    player.position = ANNEESSENS + Vector3(1000.0, 0.0, 0.0)
    scene.add_child(player)

    var runtime := RUNTIME_SCRIPT.new()
    runtime.bind_scene(scene)

    if scene.get_node_or_null("AnneessensOsmFurniture") != null:
        runtime.free()
        scene.free()
        _fail("far player eagerly allocated/published Anneessens furniture")
        return
    if int(runtime.call("tree_count")) != 0:
        runtime.free()
        scene.free()
        _fail("far player eagerly allocated tree instances")
        return
    if not runtime.has_method("_sync_build_and_activation"):
        runtime.free()
        scene.free()
        _fail("runtime lacks distance-gated build synchronizer")
        return

    player.position = ANNEESSENS
    runtime.call("_sync_build_and_activation")
    var furniture_root := scene.get_node_or_null("AnneessensOsmFurniture")
    if furniture_root == null or furniture_root.get_child_count() != EXPECTED_TREE_COUNT:
        runtime.free()
        scene.free()
        _fail("entering activation radius did not atomically publish seven source-backed trees")
        return
    var built_instance_id := furniture_root.get_instance_id()

    player.position = ANNEESSENS + Vector3(1000.0, 0.0, 0.0)
    runtime.call("_sync_build_and_activation")
    var retained_root := scene.get_node_or_null("AnneessensOsmFurniture")
    if retained_root == null or retained_root.get_instance_id() != built_instance_id:
        runtime.free()
        scene.free()
        _fail("leaving radius churned the already-built furniture root")
        return
    if bool(runtime.call("is_active")):
        runtime.free()
        scene.free()
        _fail("far retained root stayed active")
        return

    player.position = ANNEESSENS
    runtime.call("_sync_build_and_activation")
    var reused_root := scene.get_node_or_null("AnneessensOsmFurniture")
    if reused_root == null or reused_root.get_instance_id() != built_instance_id:
        runtime.free()
        scene.free()
        _fail("re-entry rebuilt instead of reusing the validated root")
        return
    if not bool(runtime.call("is_active")):
        runtime.free()
        scene.free()
        _fail("re-entered root did not reactivate")
        return

    runtime.free()
    scene.free()
    print("ANNEESSENS_OSM_LAZY_ACTIVATION_OK: scene_tree_mounted=true far_unbuilt=true enter_builds=7 leave_retains=true reentry_reuses=true radius_m=170.0")
    quit(0)
