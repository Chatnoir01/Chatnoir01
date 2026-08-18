extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const CONTRACT_PATH := "res://data/qa/grand_place_clean_player_witness.json"
const WIDTH := 1280
const HEIGHT := 720
const EXPECTED_CAMERA_POSITION := Vector3(319.01, 1.72, -535.20)
const EXPECTED_CAMERA_TARGET := Vector3(321.91, 11.8, -485.66)
const EXPECTED_CAMERA_FOV := 62.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_CLEAN_WITNESS_FAIL: %s" % message)
    quit(1)

func _read_contract() -> Dictionary:
    if not FileAccess.file_exists(CONTRACT_PATH):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
    return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}

func _v3(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.INF
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))

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
    var contract := _read_contract()
    if contract.is_empty():
        _fail("canonical camera contract missing or invalid")
        return
    if str(contract.get("schema", "")) != "grand-bruxelles-grand-place-clean-player-witness-v1":
        _fail("canonical camera contract schema drifted")
        return
    if int(contract.get("source_pr", 0)) != 711:
        _fail("canonical camera contract no longer identifies merged PR #711")
        return
    var resolution: Variant = contract.get("resolution", [])
    if typeof(resolution) != TYPE_ARRAY or resolution.size() != 2 or int(resolution[0]) != WIDTH or int(resolution[1]) != HEIGHT:
        _fail("canonical camera resolution drifted")
        return
    var camera_position := _v3(contract.get("camera_position", []))
    var camera_target := _v3(contract.get("camera_target", []))
    var camera_fov := float(contract.get("camera_fov_deg", 0.0))
    if not camera_position.is_finite() or camera_position.distance_to(EXPECTED_CAMERA_POSITION) > 0.0001:
        _fail("canonical #711 camera position drifted")
        return
    if not camera_target.is_finite() or camera_target.distance_to(EXPECTED_CAMERA_TARGET) > 0.0001:
        _fail("canonical #711 camera target drifted")
        return
    if absf(camera_fov - EXPECTED_CAMERA_FOV) > 0.0001:
        _fail("canonical #711 camera FOV drifted")
        return
    if not bool(contract.get("player_eye", false)) or not bool(contract.get("ui_mask_required", false)) or not bool(contract.get("dynamics_mask_required", false)):
        _fail("canonical witness safety flags drifted")
        return

    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    _freeze(main)

    var old_camera := main.get_viewport().get_camera_3d()
    if old_camera != null:
        old_camera.current = false
    var camera := Camera3D.new()
    camera.position = camera_position
    camera.fov = camera_fov
    main.add_child(camera)
    camera.look_at(camera_target, Vector3.UP)
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

    print("GRAND_PLACE_CLEAN_WITNESS_OK: size=1280x720 camera_contract=pr711 camera=(319.01,1.72,-535.20) fov=62 canvas_items_visible=0 dynamics_masked=true")
    quit(0)
