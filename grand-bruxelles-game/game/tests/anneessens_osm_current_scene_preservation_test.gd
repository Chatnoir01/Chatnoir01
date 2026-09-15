extends SceneTree

const ANNEESSENS := Vector3(-272.04, 0.0, -217.07)
const EXPECTED_TREE_COUNT := 7

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var runtime := root.get_node_or_null("AnneessensOsmFurnitureRuntime")
    if runtime == null:
        _fail("AnneessensOsmFurnitureRuntime autoload missing")
        return

    # current_scene is authoritative by SceneTree identity even for a synthetic
    # harness that deliberately has no canonical scene_file_path. The packed-scene
    # path requirement belongs only to automatic fallback discovery.
    var scene := Node3D.new()
    scene.name = "CurrentSceneHarness"
    var osm := Node3D.new()
    osm.name = "BrusselsOSM"
    scene.add_child(osm)
    var urbis := Node3D.new()
    urbis.name = "UrbISMidiExact"
    scene.add_child(urbis)
    var player := Node3D.new()
    player.name = "Player"
    player.position = ANNEESSENS
    scene.add_child(player)
    root.add_child(scene)
    current_scene = scene

    if not scene.scene_file_path.is_empty():
        _fail("synthetic current-scene harness unexpectedly has a packed-scene path")
        return

    # Let the autoload's deferred automatic discovery run. This must remain valid
    # after fallback ownership is hardened to res://game/main.tscn.
    await process_frame
    await process_frame

    var furniture := scene.get_node_or_null("AnneessensOsmFurniture")
    if furniture == null:
        _fail("authoritative current_scene was rejected after automatic discovery")
        return
    if furniture.get_child_count() != EXPECTED_TREE_COUNT:
        _fail("authoritative current_scene did not materialize exactly %d source-backed trees" % EXPECTED_TREE_COUNT)
        return

    current_scene = null
    scene.queue_free()
    await process_frame
    print("ANNEESSENS_CURRENT_SCENE_PRESERVATION_OK")
    quit(0)

func _fail(message: String) -> void:
    push_error(message)
    quit(1)
