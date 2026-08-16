extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const AUTOLOAD_NAME := "GrandPlaceMaisonDuRoiOfficialLod2"
const WIDTH := 1280
const HEIGHT := 720
const CAMERA_POSITION := Vector3(342.0, 8.5, -514.0)
const CAMERA_TARGET := Vector3(342.0, 13.0, -566.0)
const CAMERA_FOV := 57.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_MAISON_DU_ROI_AB_FAIL: %s" % message)
    quit(1)

func _hide_dynamic(main: Node) -> void:
    for path: String in ["Player", "PrototypeCar", "PhysicalCar", "TrafficManager", "NpcPopulationDirector", "NpcRuntimeIntegration", "MidiUrbanLife"]:
        var node := main.get_node_or_null(path)
        if node == null:
            continue
        node.process_mode = Node.PROCESS_MODE_DISABLED
        if node is Node3D:
            (node as Node3D).visible = false
    for node: Node in get_nodes_in_group("vehicle"):
        node.process_mode = Node.PROCESS_MODE_DISABLED
        if node is Node3D:
            (node as Node3D).visible = false
    for node: Node in get_nodes_in_group("npc"):
        node.process_mode = Node.PROCESS_MODE_DISABLED
        if node is Node3D:
            (node as Node3D).visible = false

func _capture(path: String) -> Image:
    RenderingServer.force_draw()
    await process_frame
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
    var main: Node = null
    var official := get_root().get_node_or_null(AUTOLOAD_NAME)
    if official == null:
        _fail("Maison du Roi autoload missing")
        return
    for _frame: int in range(480):
        await process_frame
        main = current_scene
        if main != null and main.scene_file_path == MAIN_SCENE and bool(official.get("geometry_loaded")):
            break
    if main == null or not bool(official.get("geometry_loaded")):
        _fail("main scene or official geometry did not become ready")
        return

    _hide_dynamic(main)
    var existing_camera := main.get_viewport().get_camera_3d()
    if existing_camera != null:
        existing_camera.current = false
    var camera := Camera3D.new()
    camera.name = "MaisonDuRoiWitnessCamera"
    camera.position = CAMERA_POSITION
    camera.fov = CAMERA_FOV
    camera.current = true
    main.add_child(camera)
    camera.look_at(CAMERA_TARGET, Vector3.UP)

    for _frame: int in range(12):
        await process_frame

    official.call("set_official_visible", false)
    for _frame: int in range(6):
        await process_frame
    var before := await _capture("/tmp/grand-place-maison-du-roi-before.png")
    if before == null:
        _fail("before capture failed")
        return

    official.call("set_official_visible", true)
    for _frame: int in range(6):
        await process_frame
    var after := await _capture("/tmp/grand-place-maison-du-roi-after.png")
    if after == null:
        _fail("after capture failed")
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
            var d := maxf(absf(a.r-b.r), maxf(absf(a.g-b.g), absf(a.b-b.b))) * 255.0
            if d > 3.0:
                changed3 += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
            if d > 8.0:
                changed8 += 1
    var total := WIDTH * HEIGHT
    var p3 := 100.0 * float(changed3) / float(total)
    var p8 := 100.0 * float(changed8) / float(total)
    if p3 < 2.0 or p8 < 0.8:
        _fail("anti-micro gate failed: changed3=%.4f%% changed8=%.4f%%" % [p3, p8])
        return
    print("GRAND_PLACE_MAISON_DU_ROI_AB_OK: changed3=%d %.4f%% changed8=%d %.4f%% bbox=%d,%d..%d,%d camera=(%.1f,%.1f,%.1f) fov=%.1f dynamics_masked=true" % [changed3,p3,changed8,p8,min_x,min_y,max_x,max_y,CAMERA_POSITION.x,CAMERA_POSITION.y,CAMERA_POSITION.z,CAMERA_FOV])
    quit(0)
