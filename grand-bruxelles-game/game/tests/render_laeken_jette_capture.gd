extends SceneTree

const SCENE_PATH := "res://game/zones/laeken_jette/laeken_jette_preview.tscn"
const OUTPUT_PATH := "res://laeken_jette_preview.png"

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    root.size = Vector2i(1280, 720)
    var packed: PackedScene = load(SCENE_PATH)
    if packed == null:
        push_error("CAPTURE_FAIL: scene did not load")
        quit(1)
        return

    var scene: Node = packed.instantiate()
    root.add_child(scene)

    for _i in range(12):
        await process_frame
    RenderingServer.force_draw()
    await process_frame

    var image: Image = root.get_texture().get_image()
    if image == null or image.is_empty():
        push_error("CAPTURE_FAIL: viewport image empty")
        quit(1)
        return

    var error := image.save_png(OUTPUT_PATH)
    if error != OK:
        push_error("CAPTURE_FAIL: save_png error %s" % error)
        quit(1)
        return

    print("CAPTURE_OK: %s %dx%d" % [OUTPUT_PATH, image.get_width(), image.get_height()])
    scene.queue_free()
    await process_frame
    quit(0)
