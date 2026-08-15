extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const WARMUP_FRAMES := 60
const BEFORE_PATH := "res://artifacts/visual/brussels_location_identity_banner_before.png"
const AFTER_PATH := "res://artifacts/visual/brussels_location_identity_banner_after.png"
const ROI := Rect2i(8, 10, 540, 52)
const MIN_GT3_PERCENT := 0.80
const MIN_GT8_PERCENT := 0.50

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_LOCATION_IDENTITY_BANNER_WITNESS_FAIL: %s" % message)
    quit(1)

func _save(image: Image, path: String) -> void:
    var absolute_output := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
    if image.save_png(absolute_output) != OK:
        _fail("could not save %s" % path)

func _capture(viewport: SubViewport) -> Image:
    RenderingServer.force_draw()
    await process_frame
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        _fail("capture invalid")
        return Image.new()
    return image

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene missing")
        return
    var scene := packed.instantiate()
    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    viewport.add_child(scene)

    for _frame: int in range(WARMUP_FRAMES):
        await process_frame

    var label := scene.get_node_or_null("LocationLabel")
    if label == null or not label.has_method("set_identity_plaque_enabled"):
        _fail("production LocationLabel identity API missing")
        return
    if str(label.get("text")) != "BRUXELLES-MIDI · BRUSSEL-ZUID":
        _fail("spawn does not naturally expose Midi bilingual identity")
        return

    # Freeze the complete production scene after warmup. Rendering continues,
    # but traffic, NPC, vehicle physics, HUD refresh and other dynamic state no
    # longer advance between A/B. The only mutation below is panel visibility.
    scene.process_mode = Node.PROCESS_MODE_DISABLED
    label.call("set_identity_plaque_enabled", false)
    var before := await _capture(viewport)
    if before.is_empty():
        return
    _save(before, BEFORE_PATH)

    label.call("set_identity_plaque_enabled", true)
    var after := await _capture(viewport)
    if after.is_empty():
        return
    _save(after, AFTER_PATH)

    var gt3 := 0
    var gt8 := 0
    var outside_roi_changed := 0
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) * 255.0
            if delta > 3.0:
                gt3 += 1
                if not ROI.has_point(Vector2i(x, y)):
                    outside_roi_changed += 1
            if delta > 8.0:
                gt8 += 1

    var total := WIDTH * HEIGHT
    var gt3_percent := float(gt3) * 100.0 / float(total)
    var gt8_percent := float(gt8) * 100.0 / float(total)
    if outside_roi_changed > 8:
        _fail("A/B contaminated outside HUD ROI: %d pixels" % outside_roi_changed)
        return
    if gt3_percent < MIN_GT3_PERCENT or gt8_percent < MIN_GT8_PERCENT:
        _fail("normal-frame cue too small: gt3=%.4f%% gt8=%.4f%%" % [gt3_percent, gt8_percent])
        return

    print("BRUSSELS_LOCATION_IDENTITY_BANNER_WITNESS_OK: gt3=%d pct_gt3=%.4f gt8=%d pct_gt8=%.4f outside_roi_gt3=%d dynamic_state=frozen exposure=production_spawn" % [gt3, gt3_percent, gt8, gt8_percent, outside_roi_changed])
    quit(0)
