extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_SIDEWALK_RUNTIME_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    await process_frame
    await process_frame
    var surfaces := scene.get_node_or_null("UrbISBourseSurfaceContext")
    if surfaces == null:
        _fail("Bourse surface context missing")
        return
    if int(surfaces.official_sidewalk_overlay_count()) != 5:
        _fail("expected 5 bounded sidewalk polygons")
        return
    if int(surfaces.official_sidewalk_overlay_vertex_count()) != 62:
        _fail("expected 62 sidewalk vertices")
        return
    if int(surfaces.official_sidewalk_overlay_triangle_count()) != 52:
        _fail("expected 52 sidewalk triangles")
        return
    if not bool(surfaces.sidewalk_overlay_height_is_renderer_bias_only()):
        _fail("overlay must not claim physical curb elevation")
        return
    print("BOURSE_SIDEWALK_RUNTIME_OK: 5 official foreground sidewalk polygons; curb elevation unresolved")
    scene.queue_free()
    quit(0)
