extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const WIDTH := 1280
const HEIGHT := 720
const CAMERA_POSITION := Vector3(319.01, 1.72, -535.20)
const CAMERA_TARGET := Vector3(321.9103, 11.8, -485.6594)
const CAMERA_FOV := 62.0
const OUTPUT := "/tmp/grand-place-brasseurs-clean-frame.png"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_BRASSEURS_CLEAN_FRAME_FAIL: %s" % message)
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
            layer.process_mode = Node.PROCESS_MODE_DISABLED
        elif node is CanvasItem:
            var item := node as CanvasItem
            if item.visible:
                item.visible = false
                masked += 1
            node.process_mode = Node.PROCESS_MODE_DISABLED
    return masked

func _visible_ui_paths() -> PackedStringArray:
    var nodes: Array[Node] = []
    _walk(root, nodes)
    var visible := PackedStringArray()
    for node: Node in nodes:
        if node is CanvasLayer and (node as CanvasLayer).visible:
            visible.append(str(node.get_path()))
        elif node is CanvasItem and (node as CanvasItem).visible:
            visible.append(str(node.get_path()))
    return visible

func _named_ui_survivors() -> PackedStringArray:
    var nodes: Array[Node] = []
    _walk(root, nodes)
    var survivors := PackedStringArray()
    for node: Node in nodes:
        var descriptor := (String(node.name) + " " + str(node.get_path())).to_lower()
        if node is Label:
            descriptor += " " + (node as Label).text.to_lower()
        var targeted := "mission" in descriptor or "minimap" in descriptor or "money" in descriptor or "argent" in descriptor or "signal" in descriptor or "zones" in descriptor
        if not targeted:
            continue
        if node is CanvasLayer and (node as CanvasLayer).visible:
            survivors.append(str(node.get_path()))
        elif node is CanvasItem and (node as CanvasItem).visible:
            survivors.append(str(node.get_path()))
    return survivors

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

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    for _frame: int in range(24):
        await process_frame

    _freeze_dynamics(main)
    var old_camera := main.get_viewport().get_camera_3d()
    if old_camera != null:
        old_camera.current = false
    var camera := Camera3D.new()
    camera.name = "BrasseursCleanFrameCamera"
    camera.position = CAMERA_POSITION
    camera.fov = CAMERA_FOV
    main.add_child(camera)
    camera.look_at(CAMERA_TARGET, Vector3.UP)
    camera.current = true

    var masked_total := 0
    for _frame: int in range(16):
        masked_total += _mask_all_ui()
        await process_frame
    var visible_before := _visible_ui_paths()
    if not visible_before.is_empty():
        _fail("visible Canvas UI survived pre-draw mask: %s" % [visible_before])
        return
    var named_before := _named_ui_survivors()
    if not named_before.is_empty():
        _fail("mission/minimap/money UI survived pre-draw mask: %s" % [named_before])
        return

    _mask_all_ui()
    RenderingServer.force_draw()
    await RenderingServer.frame_post_draw
    _mask_all_ui()
    var visible_after := _visible_ui_paths()
    if not visible_after.is_empty():
        _fail("visible Canvas UI reappeared at capture: %s" % [visible_after])
        return
    var named_after := _named_ui_survivors()
    if not named_after.is_empty():
        _fail("mission/minimap/money UI reappeared at capture: %s" % [named_after])
        return

    var image := root.get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        _fail("clean player-eye capture missing")
        return
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        image.resize(WIDTH, HEIGHT, Image.INTERPOLATE_LANCZOS)
    if image.save_png(OUTPUT) != OK:
        _fail("could not save clean-frame PNG")
        return

    print("GRAND_PLACE_BRASSEURS_CLEAN_FRAME_OK: player_eye=true resolution=1280x720 masked_events=%d visible_canvas_items=0 named_ui_survivors=0 dynamics_masked=true" % masked_total)
    quit(0)
