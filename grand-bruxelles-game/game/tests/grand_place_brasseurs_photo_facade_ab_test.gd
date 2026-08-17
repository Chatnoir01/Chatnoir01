extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RUNTIME_NAME := "GrandPlaceBrasseursPhotoFacadeRuntime"
const WIDTH := 1280
const HEIGHT := 720
const CAMERA_POSITION := Vector3(319.01, 1.72, -535.20)
const CAMERA_TARGET := Vector3(321.9103, 11.8, -485.6594)
const CAMERA_FOV := 62.0
# Frozen from the previously accepted Brasseurs anti-micro harness. Never lower.
const MIN_CHANGED3_PERCENT := 1.2
const MIN_CHANGED8_PERCENT := 0.7

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_BRASSEURS_PHOTO_FACADE_AB_FAIL: %s" % message)
    quit(1)

func _walk(node: Node, out: Array[Node]) -> void:
    out.append(node)
    for child: Node in node.get_children():
        _walk(child, out)

func _mask_all_ui() -> int:
    var nodes: Array[Node] = []
    _walk(root, nodes)
    var masked := 0
    for node: Node in nodes:
        if node is CanvasLayer:
            var layer := node as CanvasLayer
            if layer.visible:
                layer.visible = false
                masked += 1
        elif node is CanvasItem:
            var item := node as CanvasItem
            if item.visible:
                item.visible = false
                masked += 1
    return masked

func _assert_ui_masked() -> bool:
    var nodes: Array[Node] = []
    _walk(root, nodes)
    for node: Node in nodes:
        if node is CanvasLayer and (node as CanvasLayer).visible:
            return false
        if node is CanvasItem and (node as CanvasItem).visible:
            return false
    return true

func _freeze_dynamics(main: Node) -> void:
    for group_name: String in ["vehicle", "npc"]:
        for node: Node in get_nodes_in_group(group_name):
            node.process_mode = Node.PROCESS_MODE_DISABLED
            if node is Node3D:
                (node as Node3D).visible = false
    for path: String in ["Player", "PrototypeCar", "PhysicalCar", "TrafficManager", "NpcPopulationDirector", "NpcRuntimeIntegration", "MidiUrbanLife"]:
        var node := main.get_node_or_null(path)
        if node != null:
            node.process_mode = Node.PROCESS_MODE_DISABLED
            if node is Node3D:
                (node as Node3D).visible = false

func _capture(path: String) -> Image:
    _mask_all_ui()
    if not _assert_ui_masked():
        return null
    for _frame: int in range(6):
        RenderingServer.force_draw()
        await process_frame
        _mask_all_ui()
    if not _assert_ui_masked():
        return null
    var image := root.get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        return null
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        image.resize(WIDTH, HEIGHT, Image.INTERPOLATE_LANCZOS)
    if image.save_png(path) != OK:
        return null
    return image

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
        if bool(runtime.get("facade_ready")):
            break
    if not bool(runtime.get("facade_ready")):
        _fail("facade not ready")
        return

    _freeze_dynamics(main)
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
        _mask_all_ui()
    if not _assert_ui_masked():
        _fail("UI mask invariant failed before capture")
        return

    runtime.call("set_facade_visible", false)
    for _frame: int in range(6): await process_frame
    var before := await _capture("/tmp/brasseurs-photo-before.png")
    runtime.call("set_facade_visible", true)
    for _frame: int in range(6): await process_frame
    var after := await _capture("/tmp/brasseurs-photo-after.png")
    if before == null or after == null:
        _fail("capture failed or UI remained visible")
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
                min_x = mini(min_x, x); min_y = mini(min_y, y)
                max_x = maxi(max_x, x); max_y = maxi(max_y, y)
            if d > 8.0:
                changed8 += 1

    var total := float(WIDTH * HEIGHT)
    var p3 := 100.0 * float(changed3) / total
    var p8 := 100.0 * float(changed8) / total
    if p3 < MIN_CHANGED3_PERCENT or p8 < MIN_CHANGED8_PERCENT:
        _fail("anti-micro failed changed3=%.4f%% changed8=%.4f%% thresholds=%.2f/%.2f" % [p3,p8,MIN_CHANGED3_PERCENT,MIN_CHANGED8_PERCENT])
        return
    if max_x < min_x or max_y < min_y:
        _fail("no changed-pixel bounding box")
        return

    print("GRAND_PLACE_BRASSEURS_PHOTO_FACADE_AB_OK: changed3=%.4f%% changed8=%.4f%% bbox=(%d,%d)-(%d,%d) player_spawn=true ui_masked=true dynamics_masked=true thresholds=1.20/0.70" % [p3,p8,min_x,min_y,max_x,max_y])
    quit(0)
