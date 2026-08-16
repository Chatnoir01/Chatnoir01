extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const ANNEESSENS := Vector2(-272.04, -217.07)
const MIDI := Vector2(-668.50, 627.84)

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ANNEESSENS_PLACE_IDENTITY_VISUAL_FAIL: %s" % message)
    quit(1)

func _mask_dynamic(node: Node) -> void:
    var n := node.name.to_lower()
    for token in ["player", "npc", "pedestrian", "traffic", "vehicle", "police", "ambient", "prototypecar"]:
        if token in n:
            if node is Node3D: (node as Node3D).visible = false
            if node is CanvasItem: (node as CanvasItem).visible = false
            node.process_mode = Node.PROCESS_MODE_DISABLED
            return
    for child in node.get_children(): _mask_dynamic(child)

func _capture(path: String) -> Image:
    await process_frame
    await process_frame
    RenderingServer.force_sync()
    var image := root.get_texture().get_image()
    image.save_png(path)
    return image

func _changed_ratio(a: Image, b: Image) -> float:
    if a.get_size() != b.get_size(): return 1.0
    a.convert(Image.FORMAT_RGBA8); b.convert(Image.FORMAT_RGBA8)
    var ad := a.get_data(); var bd := b.get_data(); var changed := 0; var pixels := a.get_width()*a.get_height()
    for i in range(0, ad.size(), 4):
        var delta: int = abs(int(ad[i])-int(bd[i])) + abs(int(ad[i+1])-int(bd[i+1])) + abs(int(ad[i+2])-int(bd[i+2]))
        if delta >= 18: changed += 1
    return float(changed) / float(max(1,pixels))

func _run() -> void:
    var main := MAIN_SCENE.instantiate(); root.add_child(main); current_scene = main
    for _frame in range(18): await process_frame
    var identity := root.get_node_or_null("AnneessensPlaceIdentity")
    if identity == null or not bool(identity.get("source_loaded")):
        _fail("identity/source not ready"); return
    _mask_dynamic(main)
    var camera := Camera3D.new(); camera.name = "AnneessensFrozenCorridorCamera"; root.add_child(camera)
    var route := (ANNEESSENS - MIDI).normalized()
    var approach := ANNEESSENS - route * 58.0
    camera.position = Vector3(approach.x, 7.2, approach.y)
    camera.look_at(Vector3(ANNEESSENS.x, 3.0, ANNEESSENS.y), Vector3.UP)
    camera.fov = 58.0; camera.current = true
    identity.call("set_identity_visible", false)
    var before := await _capture("/tmp/anneessens_before.png")
    identity.call("set_identity_visible", true)
    var after := await _capture("/tmp/anneessens_after.png")
    var ratio := _changed_ratio(before, after)
    print("ANNEESSENS_PLACE_IDENTITY_VISUAL_METRIC changed_pixel_ratio=%.6f" % ratio)
    if ratio < 0.003:
        _fail("material impact too small: %.6f" % ratio); return
    if ratio > 0.30:
        _fail("change is too broad for a place-identity lot: %.6f" % ratio); return
    print("ANNEESSENS_PLACE_IDENTITY_VISUAL_OK")
    quit(0)
