extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RUNTIME_NAME := "GrandPlaceLaBrouetteFacadeRuntime"
const WIDTH := 1280
const HEIGHT := 720
const CAMERA_POSITION := Vector3(319.01, 1.72, -535.20)
const CAMERA_TARGET := Vector3(283.67, 10.5, -574.72)
const CAMERA_FOV := 62.0
const MIN_CHANGED_3 := 1.2
const MIN_CHANGED_8 := 0.8
const BEFORE_PATH := "/tmp/grand-place-la-brouette-facade-before.png"
const AFTER_PATH := "/tmp/grand-place-la-brouette-facade-after.png"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_LA_BROUETTE_FACADE_AB_FAIL: %s" % message)
    quit(1)

func _hide_capture_noise(node: Node) -> void:
    if node is CanvasItem:
        (node as CanvasItem).visible = false
    if node is Label3D:
        (node as Label3D).visible = false
    for child: Node in node.get_children():
        _hide_capture_noise(child)

func _freeze_dynamics(main: Node) -> void:
    for group_name: String in ["vehicle", "npc"]:
        for node: Node in get_nodes_in_group(group_name):
            node.process_mode = Node.PROCESS_MODE_DISABLED
            if node is Node3D:
                (node as Node3D).visible = false
    for path: String in ["Player", "PrototypeCar", "PhysicalCar", "PhysicalCarB", "TrafficManager", "NpcPopulationDirector", "NpcRuntimeIntegration", "MidiUrbanLife"]:
        var node := main.get_node_or_null(path)
        if node != null:
            node.process_mode = Node.PROCESS_MODE_DISABLED
            if node is Node3D:
                (node as Node3D).visible = false
    _hide_capture_noise(root)

func _capture(path: String) -> Image:
    for _frame: int in range(6):
        RenderingServer.force_draw()
        await process_frame
    var image := root.get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        return null
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        image.resize(WIDTH, HEIGHT, Image.INTERPOLATE_LANCZOS)
    if image.save_png(path) != OK:
        return null
    return image

func _changed_percent(before: Image, after: Image, threshold: float) -> float:
    var changed := 0
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) * 255.0
            if delta > threshold:
                changed += 1
    return 100.0 * float(changed) / float(WIDTH * HEIGHT)

func _run() -> void:
    var runtime := root.get_node_or_null(RUNTIME_NAME)
    if runtime == null:
        _fail("runtime missing")
        return
    for _frame: int in range(180):
        await process_frame
        if bool(runtime.get("articulation_ready")):
            break
    if not bool(runtime.get("articulation_ready")):
        _fail("articulation not ready")
        return

    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    for _frame: int in range(60):
        await process_frame
    _freeze_dynamics(main)

    var old_camera := main.get_viewport().get_camera_3d()
    if old_camera != null:
        old_camera.current = false
    var camera := Camera3D.new()
    camera.name = "LaBrouettePlayerExposureCamera"
    camera.position = CAMERA_POSITION
    camera.fov = CAMERA_FOV
    main.add_child(camera)
    camera.look_at(CAMERA_TARGET, Vector3.UP)
    camera.current = true
    for _frame: int in range(12):
        await process_frame
    _freeze_dynamics(main)

    runtime.call("set_articulation_visible", false)
    for _frame: int in range(8):
        await process_frame
    var before := await _capture(BEFORE_PATH)
    runtime.call("set_articulation_visible", true)
    for _frame: int in range(8):
        await process_frame
    var after := await _capture(AFTER_PATH)
    if before == null or after == null:
        _fail("capture failed")
        return

    var changed3 := _changed_percent(before, after, 3.0)
    var changed8 := _changed_percent(before, after, 8.0)
    print("GRAND_PLACE_LA_BROUETTE_FACADE_METRICS: changed3=%.4f%% changed8=%.4f%%" % [changed3, changed8])
    if changed3 < MIN_CHANGED_3 or changed8 < MIN_CHANGED_8:
        _fail("anti-micro failed changed3=%.4f%%/%.4f%% changed8=%.4f%%/%.4f%%" % [changed3,MIN_CHANGED_3,changed8,MIN_CHANGED_8])
        return
    print("GRAND_PLACE_LA_BROUETTE_FACADE_AB_OK: changed3=%.4f%% changed8=%.4f%% player_spawn=true dynamics_masked=true ui_masked=true" % [changed3,changed8])
    quit(0)
