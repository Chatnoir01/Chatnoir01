extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RUNTIME_NAME := "GrandPlaceTownHallWindowRhythmRuntime"
const WIDTH := 1280
const HEIGHT := 720
const CAMERA_POSITION := Vector3(319.01, 1.72, -535.20)
const CAMERA_TARGET := Vector3(278.0, 14.0, -521.0)
const CAMERA_FOV := 62.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_TOWN_HALL_WINDOW_RHYTHM_AB_FAIL: %s" % message)
    quit(1)

func _capture(path: String) -> Image:
    for _frame: int in range(5):
        RenderingServer.force_draw()
        await process_frame
    var image := root.get_viewport().get_texture().get_image()
    if image == null or image.is_empty(): return null
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        image.resize(WIDTH, HEIGHT, Image.INTERPOLATE_LANCZOS)
    if image.save_png(path) != OK: return null
    return image

func _hide_dynamics(main: Node) -> void:
    for group_name: String in ["vehicle", "npc"]:
        for node: Node in get_nodes_in_group(group_name):
            node.process_mode = Node.PROCESS_MODE_DISABLED
            if node is Node3D: (node as Node3D).visible = false
    for path: String in ["Player", "PrototypeCar", "PhysicalCar", "TrafficManager", "NpcPopulationDirector", "NpcRuntimeIntegration", "MidiUrbanLife"]:
        var node := main.get_node_or_null(path)
        if node != null:
            node.process_mode = Node.PROCESS_MODE_DISABLED
            if node is Node3D: (node as Node3D).visible = false
    for name_value: String in ["LocationLabel", "MissionLabel", "SaveStatusLabel", "WalletLabel", "MiniMap", "MobileControls", "PrototypeLabel"]:
        var ui := main.get_node_or_null(name_value)
        if ui is CanvasItem: (ui as CanvasItem).visible = false

func _run() -> void:
    var runtime := root.get_node_or_null(RUNTIME_NAME)
    if runtime == null:
        _fail("runtime missing")
        return
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    for _frame: int in range(480):
        await process_frame
        if bool(runtime.get("articulation_ready")): break
    if not bool(runtime.get("articulation_ready")):
        _fail("articulation not ready")
        return
    _hide_dynamics(main)
    var old_camera := main.get_viewport().get_camera_3d()
    if old_camera != null: old_camera.current = false
    var camera := Camera3D.new()
    camera.position = CAMERA_POSITION
    camera.fov = CAMERA_FOV
    main.add_child(camera)
    camera.look_at(CAMERA_TARGET, Vector3.UP)
    camera.current = true
    for _frame: int in range(12): await process_frame

    runtime.call("set_articulation_visible", false)
    for _frame: int in range(6): await process_frame
    var before := await _capture("/tmp/grand-place-town-hall-window-rhythm-before.png")
    runtime.call("set_articulation_visible", true)
    for _frame: int in range(6): await process_frame
    var after := await _capture("/tmp/grand-place-town-hall-window-rhythm-after.png")
    if before == null or after == null:
        _fail("capture failed")
        return

    var changed3 := 0
    var changed8 := 0
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x,y)
            var b := after.get_pixel(x,y)
            var d := maxf(absf(a.r-b.r), maxf(absf(a.g-b.g), absf(a.b-b.b))) * 255.0
            if d > 3.0: changed3 += 1
            if d > 8.0: changed8 += 1
    var total := float(WIDTH * HEIGHT)
    var p3 := 100.0 * float(changed3) / total
    var p8 := 100.0 * float(changed8) / total
    # Fixed before first CI run. Do not lower to rescue the lot.
    if p3 < 1.0 or p8 < 0.6:
        _fail("anti-micro failed changed3=%.4f%% changed8=%.4f%%" % [p3,p8])
        return
    print("GRAND_PLACE_TOWN_HALL_WINDOW_RHYTHM_AB_OK: changed3=%.4f%% changed8=%.4f%% player_spawn=true dynamics_masked=true" % [p3,p8])
    quit(0)
