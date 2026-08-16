extends SceneTree

const OUTPUT := "res://artifacts/visual/jette_station_visual_1280x720.png"


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var packed: PackedScene = load("res://game/zones/laeken_jette/jette_phase2_preview.tscn")
    if packed == null:
        push_error("JETTE_STATION_CAPTURE_FAIL: preview scene unavailable")
        quit(1)
        return

    var scene := packed.instantiate()
    root.add_child(scene)
    await process_frame
    await process_frame
    await process_frame

    var window := root.get_window()
    window.size = Vector2i(1280, 720)
    await process_frame
    await process_frame

    var image := root.get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        push_error("JETTE_STATION_CAPTURE_FAIL: viewport image empty")
        quit(1)
        return

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/visual"))
    var err := image.save_png(OUTPUT)
    if err != OK:
        push_error("JETTE_STATION_CAPTURE_FAIL: save_png=%s" % err)
        quit(1)
        return

    print("JETTE_STATION_CAPTURE_OK: %s" % OUTPUT)
    scene.queue_free()
    await process_frame
    quit(0)
