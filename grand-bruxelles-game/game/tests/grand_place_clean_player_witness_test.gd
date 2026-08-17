extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const WIDTH := 1280
const HEIGHT := 720
const CAMERA_POSITION := Vector3(319.01, 1.72, -535.20)
const CAMERA_TARGET := Vector3(321.91, 11.8, -485.66)

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_CLEAN_WITNESS_FAIL: %s" % message)
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

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    _freeze(main)

    var old_camera := main.get_viewport().get_camera_3d()
    if old_camera != null:
        old_camera.current = false
    var camera := Camera3D.new()
    camera.position = CAMERA_POSITION
    camera.fov = 62.0
    main.add_child(camera)
    camera.look_at(CAMERA_TARGET, Vector3.UP)
    camera.current = true

    # UI systems may create controls lazily after scene startup. Keep masking across
    # a long enough deterministic settling window, then assert none survive.
    for _i: int in range(30):
        _mask_all_canvas()
        await process_frame
    _mask_all_canvas()
    await process_frame

    var survivors := _visible_canvas_items()
    if not survivors.is_empty():
        _fail("visible CanvasItem survivors after recursive mask: %s" % ", ".join(survivors.slice(0, mini(12, survivors.size()))))
        return

    for _i: int in range(6):
        RenderingServer.force_draw()
        _mask_all_canvas()
        await process_frame
        survivors = _visible_canvas_items()
        if not survivors.is_empty():
            _fail("UI reappeared before capture: %s" % ", ".join(survivors.slice(0, mini(12, survivors.size()))))
            return

    var image := root.get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        _fail("capture failed")
        return
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        image.resize(WIDTH, HEIGHT, Image.INTERPOLATE_LANCZOS)
    if image.save_png("/tmp/grand-place-clean-player-witness.png") != OK:
        _fail("could not save clean witness")
        return

    print("GRAND_PLACE_CLEAN_WITNESS_OK: size=1280x720 player_spawn=true canvas_items_visible=0 dynamics_masked=true")
    quit(0)
