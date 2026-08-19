extends SceneTree

const CONTRACT_PATH := "res://data/qa/grand_place_complete_contour_witness_contract.json"
const WIDTH := 1280
const HEIGHT := 720

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_COMPLETE_CONTOUR_AB_FAIL: %s" % message)
    quit(1)

func _read_contract() -> Dictionary:
    if not FileAccess.file_exists(CONTRACT_PATH):
        return {}
    var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
    return value if typeof(value) == TYPE_DICTIONARY else {}

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 2:
        _fail("expected BEFORE and AFTER PNG paths")
        return
    var contract := _read_contract()
    if contract.is_empty():
        _fail("witness contract missing")
        return
    var thresholds: Dictionary = contract.get("frozen_ab_thresholds", {})
    var min_gt3_pct := float(thresholds.get("min_percent_pixels_rgb_delta_gt_3", -1.0))
    var min_gt8_pct := float(thresholds.get("min_percent_pixels_rgb_delta_gt_8", -1.0))
    var min_bbox_width := int(thresholds.get("min_bbox_width_px", -1))
    var min_bbox_height := int(thresholds.get("min_bbox_height_px", -1))
    if min_gt3_pct < 0.0 or min_gt8_pct < 0.0 or min_bbox_width <= 0 or min_bbox_height <= 0:
        _fail("frozen thresholds invalid")
        return

    var before := Image.new()
    var after := Image.new()
    if before.load(args[0]) != OK:
        _fail("could not load BEFORE %s" % args[0])
        return
    if after.load(args[1]) != OK:
        _fail("could not load AFTER %s" % args[1])
        return
    if before.get_size() != Vector2i(WIDTH, HEIGHT) or after.get_size() != Vector2i(WIDTH, HEIGHT):
        _fail("unexpected capture dimensions before=%s after=%s" % [str(before.get_size()), str(after.get_size())])
        return

    var changed_3 := 0
    var changed_8 := 0
    var min_x := WIDTH
    var min_y := HEIGHT
    var max_x := -1
    var max_y := -1
    var t3 := 3.0 / 255.0
    var t8 := 8.0 / 255.0
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var d := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
            if d > t3:
                changed_3 += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
            if d > t8:
                changed_8 += 1

    var total := float(WIDTH * HEIGHT)
    var gt3_pct := 100.0 * float(changed_3) / total
    var gt8_pct := 100.0 * float(changed_8) / total
    var bbox_width := 0 if max_x < min_x else max_x - min_x + 1
    var bbox_height := 0 if max_y < min_y else max_y - min_y + 1
    print("GRAND_PLACE_COMPLETE_CONTOUR_AB_METRICS: gt3=%.6f%% gt8=%.6f%% bbox=%dx%d thresholds=%.3f%%/%.3f%%/%dx%d" % [gt3_pct, gt8_pct, bbox_width, bbox_height, min_gt3_pct, min_gt8_pct, min_bbox_width, min_bbox_height])

    if gt3_pct < min_gt3_pct:
        _fail("full-frame gt3 impact below frozen threshold: %.6f%% < %.6f%%" % [gt3_pct, min_gt3_pct])
        return
    if gt8_pct < min_gt8_pct:
        _fail("full-frame gt8 impact below frozen threshold: %.6f%% < %.6f%%" % [gt8_pct, min_gt8_pct])
        return
    if bbox_width < min_bbox_width or bbox_height < min_bbox_height:
        _fail("contour impact too localized: bbox=%dx%d minimum=%dx%d" % [bbox_width, bbox_height, min_bbox_width, min_bbox_height])
        return

    print("GRAND_PLACE_COMPLETE_CONTOUR_AB_OK: numeric_pass_only owner_review_required=true before=%s after=%s" % [args[0], args[1]])
    quit(0)
