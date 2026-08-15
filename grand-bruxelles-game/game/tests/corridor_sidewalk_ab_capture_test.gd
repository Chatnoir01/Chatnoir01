extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const WARMUP_FRAMES := 100
const OUTPUT_DIR := "res://artifacts/qa/corridor_sidewalk_ab"
const BEFORE_PATH := OUTPUT_DIR + "/before.png"
const AFTER_PATH := OUTPUT_DIR + "/after.png"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("CORRIDOR_SIDEWALK_AB_FAIL: %s" % message)
    quit(1)

func _hide_qa_noise(scene: Node) -> void:
    for node_path: String in ["PrototypeLabel"]:
        var item := scene.get_node_or_null(node_path) as CanvasItem
        if item != null:
            item.visible = false

func _save_viewport(viewport: SubViewport, path: String) -> Image:
    RenderingServer.force_draw()
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty():
        return null
    var absolute := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    if image.save_png(absolute) != OK:
        return null
    return image

func _delta_metrics(before: Image, after: Image) -> Dictionary:
    if before.get_size() != after.get_size():
        return {}
    var changed_3 := 0
    var changed_8 := 0
    var min_x := WIDTH
    var min_y := HEIGHT
    var max_x := -1
    var max_y := -1
    var threshold_3 := 3.0 / 255.0
    var threshold_8 := 8.0 / 255.0
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
            if delta > threshold_3:
                changed_3 += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
            if delta > threshold_8:
                changed_8 += 1
    var total := float(WIDTH * HEIGHT)
    var bbox_width := 0 if max_x < min_x else max_x - min_x + 1
    var bbox_height := 0 if max_y < min_y else max_y - min_y + 1
    return {
        "changed_3_fraction": float(changed_3) / total,
        "changed_8_fraction": float(changed_8) / total,
        "bbox_width": bbox_width,
        "bbox_height": bbox_height,
    }

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    if scene == null:
        _fail("main scene did not instantiate")
        return

    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)

    var traffic_manager := scene.get_node_or_null("TrafficManager")
    if traffic_manager != null:
        traffic_manager.set("auto_spawn_runtime", false)
    _hide_qa_noise(scene)
    viewport.add_child(scene)

    for _frame: int in range(WARMUP_FRAMES):
        await process_frame
    _hide_qa_noise(scene)

    var camera := viewport.get_camera_3d()
    if camera == null:
        _fail("normal gameplay camera missing")
        return
    var articulation := scene.get_node_or_null("BrusselsOSM/CorridorSidewalkArticulation") as Node3D
    if articulation == null:
        _fail("production sidewalk articulation missing")
        return

    scene.process_mode = Node.PROCESS_MODE_DISABLED
    articulation.visible = false
    await process_frame
    var before := _save_viewport(viewport, BEFORE_PATH)
    if before == null:
        _fail("could not save BEFORE frame")
        return

    articulation.visible = true
    await process_frame
    var after := _save_viewport(viewport, AFTER_PATH)
    if after == null:
        _fail("could not save AFTER frame")
        return

    var metrics := _delta_metrics(before, after)
    if metrics.is_empty():
        _fail("could not compare A/B frames")
        return
    var changed_3 := float(metrics["changed_3_fraction"])
    var changed_8 := float(metrics["changed_8_fraction"])
    var bbox_width := int(metrics["bbox_width"])
    var bbox_height := int(metrics["bbox_height"])
    print("CORRIDOR_SIDEWALK_AB_METRICS: gt3=%.4f%% gt8=%.4f%% bbox=%dx%d camera=%s" % [changed_3 * 100.0, changed_8 * 100.0, bbox_width, bbox_height, str(camera.global_position)])

    if changed_3 < 0.0075:
        _fail("player-frame improvement is too small: %.4f%% >3 RGB" % (changed_3 * 100.0))
        return
    if changed_8 < 0.0025:
        _fail("player-frame strong delta is too small: %.4f%% >8 RGB" % (changed_8 * 100.0))
        return
    if bbox_width < 480 or bbox_height < 120:
        _fail("visible change is too localized: bbox=%dx%d" % [bbox_width, bbox_height])
        return

    print("CORRIDOR_SIDEWALK_AB_OK: %s %s" % [BEFORE_PATH, AFTER_PATH])
    viewport.queue_free()
    quit(0)
