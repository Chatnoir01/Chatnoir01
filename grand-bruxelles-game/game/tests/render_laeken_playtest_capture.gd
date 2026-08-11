extends SceneTree

const SCENE_PATH := "res://game/zones/laeken_jette/laeken_playtest.tscn"
const OUTPUT_PATH := "res://laeken_playtest_current.png"


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    root.size = Vector2i(1280, 720)
    var packed: PackedScene = load(SCENE_PATH)
    if packed == null:
        push_error("PLAYTEST_CAPTURE_FAIL: scene did not load")
        quit(1)
        return

    var scene: Node = packed.instantiate()
    root.add_child(scene)

    # Let the full DTM mesh, UrbIS drape, photo-guided corridor and terrain-aware
    # spawn settle before reading the actual player camera viewport.
    for _i in range(45):
        await process_frame
    RenderingServer.force_draw()
    await process_frame
    await process_frame

    var image: Image = root.get_texture().get_image()
    if image == null or image.is_empty():
        push_error("PLAYTEST_CAPTURE_FAIL: viewport image empty")
        quit(1)
        return

    var error := image.save_png(OUTPUT_PATH)
    if error != OK:
        push_error("PLAYTEST_CAPTURE_FAIL: save_png error %s" % error)
        quit(1)
        return

    print("PLAYTEST_CAPTURE_OK: %s %dx%d" % [OUTPUT_PATH, image.get_width(), image.get_height()])
    scene.queue_free()
    await process_frame
    quit(0)
