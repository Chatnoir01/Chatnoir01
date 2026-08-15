extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const WARMUP_FRAMES := 120
const OUTPUT_DIR := "res://artifacts/shared-environment"
const BEFORE_PNG := OUTPUT_DIR + "/neutral-daylight-before.png"
const AFTER_PNG := OUTPUT_DIR + "/neutral-daylight-after.png"
const METRICS_JSON := OUTPUT_DIR + "/neutral-daylight-metrics.json"
const MIN_CHANGED_RATIO := 0.05
const DELTA_THRESHOLD := 3.0 / 255.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("SHARED_ENVIRONMENT_DAYLIGHT_FAIL: %s" % message)
    quit(1)

func _legacy_settings(world: WorldEnvironment, sun: DirectionalLight3D) -> void:
    var environment := world.environment
    environment.background_energy_multiplier = 0.86
    environment.ambient_light_color = Color(0.73, 0.76, 0.80, 1.0)
    environment.ambient_light_energy = 0.66
    environment.tonemap_exposure = 1.05
    environment.adjustment_enabled = true
    environment.adjustment_brightness = 1.01
    environment.adjustment_contrast = 1.08
    environment.adjustment_saturation = 0.92
    environment.fog_enabled = true
    environment.fog_light_color = Color(0.70, 0.72, 0.73, 1.0)
    environment.fog_light_energy = 0.54
    environment.fog_density = 0.0028
    environment.fog_sky_affect = 0.62
    var sky := environment.sky
    if sky != null and sky.sky_material is ProceduralSkyMaterial:
        var material := sky.sky_material as ProceduralSkyMaterial
        material.sky_top_color = Color(0.19, 0.27, 0.38, 1.0)
        material.sky_horizon_color = Color(0.70, 0.73, 0.72, 1.0)
        material.ground_bottom_color = Color(0.08, 0.075, 0.07, 1.0)
        material.ground_horizon_color = Color(0.38, 0.37, 0.35, 1.0)
        material.sun_angle_max = 18.0
        material.sun_curve = 0.12
    sun.rotation_degrees = Vector3(-42.0, -32.0, 0.0)
    sun.light_color = Color(1.0, 0.925, 0.79, 1.0)
    sun.light_energy = 1.06

func _freeze_runtime(node: Node) -> void:
    node.process_mode = Node.PROCESS_MODE_DISABLED
    for child: Node in node.get_children():
        _freeze_runtime(child)

func _capture(path: String) -> Image:
    for _i: int in range(6):
        RenderingServer.force_draw()
        await process_frame
    var image := root.get_texture().get_image()
    if image == null or image.is_empty():
        return Image.new()
    var absolute := ProjectSettings.globalize_path(path)
    var error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    if error != OK and error != ERR_ALREADY_EXISTS:
        return Image.new()
    if image.save_png(absolute) != OK:
        return Image.new()
    return image

func _luma(color: Color) -> float:
    return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b

func _compare(before: Image, after: Image) -> Dictionary:
    var changed := 0
    var total := WIDTH * HEIGHT
    var before_luma := 0.0
    var after_luma := 0.0
    var max_delta := 0.0
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
            if delta > DELTA_THRESHOLD:
                changed += 1
            max_delta = maxf(max_delta, delta)
            before_luma += _luma(a)
            after_luma += _luma(b)
    return {
        "changed_pixels_gt_3_rgb": changed,
        "total_pixels": total,
        "changed_ratio": float(changed) / float(total),
        "before_mean_luma": before_luma / float(total),
        "after_mean_luma": after_luma / float(total),
        "max_rgb_delta": max_delta,
    }

func _write_metrics(metrics: Dictionary) -> bool:
    var absolute := ProjectSettings.globalize_path(METRICS_JSON)
    var error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    if error != OK and error != ERR_ALREADY_EXISTS:
        return false
    var file := FileAccess.open(absolute, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(metrics, "  ") + "\n")
    return true

func _run() -> void:
    root.size = Vector2i(WIDTH, HEIGHT)
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene could not load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    for _i: int in range(WARMUP_FRAMES):
        await process_frame

    var world := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
    var sun := scene.get_node_or_null("Sun") as DirectionalLight3D
    var runtime := root.get_node_or_null("SharedEnvironmentDaylight")
    if world == null or world.environment == null or sun == null or runtime == null:
        _fail("production environment runtime nodes are missing")
        return
    if not runtime.has_method("apply_to") or not runtime.has_method("contract"):
        _fail("shared environment runtime contract is unavailable")
        return
    var contract: Dictionary = runtime.call("contract")
    if str(contract.get("schema", "")) != "grand-bruxelles-shared-neutral-daylight-v1":
        _fail("unexpected environment contract schema")
        return
    if int(contract.get("external_assets", -1)) != 0:
        _fail("shared daylight unexpectedly depends on an external asset")
        return

    _freeze_runtime(scene)
    _legacy_settings(world, sun)
    var before := await _capture(BEFORE_PNG)
    if before.is_empty() or before.get_width() != WIDTH or before.get_height() != HEIGHT:
        _fail("legacy capture failed")
        return

    if not bool(runtime.call("apply_to", world, sun)):
        _fail("runtime refused to apply shared daylight")
        return
    var after := await _capture(AFTER_PNG)
    if after.is_empty() or after.get_width() != WIDTH or after.get_height() != HEIGHT:
        _fail("daylight capture failed")
        return

    if not is_equal_approx(world.environment.fog_density, 0.0021):
        _fail("production fog density contract drifted")
        return
    if not is_equal_approx(world.environment.ambient_light_energy, 0.72):
        _fail("production ambient energy contract drifted")
        return
    if not is_equal_approx(sun.light_energy, 1.10):
        _fail("production sun energy contract drifted")
        return

    var metrics := _compare(before, after)
    if float(metrics["changed_ratio"]) < MIN_CHANGED_RATIO:
        _fail("player-frame impact %.4f is below %.4f" % [metrics["changed_ratio"], MIN_CHANGED_RATIO])
        return
    if float(metrics["after_mean_luma"]) <= 0.04 or float(metrics["after_mean_luma"]) >= 0.92:
        _fail("after frame mean luma is visually degenerate: %.4f" % metrics["after_mean_luma"])
        return
    if not _write_metrics(metrics):
        _fail("could not write A/B metrics")
        return

    print("SHARED_ENVIRONMENT_DAYLIGHT_OK: changed=%d/%d (%.2f%%) luma %.4f -> %.4f max_delta=%.4f" % [
        metrics["changed_pixels_gt_3_rgb"],
        metrics["total_pixels"],
        float(metrics["changed_ratio"]) * 100.0,
        metrics["before_mean_luma"],
        metrics["after_mean_luma"],
        metrics["max_rgb_delta"],
    ])
    quit(0)
