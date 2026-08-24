extends SceneTree

const ARTIFACT_DIR := "res://artifacts/base_ground_surface_player_witness"
const BEFORE_PATH := ARTIFACT_DIR + "/base_ground_before.png"
const AFTER_PATH := ARTIFACT_DIR + "/base_ground_after.png"
const REPORT_PATH := ARTIFACT_DIR + "/base_ground_banding_regression.json"
const DIFF_THRESHOLD := 0.03
const MAX_VERTICAL_TO_HORIZONTAL_GRADIENT_RATIO := 2.50
const MIN_VERTICAL_TO_HORIZONTAL_GRADIENT_RATIO := 0.40
const MIN_CHANGED_ADJACENCY_SAMPLES := 5000

func _initialize() -> void:
    call_deferred("_run")
func _fail(message: String) -> void:
    push_error("BRUSSELS_BASE_GROUND_BANDING_FAIL: %s" % message)
    quit(1)
func _max_rgb_delta(a: Color, b: Color) -> float:
    return maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
func _luminance_delta(before: Color, after: Color) -> float:
    return (after.r * 0.2126 + after.g * 0.7152 + after.b * 0.0722) - (before.r * 0.2126 + before.g * 0.7152 + before.b * 0.0722)
func _is_changed(before: Color, after: Color) -> bool:
    return _max_rgb_delta(before, after) > DIFF_THRESHOLD

func _run() -> void:
    var before := Image.load_from_file(BEFORE_PATH)
    var after := Image.load_from_file(AFTER_PATH)
    if before == null or before.is_empty() or after == null or after.is_empty():
        _fail("player witness PNGs missing")
        return
    if before.get_size() != Vector2i(1280, 720) or after.get_size() != Vector2i(1280, 720):
        _fail("player witness PNG dimensions drifted")
        return
    var horizontal_energy := 0.0
    var vertical_energy := 0.0
    var horizontal_samples := 0
    var vertical_samples := 0
    for y: int in range(before.get_height()):
        for x: int in range(before.get_width() - 1):
            var b0 := before.get_pixel(x, y)
            var a0 := after.get_pixel(x, y)
            var b1 := before.get_pixel(x + 1, y)
            var a1 := after.get_pixel(x + 1, y)
            if _is_changed(b0, a0) and _is_changed(b1, a1):
                horizontal_energy += absf(_luminance_delta(b1, a1) - _luminance_delta(b0, a0))
                horizontal_samples += 1
    for y: int in range(before.get_height() - 1):
        for x: int in range(before.get_width()):
            var b0 := before.get_pixel(x, y)
            var a0 := after.get_pixel(x, y)
            var b1 := before.get_pixel(x, y + 1)
            var a1 := after.get_pixel(x, y + 1)
            if _is_changed(b0, a0) and _is_changed(b1, a1):
                vertical_energy += absf(_luminance_delta(b1, a1) - _luminance_delta(b0, a0))
                vertical_samples += 1
    if horizontal_samples < MIN_CHANGED_ADJACENCY_SAMPLES or vertical_samples < MIN_CHANGED_ADJACENCY_SAMPLES:
        _fail("insufficient changed adjacency samples for directional analysis: horizontal=%d vertical=%d" % [horizontal_samples, vertical_samples])
        return
    var horizontal_mean := horizontal_energy / float(horizontal_samples)
    var vertical_mean := vertical_energy / float(vertical_samples)
    if horizontal_mean <= 0.000001 or vertical_mean <= 0.000001:
        _fail("directional gradient energy collapsed")
        return
    var ratio := vertical_mean / horizontal_mean
    var report := {
        "schema": "grand-bruxelles-base-ground-banding-regression-v1",
        "diff_threshold": DIFF_THRESHOLD,
        "horizontal_gradient_mean": horizontal_mean,
        "vertical_gradient_mean": vertical_mean,
        "vertical_to_horizontal_gradient_ratio": ratio,
        "horizontal_samples": horizontal_samples,
        "vertical_samples": vertical_samples,
        "minimum_ratio": MIN_VERTICAL_TO_HORIZONTAL_GRADIENT_RATIO,
        "maximum_ratio": MAX_VERTICAL_TO_HORIZONTAL_GRADIENT_RATIO,
        "camera_changed": false,
        "geometry_changed": false,
        "human_full_frame_veto_still_authoritative": true,
    }
    var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
    if file == null:
        _fail("could not persist directional banding report")
        return
    file.store_string(JSON.stringify(report, "  "))
    file.close()
    if ratio > MAX_VERTICAL_TO_HORIZONTAL_GRADIENT_RATIO:
        _fail("horizontal banding regression: vertical/horizontal gradient ratio %.6f exceeds %.2f" % [ratio, MAX_VERTICAL_TO_HORIZONTAL_GRADIENT_RATIO])
        return
    if ratio < MIN_VERTICAL_TO_HORIZONTAL_GRADIENT_RATIO:
        _fail("vertical streaking regression: vertical/horizontal gradient ratio %.6f below %.2f" % [ratio, MIN_VERTICAL_TO_HORIZONTAL_GRADIENT_RATIO])
        return
    print("BRUSSELS_BASE_GROUND_BANDING_OK: horizontal=%.8f vertical=%.8f ratio=%.6f samples=%d/%d human_veto=true" % [horizontal_mean, vertical_mean, ratio, horizontal_samples, vertical_samples])
    quit(0)
