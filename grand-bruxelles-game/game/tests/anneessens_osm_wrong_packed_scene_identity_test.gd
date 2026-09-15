extends SceneTree

const ANNEESSENS := Vector3(-272.04, 0.0, -217.07)

func _initialize() -> void:
    call_deferred("_run")

func _anchor(name_value: String) -> Node3D:
    var node := Node3D.new()
    node.name = name_value
    return node

func _fail(message: String) -> void:
    push_error("ANNEESSENS_WRONG_PACKED_SCENE_IDENTITY_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var runtime := root.get_node_or_null("AnneessensOsmFurnitureRuntime")
    if runtime == null:
        _fail("runtime autoload missing")
        return

    # A packed scene can be perfectly legitimate while still being the wrong scene.
    # Automatic ownership must key on the canonical packed-scene identity, not merely
    # on Main + production-looking anchors.
    var forged := Node3D.new()
    forged.name = "Main"
    forged.add_child(_anchor("BrusselsOSM"))
    forged.add_child(_anchor("UrbISMidiExact"))
    var player := _anchor("Player")
    player.position = ANNEESSENS
    forged.add_child(player)

    var packed := PackedScene.new()
    if packed.pack(forged) != OK:
        _fail("could not pack forged scene")
        return
    var wrong_path := "user://anneessens_wrong_main.tscn"
    if ResourceSaver.save(packed, wrong_path) != OK:
        _fail("could not save forged packed scene")
        return
    forged.queue_free()
    await process_frame

    var wrong_resource := load(wrong_path) as PackedScene
    if wrong_resource == null:
        _fail("could not reload forged packed scene")
        return
    var wrong_scene := wrong_resource.instantiate() as Node3D
    if wrong_scene == null:
        _fail("could not instantiate forged packed scene")
        return
    root.add_child(wrong_scene)
    if wrong_scene.scene_file_path == "res://game/main.tscn" or wrong_scene.scene_file_path.is_empty():
        _fail("witness did not establish a distinct packed-scene identity")
        return

    for _i in range(12):
        await process_frame

    if wrong_scene.get_node_or_null("AnneessensOsmFurniture") != null:
        _fail("runtime mounted furniture under wrong packed Main: %s" % wrong_scene.scene_file_path)
        return
    if int(runtime.call("tree_count")) != 0:
        _fail("runtime allocated source-backed trees for wrong packed Main")
        return

    print("ANNEESSENS_WRONG_PACKED_SCENE_IDENTITY_OK: rejected=%s" % wrong_scene.scene_file_path)
    quit(0)
