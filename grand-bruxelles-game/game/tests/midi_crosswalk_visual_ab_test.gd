extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const ROAD_ROI_X_MAX := 600
const ROAD_ROI_Y_MIN := 400
const ROAD_ROI_Y_MAX := 650


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("MIDI_CROSSWALK_VISUAL_AB_FAIL: %s" % message)
    quit(1)


func _is_bright_neutral(color: Color) -> bool:
    var channel_min := minf(color.r, minf(color.g, color.b))
    var channel_max := maxf(color.r, maxf(color.g, color.b))
    return channel_min > 220.0 / 255.0 and channel_max - channel_min < 20.0 / 255.0


func _run() -> void:
    # Keep the production scene present while project autoloads settle, so the
    # image comparator exercises the same imported project as the capture.
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

    var changed_12 := 0
    var before_bright_road := 0
    var after_bright_road := 0
    var min_x := WIDTH
    var min_y := HEIGHT
    var max_x := -1
    var max_y := -1
    var delta_threshold := 12.0 / 255.0
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var old_color := before.get_pixel(x, y)
            var new_color := after.get_pixel(x, y)
            var delta := maxf(
                absf(old_color.r - new_color.r),
                maxf(absf(old_color.g - new_color.g), absf(old_color.b - new_color.b))
            )
            if delta > delta_threshold:
                changed_12 += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
            if x < ROAD_ROI_X_MAX and y >= ROAD_ROI_Y_MIN and y < ROAD_ROI_Y_MAX:
                if _is_bright_neutral(old_color):
                    before_bright_road += 1
                if _is_bright_neutral(new_color):
                    after_bright_road += 1

    var frame_pixels := float(WIDTH * HEIGHT)
    var changed_fraction := float(changed_12) / frame_pixels
    var bbox_width := 0 if max_x < min_x else max_x - min_x + 1
    var bbox_height := 0 if max_y < min_y else max_y - min_y + 1
    var bright_drop := 1.0 - float(after_bright_road) / float(maxi(before_bright_road, 1))
    print(
        "MIDI_CROSSWALK_VISUAL_AB_METRICS: gt12=%.3f%% bbox=%dx%d bright_road=%d->%d drop=%.2f%%" %
        [
            changed_fraction * 100.0,
            bbox_width,
            bbox_height,
            before_bright_road,
            after_bright_road,
            bright_drop * 100.0,
        ]
    )

    # The neutral-road count is the primary proof. Broader delta and bounding
    # box bounds only reject empty or scene-wide captures without depending on
    # the exact position of ambient pedestrians between two renderer launches.
    if changed_fraction < 0.03:
        _fail("crosswalk correction is not materially visible")
        return
    if changed_fraction > 0.20:
        _fail("crosswalk correction unexpectedly changes too much of the frame")
        return
    if bbox_width < 450 or bbox_height < 140:
        _fail("crosswalk correction is too localized: %dx%d" % [bbox_width, bbox_height])
        return
    if before_bright_road < 35000:
        _fail("BEFORE image does not reproduce the oversized white slabs")
        return
    if after_bright_road < 10000:
        _fail("AFTER image removed the pedestrian marking instead of rescaling it")
        return
    if after_bright_road > 25000 or bright_drop < 0.55:
        _fail("oversized bright road slabs remain visible after correction")
        return

    print("MIDI_CROSSWALK_VISUAL_AB_OK: %s %s" % [args[0], args[1]])
    scene.queue_free()
    quit(0)
