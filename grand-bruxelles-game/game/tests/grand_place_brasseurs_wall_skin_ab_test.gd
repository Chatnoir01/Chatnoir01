extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RUNTIME_SCRIPT := preload("res://game/scripts/grand_place_brasseurs_wall_skin_runtime.gd")
const SOURCE_PATH := "res://data/qa/grand_place_brasseurs_wall_skin_source.json"
const BEFORE_PATH := "/tmp/brasseurs-wall-before.png"
const AFTER_PATH := "/tmp/brasseurs-wall-after.png"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRASSEURS_WALL_SKIN_AB_FAIL: " + message)
    quit(1)

func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}

func _v3(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.INF
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))

func _walk(node: Node, out: Array[Node]) -> void:
    out.append(node)
    for child: Node in node.get_children():
        _walk(child, out)

func _mask_ui() -> void:
    var nodes: Array[Node] = []
    _walk(root, nodes)
    for node: Node in nodes:
        if node is CanvasLayer:
            (node as CanvasLayer).visible = false
        if node is CanvasItem:
            (node as CanvasItem).visible = false

func _visible_canvas_count() -> int:
    var nodes: Array[Node] = []
    _walk(root, nodes)
    var count := 0
    for node: Node in nodes:
        if node is CanvasItem and (node as CanvasItem).is_visible_in_tree():
            count += 1
    return count

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

func _capture(path: String, width: int, height: int) -> bool:
    for _frame: int in range(8):
        _mask_ui()
        RenderingServer.force_draw()
        await process_frame
    if _visible_canvas_count() != 0:
        return false
    var image := root.get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        return false
    if image.get_width() != width or image.get_height() != height:
        image.resize(width, height, Image.INTERPOLATE_LANCZOS)
    return image.save_png(path) == OK

func _run() -> void:
    var source := _read_json(SOURCE_PATH)
    if source.is_empty():
        _fail("wall source contract missing")
        return
    var gate: Dictionary = source.get("visual_gate", {})
    var camera_path := str(gate.get("camera_contract_path", ""))
    if camera_path != "res://data/qa/grand_place_clean_player_witness.json":
        _fail("A/B must consume shared #753 camera contract")
        return
    if not bool(gate.get("thresholds_frozen_before_first_candidate_render", false)):
        _fail("visual thresholds were not frozen before render")
        return
    var camera_contract := _read_json(camera_path)
    if camera_contract.is_empty() or str(camera_contract.get("schema", "")) != "grand-bruxelles-grand-place-clean-player-witness-v1":
        _fail("canonical camera contract missing or invalid")
        return
    if int(camera_contract.get("source_pr", 0)) != 711:
        _fail("canonical camera provenance drifted")
        return
    var resolution: Variant = camera_contract.get("resolution", [])
    if typeof(resolution) != TYPE_ARRAY or resolution.size() != 2:
        _fail("canonical camera resolution invalid")
        return
    var width := int(resolution[0])
    var height := int(resolution[1])
    if width != 1280 or height != 720 or int(gate.get("width", 0)) != width or int(gate.get("height", 0)) != height:
        _fail("canonical/gate resolution mismatch")
        return
    var camera_position := _v3(camera_contract.get("camera_position", []))
    var camera_target := _v3(camera_contract.get("camera_target", []))
    var camera_fov := float(camera_contract.get("camera_fov_deg", 0.0))
    if not camera_position.is_finite() or not camera_target.is_finite() or camera_fov <= 1.0 or camera_fov >= 179.0:
        _fail("canonical camera values invalid")
        return

    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main

    var runtime: Node3D = RUNTIME_SCRIPT.new()
    runtime.name = "BrasseursExactWallVisibilityCandidate"
    root.add_child(runtime)
    await process_frame
    if not bool(runtime.get("wall_ready")):
        _fail("exact wall runtime did not become ready")
        return
    var wall := runtime.get_node_or_null("GrandPlaceBrasseursWall10945501") as MeshInstance3D
    if wall == null or wall.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
        _fail("candidate must be shadow-disabled so diff cannot pass on shadow only")
        return

    runtime.call("set_wall_visible", false)
    var old_camera := main.get_viewport().get_camera_3d()
    if old_camera != null:
        old_camera.current = false
    var camera := Camera3D.new()
    camera.name = "CanonicalGrandPlaceWitnessCamera"
    camera.position = camera_position
    camera.fov = camera_fov
    main.add_child(camera)
    camera.look_at(camera_target, Vector3.UP)
    camera.current = true

    # Settle current production from the exact canonical witness while repeatedly
    # freezing dynamic/UI systems that can appear lazily after scene startup.
    for _frame: int in range(48):
        _freeze_dynamics(main)
        _mask_ui()
        await process_frame

    if not await _capture(BEFORE_PATH, width, height):
        _fail("BEFORE capture failed")
        return

    runtime.call("set_wall_visible", true)
    for _frame: int in range(8):
        _freeze_dynamics(main)
        _mask_ui()
        await process_frame
    if not await _capture(AFTER_PATH, width, height):
        _fail("AFTER capture failed")
        return

    print("BRASSEURS_WALL_SKIN_AB_CAPTURE_OK: camera_source_pr=711 size=1280x720 shadow=false details=0 offset=0 before=%s after=%s" % [BEFORE_PATH, AFTER_PATH])
    quit(0)
