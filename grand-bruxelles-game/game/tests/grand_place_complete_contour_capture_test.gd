extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const WARMUP_FRAMES := 140
const CONTRACT_PATH := "res://data/qa/grand_place_complete_contour_witness_contract.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_COMPLETE_CONTOUR_CAPTURE_FAIL: %s" % message)
    quit(1)

func _read_contract() -> Dictionary:
    if not FileAccess.file_exists(CONTRACT_PATH):
        return {}
    var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
    return value if typeof(value) == TYPE_DICTIONARY else {}

func _vec3(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.INF
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))

func _freeze_and_hide(scene: Node) -> void:
    for path: String in ["Player", "PrototypeCar", "MidiUrbanLife", "TrafficManager"]:
        var node := scene.get_node_or_null(path)
        if node != null:
            node.process_mode = Node.PROCESS_MODE_DISABLED
            if node is Node3D:
                (node as Node3D).visible = false
    for path: String in ["NpcPopulationDirector", "NpcRuntimeIntegration"]:
        var node := scene.get_node_or_null(path)
        if node != null:
            node.process_mode = Node.PROCESS_MODE_DISABLED
    var traffic := scene.get_node_or_null("TrafficManager")
    if traffic != null:
        traffic.set("auto_spawn_runtime", false)

func _hide_canvas_recursive(node: Node) -> void:
    if node is CanvasItem:
        (node as CanvasItem).visible = false
    for child: Node in node.get_children():
        _hide_canvas_recursive(child)

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 1:
        _fail("expected exactly one output PNG path")
        return
    var output_path := args[0]
    var contract := _read_contract()
    if contract.is_empty() or str(contract.get("schema", "")) != "grand-bruxelles-grand-place-complete-contour-witness-v2":
        _fail("witness v2 contract missing")
        return
    var capture_rules: Dictionary = contract.get("capture_rules", {})
    if not bool(capture_rules.get("shared_root_world3d_required", false)):
        _fail("shared World3D requirement missing")
        return
    var camera_contract: Dictionary = contract.get("camera", {})
    var resolution: Array = camera_contract.get("resolution", [])
    if resolution.size() != 2 or int(resolution[0]) != WIDTH or int(resolution[1]) != HEIGHT:
        _fail("frozen witness resolution drifted")
        return
    var camera_position := _vec3(camera_contract.get("position", []))
    var camera_target := _vec3(camera_contract.get("target", []))
    if not camera_position.is_finite() or not camera_target.is_finite():
        _fail("frozen witness camera invalid")
        return

    seed(711753)
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    if scene == null:
        _fail("main scene did not instantiate")
        return
    _freeze_and_hide(scene)

    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = false
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    viewport.add_child(scene)

    var witness_camera := Camera3D.new()
    witness_camera.name = "GrandPlaceFrozenWitnessCamera"
    witness_camera.position = camera_position
    witness_camera.fov = float(camera_contract.get("fov_degrees", 62.0))
    viewport.add_child(witness_camera)
    witness_camera.look_at(camera_target, Vector3.UP)
    witness_camera.current = true

    var contour := root.get_node_or_null("GrandPlaceCompleteContourRuntime")
    if contour != null and contour.has_method("bind_scene"):
        contour.call("bind_scene", scene)

    for _frame: int in range(WARMUP_FRAMES):
        await process_frame
    _hide_canvas_recursive(scene)

    for loader_name: String in ["GrandPlaceOfficialLod2", "GrandPlaceOfficialLod2Next"]:
        var loader := root.get_node_or_null(loader_name)
        if loader == null or not bool(loader.get("geometry_loaded")):
            _fail("existing production official loader not ready in witness: %s" % loader_name)
            return

    contour = root.get_node_or_null("GrandPlaceCompleteContourRuntime")
    if contour != null:
        if not contour.has_method("ready_complete") or not bool(contour.call("ready_complete")) or bool(contour.call("failed")):
            _fail("head contour runtime not complete")
            return
        if int(contour.call("owner_count")) != 23:
            _fail("head contour runtime owner count drifted")
            return
        var camera_world := witness_camera.get_world_3d()
        if camera_world == null:
            _fail("witness camera has no World3D")
            return
        if not contour.has_method("world_matches") or not bool(contour.call("world_matches", camera_world)):
            _fail("witness camera does not share contour runtime World3D")
            return
        if scene is Node3D and (scene as Node3D).get_world_3d() != camera_world:
            _fail("witness scene does not share contour runtime World3D")
            return

    scene.process_mode = Node.PROCESS_MODE_DISABLED
    RenderingServer.force_draw()
    await process_frame
    await process_frame
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty():
        _fail("capture image is empty")
        return
    if image.get_size() != Vector2i(WIDTH, HEIGHT):
        _fail("capture dimensions drifted")
        return

    var absolute := output_path if output_path.begins_with("/") else ProjectSettings.globalize_path(output_path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    if image.save_png(absolute) != OK:
        _fail("could not save PNG to %s" % absolute)
        return

    var contour_state := "absent"
    if contour != null:
        contour_state = "owners=%d render=%d degenerate=%d" % [int(contour.call("owner_count")), int(contour.get("render_triangle_count")), int(contour.get("degenerate_render_triangle_count"))]
    print("GRAND_PLACE_COMPLETE_CONTOUR_CAPTURE_OK: %s camera=%s target=%s fov=%.1f contour=%s shared_world3d=true" % [absolute, str(witness_camera.global_position), str(camera_target), witness_camera.fov, contour_state])
    viewport.queue_free()
    quit(0)
