extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const WARMUP_FRAMES := 120
const SAMPLE_FRAMES := 120
const SAMPLE_STEP := 24
const TILE_COLS := 16
const TILE_ROWS := 9
const TILE_SAMPLE_STEP := 8
const HISTOGRAM_BINS := 16
const OUTPUT_PNG := "res://artifacts/rendered-main-baseline.png"
const OUTPUT_FINGERPRINT := "res://artifacts/rendered-main-fingerprint.json"
const BASELINE_PATH := "res://data/qa/rendered_main_baseline.json"
const BASELINE_SCHEMA := "grand-bruxelles-rendered-main-v1"

# Robust software-renderer tolerances. These compare coarse tile statistics, not pixels.
const MAX_TILE_RGB_MAE := 0.055
const MAX_TILE_LUMA_MAE := 0.045
const MAX_SINGLE_TILE_LUMA_DELTA := 0.16
const MAX_LUMA_HISTOGRAM_MAE := 0.055

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("RENDERED_MAIN_BASELINE_FAIL: %s" % message)
    quit(1)

func _percentile(sorted_values: Array[float], percentile: float) -> float:
    if sorted_values.is_empty():
        return 0.0
    var index := int(ceil((sorted_values.size() - 1) * percentile))
    return sorted_values[clampi(index, 0, sorted_values.size() - 1)]

func _quantize(value: float) -> float:
    return round(value * 10000.0) / 10000.0

func _luma(color: Color) -> float:
    return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b

func _build_visual_fingerprint(image: Image) -> Dictionary:
    var tile_width := WIDTH / TILE_COLS
    var tile_height := HEIGHT / TILE_ROWS
    var tiles: Array = []
    var histogram: Array[float] = []
    histogram.resize(HISTOGRAM_BINS)
    histogram.fill(0.0)
    var histogram_samples := 0

    for tile_y: int in range(TILE_ROWS):
        for tile_x: int in range(TILE_COLS):
            var r_sum := 0.0
            var g_sum := 0.0
            var b_sum := 0.0
            var luma_sum := 0.0
            var count := 0
            var start_x := tile_x * tile_width
            var start_y := tile_y * tile_height
            var end_x := mini(WIDTH, start_x + tile_width)
            var end_y := mini(HEIGHT, start_y + tile_height)
            for y: int in range(start_y, end_y, TILE_SAMPLE_STEP):
                for x: int in range(start_x, end_x, TILE_SAMPLE_STEP):
                    var color := image.get_pixel(x, y)
                    var value := _luma(color)
                    r_sum += color.r
                    g_sum += color.g
                    b_sum += color.b
                    luma_sum += value
                    count += 1
                    var bin_index := clampi(int(floor(value * float(HISTOGRAM_BINS))), 0, HISTOGRAM_BINS - 1)
                    histogram[bin_index] += 1.0
                    histogram_samples += 1
            var denominator := float(maxi(count, 1))
            tiles.append([
                _quantize(r_sum / denominator),
                _quantize(g_sum / denominator),
                _quantize(b_sum / denominator),
                _quantize(luma_sum / denominator),
            ])

    var histogram_denominator := float(maxi(histogram_samples, 1))
    var normalized_histogram: Array = []
    for value: float in histogram:
        normalized_histogram.append(_quantize(value / histogram_denominator))

    return {
        "schema": BASELINE_SCHEMA,
        "width": WIDTH,
        "height": HEIGHT,
        "tile_cols": TILE_COLS,
        "tile_rows": TILE_ROWS,
        "tile_sample_step": TILE_SAMPLE_STEP,
        "tiles_rgbl": tiles,
        "luma_histogram": normalized_histogram,
    }

func _write_json(path: String, value: Dictionary) -> bool:
    var absolute := ProjectSettings.globalize_path(path)
    var directory := absolute.get_base_dir()
    var dir_error := DirAccess.make_dir_recursive_absolute(directory)
    if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
        return false
    var file := FileAccess.open(absolute, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(value, "  ") + "\n")
    return true

func _load_baseline() -> Dictionary:
    if not FileAccess.file_exists(BASELINE_PATH):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASELINE_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    return parsed as Dictionary

func _compare_fingerprint(current: Dictionary, baseline_document: Dictionary) -> Dictionary:
    var baseline: Dictionary = baseline_document.get("fingerprint", {})
    if str(baseline.get("schema", "")) != BASELINE_SCHEMA:
        return {"valid": false, "reason": "baseline schema mismatch"}
    for key: String in ["width", "height", "tile_cols", "tile_rows"]:
        if int(current.get(key, -1)) != int(baseline.get(key, -2)):
            return {"valid": false, "reason": "baseline geometry mismatch for %s" % key}

    var current_tiles: Array = current.get("tiles_rgbl", [])
    var baseline_tiles: Array = baseline.get("tiles_rgbl", [])
    if current_tiles.size() != baseline_tiles.size() or current_tiles.is_empty():
        return {"valid": false, "reason": "baseline tile vector mismatch"}

    var rgb_delta_sum := 0.0
    var luma_delta_sum := 0.0
    var max_luma_delta := 0.0
    var rgb_components := 0
    for index: int in range(current_tiles.size()):
        var current_tile: Array = current_tiles[index]
        var baseline_tile: Array = baseline_tiles[index]
        if current_tile.size() < 4 or baseline_tile.size() < 4:
            return {"valid": false, "reason": "malformed tile vector at %d" % index}
        for channel: int in range(3):
            rgb_delta_sum += absf(float(current_tile[channel]) - float(baseline_tile[channel]))
            rgb_components += 1
        var luma_delta := absf(float(current_tile[3]) - float(baseline_tile[3]))
        luma_delta_sum += luma_delta
        max_luma_delta = maxf(max_luma_delta, luma_delta)

    var current_histogram: Array = current.get("luma_histogram", [])
    var baseline_histogram: Array = baseline.get("luma_histogram", [])
    if current_histogram.size() != baseline_histogram.size() or current_histogram.is_empty():
        return {"valid": false, "reason": "baseline histogram mismatch"}
    var histogram_delta_sum := 0.0
    for index: int in range(current_histogram.size()):
        histogram_delta_sum += absf(float(current_histogram[index]) - float(baseline_histogram[index]))

    return {
        "valid": true,
        "tile_rgb_mae": rgb_delta_sum / float(maxi(rgb_components, 1)),
        "tile_luma_mae": luma_delta_sum / float(current_tiles.size()),
        "max_tile_luma_delta": max_luma_delta,
        "luma_histogram_mae": histogram_delta_sum / float(current_histogram.size()),
    }

func _assert_visual_contract(comparison: Dictionary) -> bool:
    if not bool(comparison.get("valid", false)):
        _fail(str(comparison.get("reason", "invalid visual baseline")))
        return false
    if float(comparison.get("tile_rgb_mae", INF)) > MAX_TILE_RGB_MAE:
        _fail("visual tile RGB MAE %.5f exceeds %.5f" % [comparison["tile_rgb_mae"], MAX_TILE_RGB_MAE])
        return false
    if float(comparison.get("tile_luma_mae", INF)) > MAX_TILE_LUMA_MAE:
        _fail("visual tile luma MAE %.5f exceeds %.5f" % [comparison["tile_luma_mae"], MAX_TILE_LUMA_MAE])
        return false
    if float(comparison.get("max_tile_luma_delta", INF)) > MAX_SINGLE_TILE_LUMA_DELTA:
        _fail("visual max tile luma delta %.5f exceeds %.5f" % [comparison["max_tile_luma_delta"], MAX_SINGLE_TILE_LUMA_DELTA])
        return false
    if float(comparison.get("luma_histogram_mae", INF)) > MAX_LUMA_HISTOGRAM_MAE:
        _fail("visual luma histogram MAE %.5f exceeds %.5f" % [comparison["luma_histogram_mae"], MAX_LUMA_HISTOGRAM_MAE])
        return false
    return true

func _run() -> void:
    root.size = Vector2i(WIDTH, HEIGHT)
    var packed: PackedScene = load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)

    for _i: int in range(WARMUP_FRAMES):
        await process_frame

    var frame_times_ms: Array[float] = []
    var previous_tick_usec := Time.get_ticks_usec()
    var draw_calls_max := 0
    var objects_max := 0
    var primitives_max := 0
    var static_memory_max := 0.0
    for _i: int in range(SAMPLE_FRAMES):
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
    for y: int in range(0, HEIGHT, SAMPLE_STEP):
        for x: int in range(0, WIDTH, SAMPLE_STEP):
            var value := _luma(image.get_pixel(x, y))
            luma_sum += value
            luma_min = minf(luma_min, value)
            luma_max = maxf(luma_max, value)
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

    var fingerprint := _build_visual_fingerprint(image)
    if not _write_json(OUTPUT_FINGERPRINT, {"fingerprint": fingerprint}):
        _fail("could not write visual fingerprint artifact")
        return
    print("RENDERED_MAIN_VISUAL_FINGERPRINT_JSON: %s" % JSON.stringify({"fingerprint": fingerprint}))

    var record_mode := OS.get_environment("GB_VISUAL_BASELINE_RECORD") == "1"
    var baseline_document := _load_baseline()
    var visual_comparison: Dictionary = {"record_mode": record_mode, "baseline_present": not baseline_document.is_empty()}
    if not record_mode:
        if baseline_document.is_empty():
            _fail("visual baseline JSON is missing: %s" % BASELINE_PATH)
            return
        visual_comparison = _compare_fingerprint(fingerprint, baseline_document)
        if not _assert_visual_contract(visual_comparison):
            return

    var frame_sum_ms := 0.0
    for value: float in frame_times_ms:
        frame_sum_ms += value
    var sorted_frame_times := frame_times_ms.duplicate()
    sorted_frame_times.sort()
    var metrics := {
        "renderer": RenderingServer.get_current_rendering_driver_name(),
        "width": WIDTH,
        "height": HEIGHT,
        "warmup_frames": WARMUP_FRAMES,
        "sample_frames": SAMPLE_FRAMES,
        "wall_frame_ms_avg": frame_sum_ms / float(SAMPLE_FRAMES),
        "wall_frame_ms_p95": _percentile(sorted_frame_times, 0.95),
        "draw_calls_max": draw_calls_max,
        "objects_in_frame_max": objects_max,
        "primitives_in_frame_max": primitives_max,
        "static_memory_mib_max": static_memory_max / (1024.0 * 1024.0),
        "sampled_luma_mean": luma_mean,
        "sampled_luma_min": luma_min,
        "sampled_luma_max": luma_max,
        "sampled_luma_range": luma_range,
        "visual_contract": visual_comparison,
        "screenshot": OUTPUT_PNG,
        "fingerprint": OUTPUT_FINGERPRINT,
    }
    print("RENDERED_MAIN_BASELINE_JSON: %s" % JSON.stringify(metrics))
    print("RENDERED_MAIN_BASELINE_OK")
    scene.queue_free()
    await process_frame
    quit(0)
