extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const WIDTH := 1280
const HEIGHT := 720
const CAMERA_POSITION := Vector3(324.9581, 3.3, -512.8388)
const CAMERA_TARGET := Vector3(321.9103, 11.8, -485.6584)
const CAMERA_FOV := 62.0
const RUNTIME_PATH := NodePath("GrandPlaceWhiteStoneSurfaceRuntime/GrandPlaceBrasseursWallSkinRuntime")
const BEFORE_PATH := "/tmp/brasseurs-wall-before.png"
const AFTER_PATH := "/tmp/brasseurs-wall-after.png"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRASSEURS_WALL_SKIN_AB_FAIL: " + message)
    quit(1)

func _walk(node: Node, out: Array[Node]) -> void:
    out.append(node)
    for child: Node in node.get_children():
        _walk(child, out)

func _mask_all_canvas() -> void:
    var nodes: Array[Node] = []
    _walk(root, nodes)
    for node: Node in nodes:
        if node is CanvasLayer:
            (node as CanvasLayer).visible = false
        if node is CanvasItem:
            (node as CanvasItem).visible = false

func _visible_canvas_items() -> Array[String]:
    var nodes: Array[Node] = []
    var visible_paths: Array[String] = []
    _walk(root, nodes)
    for node: Node in nodes:
        if node is CanvasItem and (node as CanvasItem).is_visible_in_tree():
            visible_paths.append(str(node.get_path()))
    return visible_paths

func _freeze(main: Node) -> void:
    for group_name: String in ["vehicle", "npc", "ambient_pedestrian", "ambient_traffic", "police"]:
        for node: Node in get_nodes_in_group(group_name):
            node.process_mode = Node.PROCESS_MODE_DISABLED
            if node is Node3D:
                (node as Node3D).visible = false
    for path: String in [
        "Player", "PrototypeCar", "PhysicalCar", "TrafficManager", "NpcPopulationDirector",
        "NpcRuntimeIntegration", "MidiUrbanLife", "LivingCityShowcaseRuntime"
    ]:
        var node := main.get_node_or_null(path)
        if node != null:
            node.process_mode = Node.PROCESS_MODE_DISABLED
            if node is Node3D:
                (node as Node3D).visible = false

func _capture(path: String) -> bool:
    for _i: int in range(8):
        _mask_all_canvas()
        RenderingServer.force_draw()
        await process_frame
    var survivors := _visible_canvas_items()
    if not survivors.is_empty():
        _fail("visible CanvasItem survivors: %s" % ", ".join(survivors.slice(0, mini(12, survivors.size()))))
        return false
    var image := root.get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        _fail("capture failed")
        return false
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        image.resize(WIDTH, HEIGHT, Image.INTERPOLATE_LANCZOS)
    if image.save_png(path) != OK:
        _fail("could not save %s" % path)
        return false
    return true

func _run() -> void:
    var runtime: Node = null
    for _frame: int in range(30):
        runtime = root.get_node_or_null(RUNTIME_PATH)
        if runtime != null and runtime.has_method("set_candidate_visible"):
            break
        await process_frame
    if runtime == null or not runtime.has_method("set_candidate_visible"):
        _fail("production Brasseurs wall-skin integration not mounted")
        return

    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    _freeze(main)

    var old_camera := main.get_viewport().get_camera_3d()
    if old_camera != null:
        old_camera.current = false
    var camera := Camera3D.new()
    camera.position = CAMERA_POSITION
    camera.fov = CAMERA_FOV
    main.add_child(camera)
    camera.look_at(CAMERA_TARGET, Vector3.UP)
    camera.current = true

    for _i: int in range(30):
        _mask_all_canvas()
        await process_frame

    runtime.call("set_candidate_visible", false)
    if not await _capture(BEFORE_PATH):
        return
    runtime.call("set_candidate_visible", true)
    if not await _capture(AFTER_PATH):
        return

    print("BRASSEURS_WALL_SKIN_AB_OK: size=1280x720 camera=(324.9581,3.3,-512.8388) fov=62 dynamics_masked=true canvas_visible=0 details=0")
    quit(0)
