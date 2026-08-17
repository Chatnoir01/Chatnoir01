extends SceneTree

const SCRIPT := preload("res://game/scripts/grand_place_roi_espagne_facade_rhythm_runtime.gd")
const WIDTH := 1280
const HEIGHT := 720
const WARMUP_FRAMES := 90
const SETTLE_FRAMES := 8
const BEFORE_PATH := "res://artifacts/visual/roi_espagne_facade_before.png"
const AFTER_PATH := "res://artifacts/visual/roi_espagne_facade_after.png"
const MIN_CHANGED_3 := 0.015
const MIN_CHANGED_8 := 0.008
const CAMERA_POSITION := Vector3(319.01, 1.72, -535.20)
const FACADE_TARGET := Vector3(291.1278, 8.6, -582.8959)

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ROI_ESPAGNE_FACADE_WITNESS_FAIL: %s" % message)
    quit(1)

func _hide_noise(node: Node) -> void:
    if node is CanvasItem:
        (node as CanvasItem).visible = false
    var noisy := ["Player", "PrototypeCar", "PhysicalCarB", "TrafficManager", "NpcPopulationDirector", "NpcRuntimeIntegration", "MidiUrbanLife", "LivingCityShowcase", "LivingCityShowcaseRuntime", "MobilePlayabilityCollisionRuntime"]
    if node.name in noisy and node is Node3D:
        (node as Node3D).visible = false
    if node.name in noisy:
        node.process_mode = Node.PROCESS_MODE_DISABLED
    for child: Node in node.get_children():
        _hide_noise(child)

func _capture(viewport: SubViewport, output_path: String) -> Image:
    RenderingServer.force_draw()
    await process_frame
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty():
        return null
    var absolute := ProjectSettings.globalize_path(output_path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    if image.save_png(absolute) != OK:
        return null
    return image

func _changed_fraction(before: Image, after: Image, threshold: int) -> float:
    if before == null or after == null or before.get_size() != after.get_size():
        return -1.0
    var changed := 0
    var total := before.get_width() * before.get_height()
    var limit := float(threshold) / 255.0
    for y: int in range(before.get_height()):
        for x: int in range(before.get_width()):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            if max(abs(a.r - b.r), max(abs(a.g - b.g), abs(a.b - b.b))) > limit:
                changed += 1
    return float(changed) / float(total)

func _run() -> void:
    var autoload_runtime := root.get_node_or_null("GrandPlaceRoiEspagneFacadeRhythmRuntime") as Node3D
    if autoload_runtime != null:
        autoload_runtime.visible = false
        autoload_runtime.process_mode = Node.PROCESS_MODE_DISABLED

    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene missing")
        return
    var scene := packed.instantiate()
    if scene == null:
        _fail("main scene could not instantiate")
        return

    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    _hide_noise(scene)
    viewport.add_child(scene)

    var witness_runtime := SCRIPT.new()
    witness_runtime.name = "RoiEspagneFacadeWitnessRuntime"
    scene.add_child(witness_runtime)

    var current_camera := scene.get_viewport().get_camera_3d()
    if current_camera != null:
        current_camera.current = false
    var camera := Camera3D.new()
    camera.name = "RoiEspagnePlayerExposureCamera"
    camera.position = CAMERA_POSITION
    camera.fov = 62.0
    camera.current = true
    scene.add_child(camera)
    camera.look_at(FACADE_TARGET, Vector3.UP)

    for _frame: int in range(WARMUP_FRAMES):
        await process_frame
    _hide_noise(scene)

    if witness_runtime.diagnostic_register_count() != 3 or witness_runtime.diagnostic_opening_count() != 21:
        _fail("runtime did not build expected seven-bay three-register articulation")
        return

    witness_runtime.set_visual_enabled(false)
    for _frame: int in range(SETTLE_FRAMES):
        await process_frame
    var before := await _capture(viewport, BEFORE_PATH)
    if before == null:
        _fail("before capture failed")
        return

    witness_runtime.set_visual_enabled(true)
    for _frame: int in range(SETTLE_FRAMES):
        await process_frame
    var after := await _capture(viewport, AFTER_PATH)
    if after == null:
        _fail("after capture failed")
        return

    var changed_3 := _changed_fraction(before, after, 3)
    var changed_8 := _changed_fraction(before, after, 8)
    print("ROI_ESPAGNE_FACADE_METRICS: changed_gt3=%.6f changed_gt8=%.6f" % [changed_3, changed_8])
    if changed_3 < MIN_CHANGED_3:
        _fail("impact below >3 RGB gate: %.4f%% < %.4f%%" % [changed_3 * 100.0, MIN_CHANGED_3 * 100.0])
        return
    if changed_8 < MIN_CHANGED_8:
        _fail("impact below >8 RGB gate: %.4f%% < %.4f%%" % [changed_8 * 100.0, MIN_CHANGED_8 * 100.0])
        return

    print("ROI_ESPAGNE_FACADE_WITNESS_OK: changed_gt3=%.4f%% changed_gt8=%.4f%% camera=%s target=%s" % [changed_3 * 100.0, changed_8 * 100.0, str(CAMERA_POSITION), str(FACADE_TARGET)])
    viewport.queue_free()
    quit(0)
