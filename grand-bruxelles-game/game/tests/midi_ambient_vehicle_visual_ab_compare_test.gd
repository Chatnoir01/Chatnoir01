extends SceneTree

const WIDTH := 1280
const HEIGHT := 720

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_AMBIENT_VEHICLE_AB_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 2:
        _fail("expected BEFORE and AFTER PNG paths")
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
    var changed_4_fraction := float(changed_4) / total
    var changed_12_fraction := float(changed_12) / total
    var bbox_width := 0 if max_x < min_x else max_x - min_x + 1
    var bbox_height := 0 if max_y < min_y else max_y - min_y + 1
    print("MIDI_AMBIENT_VEHICLE_AB_METRICS: gt4=%.4f%% gt12=%.4f%% bbox=%dx%d" % [changed_4_fraction * 100.0, changed_12_fraction * 100.0, bbox_width, bbox_height])

    if changed_4_fraction < 0.0015:
        _fail("normal player frame change too small: %.4f%%" % (changed_4_fraction * 100.0))
        return
    if changed_12_fraction < 0.0008:
        _fail("strong normal player frame change too small: %.4f%%" % (changed_12_fraction * 100.0))
        return
    if bbox_width < 260 or bbox_height < 100:
        _fail("vehicle improvement too localized in frame: bbox=%dx%d" % [bbox_width, bbox_height])
        return

    print("MIDI_AMBIENT_VEHICLE_AB_OK: %s %s" % [args[0], args[1]])
    quit(0)
