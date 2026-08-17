extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const MAX_CHANGED_FRACTION := 0.001
const MAX_MEAN_DELTA := 1.0 / 255.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_SURFACE_STABILITY_AB_FAIL: %s" % message)
    quit(1)

func _run() -> void:
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

    var changed := 0
    var total_delta := 0.0
    var threshold := 4.0 / 255.0
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
            total_delta += delta
            if delta > threshold:
                changed += 1

    var pixels := float(WIDTH * HEIGHT)
    var fraction := float(changed) / pixels
    var mean_delta := total_delta / pixels
    print("MIDI_SURFACE_STABILITY_AB_METRICS: changed_gt4=%.5f%% mean_delta=%.7f" % [fraction * 100.0, mean_delta])

    if fraction > MAX_CHANGED_FRACTION:
        _fail("physics-only change altered too many visible pixels: %.5f%%" % (fraction * 100.0))
        return
    if mean_delta > MAX_MEAN_DELTA:
        _fail("physics-only change altered average frame color too much: %.7f" % mean_delta)
        return

    print("MIDI_SURFACE_STABILITY_AB_OK: physics-only runtime change preserved the frozen player view")
    quit(0)
