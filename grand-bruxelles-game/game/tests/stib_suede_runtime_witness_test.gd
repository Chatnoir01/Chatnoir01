extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/stib_suede_runtime.gd")
const WIDTH := 1280
const HEIGHT := 720
const WARMUP_FRAMES := 70
const BEFORE_PATH := "res://artifacts/visual/stib_suede_runtime_before.png"
const AFTER_PATH := "res://artifacts/visual/stib_suede_runtime_after.png"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("STIB_SUEDE_RUNTIME_WITNESS_FAIL: %s" % message)
    quit(1)

func _hide_noise(scene: Node) -> void:
    for node_path: String in ["LocationLabel", "MissionLabel", "PrototypeLabel", "MiniMap", "MobileControls", "WalletHud"]:
        var item := scene.get_node_or_null(node_path) as CanvasItem
        if item != null:
            item.visible = false
    for node_path: String in ["Player", "PrototypeCar", "PhysicalCarB"]:
        var spatial := scene.get_node_or_null(node_path) as Node3D
        if spatial != null:
            spatial.visible = false

func _capture(viewport: SubViewport, output_path: String) -> Image:
    RenderingServer.force_draw()
    await process_frame
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        _fail("invalid capture for %s" % output_path)
        return null
    var absolute := ProjectSettings.globalize_path(output_path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    if image.save_png(absolute) != OK:
        _fail("could not save %s" % output_path)
        return null
    return image

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    var scene := packed.instantiate() as Node3D
    if scene == null:
        _fail("production scene did not instantiate")
        return

    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    viewport.add_child(scene)
    _hide_noise(scene)

    var existing_camera := scene.get_viewport().get_camera_3d()
    if existing_camera != null:
        existing_camera.current = false

    var camera := Camera3D.new()
    camera.name = "SuedeNormalDistanceWitnessCamera"
    camera.position = Vector3(-845.39, 2.25, 877.49)
    camera.fov = 62.0
    camera.current = true
    scene.add_child(camera)
    camera.look_at(Vector3(-856.297, 2.25, 868.715), Vector3.UP)

    for _frame in range(WARMUP_FRAMES):
        await process_frame
    _hide_noise(scene)
    var before := await _capture(viewport, BEFORE_PATH)
    if before == null:
        return

    var runtime := RUNTIME_SCRIPT.new()
    runtime.name = "SuedeRuntimeWitness"
    scene.add_child(runtime)
    for _frame in range(WARMUP_FRAMES):
        await process_frame
    _hide_noise(scene)
    var after := await _capture(viewport, AFTER_PATH)
    if after == null:
        return

    var changed_3 := 0
    var changed_8 := 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := maxi(maxi(absi(int(round((a.r - b.r) * 255.0))), absi(int(round((a.g - b.g) * 255.0)))), absi(int(round((a.b - b.b) * 255.0))))
            if delta > 3:
                changed_3 += 1
            if delta > 8:
                changed_8 += 1
    var total := WIDTH * HEIGHT
    var ratio_3 := 100.0 * float(changed_3) / float(total)
    var ratio_8 := 100.0 * float(changed_8) / float(total)
    if changed_3 < 5500 or ratio_3 < 0.60:
        _fail("normal-distance cue too small: %d pixels / %.4f%% >3 RGB" % [changed_3, ratio_3])
        return

    print("STIB_SUEDE_RUNTIME_WITNESS_OK before=%s after=%s changed_gt3=%d ratio_gt3=%.4f%% changed_gt8=%d ratio_gt8=%.4f%% camera_distance_normal=true" % [BEFORE_PATH, AFTER_PATH, changed_3, ratio_3, changed_8, ratio_8])
    quit(0)
