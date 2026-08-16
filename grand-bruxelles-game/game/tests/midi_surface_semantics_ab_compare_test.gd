extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const LOWER_FRAME_Y := 420


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("MIDI_SURFACE_SEMANTICS_AB_FAIL: %s" % message)
    quit(1)


func _luma(color: Color) -> float:
    return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b


func _lower_frame_luma(image: Image) -> float:
    var total := 0.0
    var count := 0
    for y: int in range(LOWER_FRAME_Y, HEIGHT, 4):
        for x: int in range(0, WIDTH, 4):
            total += _luma(image.get_pixel(x, y))
            count += 1
    return total / float(maxi(count, 1))


func _run() -> void:
    # Keep the production scene present while project autoloads settle, so this
    # image-only comparator does not create misleading missing-scene errors.
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("production main scene did not load")
        return
    var scene := packed.instantiate()
    var traffic_manager := scene.get_node_or_null("TrafficManager")
    if traffic_manager != null:
        traffic_manager.set("auto_spawn_runtime", false)
    root.add_child(scene)
    await process_frame

    var args := OS.get_cmdline_user_args()
    if args.size() != 2:
        _fail("expected BEFORE and AFTER PNG paths")
        return

    var before := Image.new()
    var after := Image.new()
    if before.load(args[0]) != OK or after.load(args[1]) != OK:
        _fail("could not load A/B images")
        return
    if before.get_size() != Vector2i(WIDTH, HEIGHT) or after.get_size() != Vector2i(WIDTH, HEIGHT):
        _fail("unexpected A/B image dimensions")
        return

    var changed_4 := 0
    var changed_12 := 0
    var min_x := WIDTH
    var min_y := HEIGHT
    var max_x := -1
    var max_y := -1
    var threshold_4 := 4.0 / 255.0
    var threshold_12 := 12.0 / 255.0
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
            if delta > threshold_4:
                changed_4 += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
            if delta > threshold_12:
                changed_12 += 1

    var pixels := float(WIDTH * HEIGHT)
    var fraction_4 := float(changed_4) / pixels
    var fraction_12 := float(changed_12) / pixels
    var bbox_width := 0 if max_x < min_x else max_x - min_x + 1
    var bbox_height := 0 if max_y < min_y else max_y - min_y + 1
    var before_lower_luma := _lower_frame_luma(before)
    var after_lower_luma := _lower_frame_luma(after)
    var lower_luma_drop := before_lower_luma - after_lower_luma
    print(
        "MIDI_SURFACE_SEMANTICS_AB_METRICS: gt4=%.4f%% gt12=%.4f%% bbox=%dx%d lower_luma=%.5f->%.5f drop=%.5f" %
        [fraction_4 * 100.0, fraction_12 * 100.0, bbox_width, bbox_height, before_lower_luma, after_lower_luma, lower_luma_drop]
    )

    if fraction_4 < 0.20 or fraction_12 < 0.18:
        _fail("underground-overlay removal is not materially visible")
        return
    if fraction_4 > 0.45:
        _fail("surface correction unexpectedly changed most of the frame")
        return
    if bbox_width < 1000 or bbox_height < 300:
        _fail("surface correction is too localized: %dx%d" % [bbox_width, bbox_height])
        return
    if lower_luma_drop < 0.08:
        _fail("street-level road did not replace the pale underground overlay")
        return

    print("MIDI_SURFACE_SEMANTICS_AB_OK: %s %s" % [args[0], args[1]])
    scene.queue_free()
    quit(0)
