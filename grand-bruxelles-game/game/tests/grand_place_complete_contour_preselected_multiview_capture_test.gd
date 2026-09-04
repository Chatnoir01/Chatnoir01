extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const WARMUP_FRAMES := 140
const CONTRACT_PATH := "res://data/qa/grand_place_complete_contour_preselected_multiview_contract.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_PRESELECTED_MULTIVIEW_FAIL: %s" % message)
    quit(1)

func _read_contract() -> Dictionary:
    if not FileAccess.file_exists(CONTRACT_PATH):
        return {}
    var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
    return value if typeof(value) == TYPE_DICTIONARY else {}

func _exact_vec3(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.INF
    for component: Variant in raw:
        var t := typeof(component)
        if t != TYPE_INT and t != TYPE_FLOAT:
            return Vector3.INF
    var value := Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
    return value if value.is_finite() else Vector3.INF

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

func _find_view(contract: Dictionary, view_id: String) -> Dictionary:
    var views: Variant = contract.get("views", [])
    if typeof(views) != TYPE_ARRAY:
        return {}
    for raw_view: Variant in views:
        if typeof(raw_view) == TYPE_DICTIONARY and str((raw_view as Dictionary).get("id", "")) == view_id:
            return raw_view as Dictionary
    return {}

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 2:
        _fail("expected view id and output PNG path")
        return
    var view_id := str(args[0])
    var output_path := str(args[1])
    var contract := _read_contract()
    if str(contract.get("schema", "")) != "grand-bruxelles-grand-place-preselected-multiview-v1":
        _fail("preselected contract missing")
        return
    var provenance: Dictionary = contract.get("selection_provenance", {})
    if str(provenance.get("source_head", "")) != "125b980f200c87f8ad3e30199f4390a979873666" or int(provenance.get("workflow_run_id", 0)) != 33834994119 or int(provenance.get("artifact_id", 0)) != 9922999722 or str(provenance.get("selection_stage", "")) != "before_png_capture":
        _fail("selection provenance drifted")
        return
    var rules: Dictionary = contract.get("capture_rules", {})
    if not bool(rules.get("selection_is_pinned_before_capture", false)) or bool(rules.get("post_capture_reselection_allowed", true)) or not bool(rules.get("owner_full_frame_review_required", false)):
        _fail("pre-capture selection rails drifted")
        return
    var seed_contract: Dictionary = contract.get("camera_seed", {})
    var resolution: Variant = seed_contract.get("resolution", [])
    if typeof(resolution) != TYPE_ARRAY or resolution.size() != 2 or int(resolution[0]) != WIDTH or int(resolution[1]) != HEIGHT:
        _fail("resolution drifted")
        return
    var seed_position := _exact_vec3(seed_contract.get("position", []))
    var target := _exact_vec3(seed_contract.get("target", []))
    if not seed_position.is_finite() or not target.is_finite():
        _fail("seed camera invalid")
        return
    var view := _find_view(contract, view_id)
    if view.is_empty():
        _fail("unknown selected view %s" % view_id)
        return
    var yaw_raw: Variant = view.get("yaw_degrees_from_seed", null)
    if typeof(yaw_raw) != TYPE_INT and typeof(yaw_raw) != TYPE_FLOAT:
        _fail("selected yaw invalid")
        return
    var yaw_degrees := float(yaw_raw)
    if not is_finite(yaw_degrees):
        _fail("selected yaw non-finite")
        return
    var seed_offset := seed_position - target
    var rotated_offset := seed_offset.rotated(Vector3.UP, deg_to_rad(yaw_degrees))
    var camera_position := target + rotated_offset
    if not camera_position.is_finite() or absf(rotated_offset.length() - seed_offset.length()) > 0.0001 or absf(camera_position.y - seed_position.y) > 0.0001:
        _fail("selected camera violated frozen radius/height")
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
    witness_camera.name = "GrandPlacePreselectedCamera_%s" % view_id
    witness_camera.position = camera_position
    witness_camera.fov = float(seed_contract.get("fov_degrees", 62.0))
    viewport.add_child(witness_camera)
    witness_camera.look_at(target, Vector3.UP)
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
            _fail("official loader not ready: %s" % loader_name)
            return
    contour = root.get_node_or_null("GrandPlaceCompleteContourRuntime")
    if contour == null or not contour.has_method("ready_complete") or not bool(contour.call("ready_complete")) or bool(contour.call("failed")) or int(contour.call("owner_count")) != 23:
        _fail("complete contour runtime not ready")
        return
    var camera_world := witness_camera.get_world_3d()
    if camera_world == null or not contour.has_method("world_matches") or not bool(contour.call("world_matches", camera_world)):
        _fail("camera/runtime World3D mismatch")
        return

    scene.process_mode = Node.PROCESS_MODE_DISABLED
    RenderingServer.force_draw()
    await process_frame
    await process_frame
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty() or image.get_size() != Vector2i(WIDTH, HEIGHT):
        _fail("capture invalid")
        return
    var absolute := output_path if output_path.begins_with("/") else ProjectSettings.globalize_path(output_path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    if image.save_png(absolute) != OK:
        _fail("could not save PNG")
        return
    print("GRAND_PLACE_PRESELECTED_MULTIVIEW_OK: view=%s quadrant=%s yaw=%.0f output=%s owners=23 selection_pinned_before_capture=true owner_review_required=true visual_acceptance=false jouable_authorized=false" % [view_id, str(view.get("quadrant", "")), yaw_degrees, absolute])
    viewport.queue_free()
    quit(0)
