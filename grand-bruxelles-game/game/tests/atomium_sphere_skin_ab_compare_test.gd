extends SceneTree

const CHANGE_THRESHOLD := 4.0 / 255.0
const MIN_CHANGED_RATIO := 0.0015
const MAX_CHANGED_RATIO := 0.18
const MAX_OUTSIDE_HERO_RATIO := 0.22

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ATOMIUM_SPHERE_SKIN_AB_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() < 2:
        _fail("before/after paths required")
        return
    var before := Image.load_from_file(args[0])
    var after := Image.load_from_file(args[1])
    if before == null or after == null or before.is_empty() or after.is_empty():
        _fail("could not load witness images")
        return
    if before.get_size() != after.get_size():
        _fail("witness dimensions differ")
        return

    var width := before.get_width()
    var height := before.get_height()
    if width != 1280 or height != 720:
        _fail("witness resolution is not 1280x720")
        return

    # The deterministic camera puts the complete Atomium in the central frame.
    # A valid sphere-skin lot should not produce a dominant global/background diff.
    var hero_x0 := int(width * 0.19)
    var hero_x1 := int(width * 0.81)
    var hero_y0 := int(height * 0.04)
    var hero_y1 := int(height * 0.96)

    var changed := 0
    var changed_outside := 0
    var min_x := width
    var min_y := height
    var max_x := -1
    var max_y := -1

    for y: int in range(height):
        for x: int in range(width):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
            if delta <= CHANGE_THRESHOLD:
                continue
            changed += 1
            min_x = mini(min_x, x)
            min_y = mini(min_y, y)
            max_x = maxi(max_x, x)
            max_y = maxi(max_y, y)
            if x < hero_x0 or x > hero_x1 or y < hero_y0 or y > hero_y1:
                changed_outside += 1

    var total := width * height
    var changed_ratio := float(changed) / float(total)
    if changed_ratio < MIN_CHANGED_RATIO:
        _fail("visual change too small: %.4f%%" % (changed_ratio * 100.0))
        return
    if changed_ratio > MAX_CHANGED_RATIO:
        _fail("visual change too global: %.4f%%" % (changed_ratio * 100.0))
        return
    if changed <= 0 or max_x < min_x or max_y < min_y:
        _fail("no changed bounding box")
        return
    var outside_ratio := float(changed_outside) / float(changed)
    if outside_ratio > MAX_OUTSIDE_HERO_RATIO:
        _fail("diff escaped Atomium-dominant frame: outside=%.2f%%" % (outside_ratio * 100.0))
        return

    var bbox_w := max_x - min_x + 1
    var bbox_h := max_y - min_y + 1
    if bbox_w < 120 or bbox_h < 120:
        _fail("diff bbox too small for a readable nine-sphere change: %dx%d" % [bbox_w, bbox_h])
        return

    print("ATOMIUM_SPHERE_SKIN_AB_METRICS: changed=%.4f%% outside=%.2f%% bbox=%dx%d" % [changed_ratio * 100.0, outside_ratio * 100.0, bbox_w, bbox_h])
    print("ATOMIUM_SPHERE_SKIN_AB_OK: %s %s" % [args[0], args[1]])
    quit(0)
