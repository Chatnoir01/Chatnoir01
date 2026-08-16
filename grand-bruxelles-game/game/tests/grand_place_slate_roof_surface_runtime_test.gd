extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const OUTPUT_DIR := "res://artifacts/grand-place/slate-roof-surface-runtime"
const WIDTH := 1280
const HEIGHT := 720
const CAMERA_POSITION := Vector3(365.0, 1.72, -505.0)
const CAMERA_TARGET := Vector3(279.5, 38.0, -515.0)
const CAMERA_FOV := 64.0
const MIN_CHANGED_RATIO := 0.015
const PIXEL_THRESHOLD := 3.0 / 255.0
const MIN_STRONG_CHANGED_RATIO := 0.005
const STRONG_PIXEL_THRESHOLD := 8.0 / 255.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_SLATE_ROOF_SURFACE_FAIL: %s" % message)
    quit(1)

func _hide_noise(main: Node) -> void:
    for name_value: String in ["LocationLabel", "MissionLabel", "SaveStatusLabel", "WalletLabel", "MiniMap", "MobileControls", "PrototypeLabel"]:
        var node := main.get_node_or_null(name_value)
        if node is CanvasItem:
            (node as CanvasItem).visible = false
    for path: String in ["Player", "PrototypeCar", "TrafficManager", "MidiUrbanLife"]:
        var node := main.get_node_or_null(path)
        if node is Node3D:
            (node as Node3D).visible = false
    var showcase := root.get_node_or_null("LivingCityShowcaseRuntime")
    if showcase != null:
        showcase.process_mode = Node.PROCESS_MODE_DISABLED
    var visible_runtime := root.get_node_or_null("VisibleCityRuntime")
    if visible_runtime != null and visible_runtime.has_method("_set_status"):
        visible_runtime.call("_set_status", "")

func _capture(path: String) -> Image:
    for _frame: int in range(5):
        RenderingServer.force_draw()
        await process_frame
    var image := root.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        return Image.new()
    var absolute := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    if image.save_png(absolute) != OK:
        return Image.new()
    return image

func _changed_ratio(before: Image, after: Image, threshold: float) -> float:
    var changed := 0
    var total := WIDTH * HEIGHT
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
            if delta > threshold:
                changed += 1
    return float(changed) / float(total)

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    for _frame: int in range(34):
        await process_frame

    var runtime := root.get_node_or_null("GrandPlaceSlateRoofSurfaceRuntime")
    if runtime == null:
        _fail("autoload missing")
        return
    if int(runtime.call("applied_surface_count")) != 2 or not bool(runtime.call("presentation_enabled")):
        _fail("expected two sourced LoD2 roof surfaces")
        return

    var townhall_roof := root.get_node_or_null("GrandPlaceOfficialLod2/GrandPlace1655673_ROOFSURFACE") as MeshInstance3D
    var ensemble_roof := root.get_node_or_null("GrandPlaceOfficialLod2Next/GrandPlace1786758_ROOFSURFACE") as MeshInstance3D
    if townhall_roof == null or ensemble_roof == null:
        _fail("Grand-Place roof surfaces missing")
        return
    for roof: MeshInstance3D in [townhall_roof, ensemble_roof]:
        if not roof.material_override is ShaderMaterial:
            _fail("source-backed roof did not receive procedural ShaderMaterial")
            return
        var material := roof.material_override as ShaderMaterial
        if str(material.get_meta("material_family", "")) != "brussels_source_verified_slate_roof":
            _fail("reusable slate material family missing")
            return
        if bool(material.get_meta("roofing_unit_pattern_authored", true)) or bool(material.get_meta("dormers_authored", true)) or bool(material.get_meta("geometry_changed", true)):
            _fail("slate presentation started inventing roof architecture")
            return
        if bool(material.get_meta("exact_rgb_is_photometric_measurement", true)):
            _fail("authored slate presentation was promoted to photometric truth")
            return

    _hide_noise(main)
    var player_camera := main.get_node_or_null("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if player_camera != null:
        player_camera.current = false
    var car_camera := main.get_node_or_null("PrototypeCar/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if car_camera != null:
        car_camera.current = false

    var camera := Camera3D.new()
    camera.name = "GrandPlaceSlateRoofSurfaceWitness"
    camera.position = CAMERA_POSITION
    camera.fov = CAMERA_FOV
    main.add_child(camera)
    camera.look_at(CAMERA_TARGET, Vector3.UP)
    camera.current = true

    runtime.call("set_enabled", false)
    for _frame: int in range(3):
        await process_frame
    var before := await _capture(OUTPUT_DIR + "/before.png")
    if before.is_empty():
        _fail("before capture failed")
        return

    runtime.call("set_enabled", true)
    for _frame: int in range(3):
        await process_frame
    var after := await _capture(OUTPUT_DIR + "/after.png")
    if after.is_empty():
        _fail("after capture failed")
        return

    var ratio := _changed_ratio(before, after, PIXEL_THRESHOLD)
    var strong_ratio := _changed_ratio(before, after, STRONG_PIXEL_THRESHOLD)
    if ratio < MIN_CHANGED_RATIO:
        _fail("broad visual delta too small: %.6f < %.6f" % [ratio, MIN_CHANGED_RATIO])
        return
    if strong_ratio < MIN_STRONG_CHANGED_RATIO:
        _fail("perceptible visual delta too small: %.6f < %.6f" % [strong_ratio, MIN_STRONG_CHANGED_RATIO])
        return

    print("GRAND_PLACE_SLATE_ROOF_SURFACE_OK: surfaces=2 changed_ratio=%.6f strong_ratio=%.6f thresholds=%.6f/%.6f before=%s after=%s" % [
        ratio, strong_ratio, MIN_CHANGED_RATIO, MIN_STRONG_CHANGED_RATIO,
        OUTPUT_DIR + "/before.png", OUTPUT_DIR + "/after.png"
    ])
    quit(0)
