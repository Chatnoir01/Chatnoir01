extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const WARMUP_FRAMES := 120
const SAMPLE_FRAMES := 120
const SAMPLE_STEP := 24
const OUTPUT_PNG := "res://artifacts/rendered-main-baseline.png"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("RENDERED_MAIN_BASELINE_FAIL: %s" % message)
    quit(1)

func _percentile(sorted_values: Array[float], percentile: float) -> float:
    if sorted_values.is_empty():
        return 0.0
    var index := int(ceil((sorted_values.size() - 1) * percentile))
    index = clampi(index, 0, sorted_values.size() - 1)
    return sorted_values[index]

func _run() -> void:
    root.size = Vector2i(WIDTH, HEIGHT)

    var packed: PackedScene = load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return

    var scene := packed.instantiate()
    root.add_child(scene)

    for _i in range(WARMUP_FRAMES):
        await process_frame

    var frame_times_ms: Array[float] = []
    var previous_tick_usec := Time.get_ticks_usec()
    var draw_calls_max := 0
    var objects_max := 0
    var primitives_max := 0
    var static_memory_max := 0.0

    for _i in range(SAMPLE_FRAMES):
        await process_frame
        var now_tick_usec := Time.get_ticks_usec()
        frame_times_ms.append(float(now_tick_usec - previous_tick_usec) / 1000.0)
        previous_tick_usec = now_tick_usec
        draw_calls_max = maxi(draw_calls_max, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
        objects_max = maxi(objects_max, int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
        primitives_max = maxi(primitives_max, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
        static_memory_max = maxf(static_memory_max, float(Performance.get_monitor(Performance.MEMORY_STATIC)))

    RenderingServer.force_draw()
    await process_frame

    var image: Image = root.get_texture().get_image()
    if image == null or image.is_empty():
        _fail("viewport capture is empty")
        return
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        _fail("unexpected capture size: %dx%d" % [image.get_width(), image.get_height()])
        return

    var luma_sum := 0.0
    var luma_min := 1.0
    var luma_max := 0.0
    var sample_count := 0
    for y in range(0, HEIGHT, SAMPLE_STEP):
        for x in range(0, WIDTH, SAMPLE_STEP):
            var c := image.get_pixel(x, y)
            var luma := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
            luma_sum += luma
            luma_min = minf(luma_min, luma)
            luma_max = maxf(luma_max, luma)
            sample_count += 1

    var luma_mean := luma_sum / float(maxi(sample_count, 1))
    var luma_range := luma_max - luma_min
    if luma_range < 0.02:
        _fail("capture appears visually degenerate; sampled luma range %.5f" % luma_range)
        return

    var output_absolute := ProjectSettings.globalize_path(OUTPUT_PNG)
    var output_dir := output_absolute.get_base_dir()
    var dir_error := DirAccess.make_dir_recursive_absolute(output_dir)
    if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
        _fail("could not create artifact directory: %s" % error_string(dir_error))
        return
    var save_error := image.save_png(output_absolute)
    if save_error != OK:
        _fail("could not save screenshot: %s" % error_string(save_error))
        return

    var frame_sum_ms := 0.0
    for value in frame_times_ms:
        frame_sum_ms += value
    var frame_ms_avg := frame_sum_ms / float(SAMPLE_FRAMES)
    var sorted_frame_times := frame_times_ms.duplicate()
    sorted_frame_times.sort()
    var frame_ms_p95 := _percentile(sorted_frame_times, 0.95)

    var metrics := {
        "renderer": RenderingServer.get_current_rendering_driver_name(),
        "width": WIDTH,
        "height": HEIGHT,
        "warmup_frames": WARMUP_FRAMES,
        "sample_frames": SAMPLE_FRAMES,
        "wall_frame_ms_avg": frame_ms_avg,
        "wall_frame_ms_p95": frame_ms_p95,
        "draw_calls_max": draw_calls_max,
        "objects_in_frame_max": objects_max,
        "primitives_in_frame_max": primitives_max,
        "static_memory_mib_max": static_memory_max / (1024.0 * 1024.0),
        "sampled_luma_mean": luma_mean,
        "sampled_luma_min": luma_min,
        "sampled_luma_max": luma_max,
        "sampled_luma_range": luma_range,
        "screenshot": OUTPUT_PNG
    }

    print("RENDERED_MAIN_BASELINE_JSON: %s" % JSON.stringify(metrics))
    print("RENDERED_MAIN_BASELINE_OK")
    scene.queue_free()
    await process_frame
    quit(0)
