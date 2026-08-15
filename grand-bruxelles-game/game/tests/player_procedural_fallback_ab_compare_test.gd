extends SceneTree

const WIDTH := 1280
const HEIGHT := 720

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("PLAYER_PROCEDURAL_FALLBACK_AB_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 2:
        _fail("expected BEFORE and AFTER PNG paths")
        return
    var before := Image.new()
    var after := Image.new()
    if before.load(args[0]) != OK or after.load(args[1]) != OK:
        _fail("could not load A/B captures")
        return
    if before.get_size() != Vector2i(WIDTH, HEIGHT) or after.get_size() != Vector2i(WIDTH, HEIGHT):
        _fail("unexpected capture dimensions")
        return

    var changed_4 := 0
    var changed_12 := 0
    var min_x := WIDTH
    var min_y := HEIGHT
    var max_x := -1
    var max_y := -1
    var t4 := 4.0 / 255.0
    var t12 := 12.0 / 255.0
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var d := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
            if d > t4:
                changed_4 += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
            if d > t12:
                changed_12 += 1

    var total := float(WIDTH * HEIGHT)
    var gt4 := float(changed_4) / total
    var gt12 := float(changed_12) / total
    var bbox_w := 0 if max_x < min_x else max_x - min_x + 1
    var bbox_h := 0 if max_y < min_y else max_y - min_y + 1
    print("PLAYER_PROCEDURAL_FALLBACK_AB_METRICS: gt4=%.4f%% gt12=%.4f%% bbox=%dx%d" % [gt4 * 100.0, gt12 * 100.0, bbox_w, bbox_h])

    # Frozen before first run: the third-person player is intentionally localized,
    # so require a material silhouette delta without pretending the whole city changed.
    if gt4 < 0.00020:
        _fail("normal-camera player change too small: %.4f%%" % (gt4 * 100.0))
        return
    if gt12 < 0.00008:
        _fail("strong player change too small: %.4f%%" % (gt12 * 100.0))
        return
    if bbox_w < 30 or bbox_h < 55:
        _fail("player delta too localized: bbox=%dx%d" % [bbox_w, bbox_h])
        return
    print("PLAYER_PROCEDURAL_FALLBACK_AB_OK: %s %s" % [args[0], args[1]])
    quit(0)
