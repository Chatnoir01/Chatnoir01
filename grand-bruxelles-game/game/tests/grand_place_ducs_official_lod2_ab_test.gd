extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const AUTOLOAD := "GrandPlaceDucsOfficialLod2"
const WIDTH := 1280
const HEIGHT := 720
const CAMERA_POSITION := Vector3(319.01, 1.72, -535.20)
const CAMERA_TARGET := Vector3(372.82, 13.50, -490.31)
const CAMERA_FOV := 62.0
const MIN_CHANGED_3_PERCENT := 5.0
const MIN_CHANGED_8_PERCENT := 2.0
const BEFORE_PATH := "/tmp/grand-place-ducs-before.png"
const AFTER_PATH := "/tmp/grand-place-ducs-after.png"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_DUCS_AB_FAIL: %s" % message)
    quit(1)

func _hide_dynamics(main: Node) -> void:
    for group_name: String in ["vehicle", "npc"]:
        for node: Node in get_nodes_in_group(group_name):
            node.process_mode = Node.PROCESS_MODE_DISABLED
            if node is Node3D:
                (node as Node3D).visible = false
    for path: String in ["Player", "PrototypeCar", "PhysicalCarB", "TrafficManager", "NpcPopulationDirector", "NpcRuntimeIntegration", "MidiUrbanLife"]:
        var node := main.get_node_or_null(path)
        if node != null:
            node.process_mode = Node.PROCESS_MODE_DISABLED
            if node is Node3D:
                (node as Node3D).visible = false
    for name_value: String in ["LocationLabel", "MissionLabel", "SaveStatusLabel", "WalletLabel", "MiniMap", "MobileControls", "PrototypeLabel"]:
        var ui := main.get_node_or_null(name_value)
        if ui is CanvasItem:
            (ui as CanvasItem).visible = false

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

func _run() -> void:
    var runtime := root.get_node_or_null(AUTOLOAD)
    if runtime == null:
        _fail("runtime missing")
        return
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    for _frame: int in range(480):
        await process_frame
        if bool(runtime.get("geometry_loaded")):
            break
    if not bool(runtime.get("geometry_loaded")):
        _fail("official Ducs LoD2 not ready")
        return
    _hide_dynamics(main)
    var old_camera := main.get_viewport().get_camera_3d()
    if old_camera != null:
        old_camera.current = false
    var camera := Camera3D.new()
    camera.position = CAMERA_POSITION
    camera.fov = CAMERA_FOV
    main.add_child(camera)
    camera.look_at(CAMERA_TARGET, Vector3.UP)
    camera.current = true
    for _frame: int in range(12):
        await process_frame

    runtime.call("set_official_visible", false)
    for _frame: int in range(8): await process_frame
    var before := await _capture(BEFORE_PATH)
    runtime.call("set_official_visible", true)
    for _frame: int in range(8): await process_frame
    var after := await _capture(AFTER_PATH)
    if before == null or after == null:
        _fail("capture failed")
        return

    var changed3 := 0
    var changed8 := 0
    var min_x := WIDTH
    var min_y := HEIGHT
    var max_x := -1
    var max_y := -1
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := maxf(absf(a.r-b.r), maxf(absf(a.g-b.g), absf(a.b-b.b))) * 255.0
            if delta > 3.0:
                changed3 += 1
                min_x = mini(min_x, x); min_y = mini(min_y, y)
                max_x = maxi(max_x, x); max_y = maxi(max_y, y)
            if delta > 8.0:
                changed8 += 1
    var total := float(WIDTH * HEIGHT)
    var p3 := 100.0 * float(changed3) / total
    var p8 := 100.0 * float(changed8) / total
    print("GRAND_PLACE_DUCS_AB_METRICS: changed3=%.4f%% changed8=%.4f%% bbox=(%d,%d)-(%d,%d) masked_osm=%d player_spawn=true dynamics_masked=true" % [p3, p8, min_x, min_y, max_x, max_y, int(runtime.get("masked_osm_count"))])
    if p3 < MIN_CHANGED_3_PERCENT or p8 < MIN_CHANGED_8_PERCENT:
        _fail("anti-micro failed changed3=%.4f%% changed8=%.4f%% required=%.2f%%/%.2f%%" % [p3, p8, MIN_CHANGED_3_PERCENT, MIN_CHANGED_8_PERCENT])
        return
    print("GRAND_PLACE_DUCS_AB_OK: changed3=%.4f%% changed8=%.4f%%" % [p3, p8])
    quit(0)
