extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const WARMUP_FRAMES := 140
const CONTRACT_PATH := "res://data/qa/grand_place_complete_contour_multiview_contract.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_MULTIVIEW_CAPTURE_FAIL: %s" % message)
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
        if typeof(raw_view) != TYPE_DICTIONARY:
            continue
        var view: Dictionary = raw_view
        if str(view.get("id", "")) == view_id:
            return view
    return {}

func _measure_center_ray_clearance(world: World3D, camera_position: Vector3, target: Vector3) -> Dictionary:
    if world == null or not camera_position.is_finite() or not target.is_finite():
        return {}
    var segment := target - camera_position
    var segment_length := segment.length()
    if not is_finite(segment_length) or segment_length <= 0.0001:
        return {}
    var query := PhysicsRayQueryParameters3D.create(camera_position, target)
    query.collide_with_areas = false
    query.collide_with_bodies = true
    var hit := world.direct_space_state.intersect_ray(query)
    if hit.is_empty():
        return {
            "hit": false,
            "clearance_m": segment_length,
            "segment_m": segment_length,
            "collider_path": "",
        }
    var hit_position: Variant = hit.get("position", null)
    if typeof(hit_position) != TYPE_VECTOR3 or not (hit_position as Vector3).is_finite():
        return {}
    var clearance := camera_position.distance_to(hit_position as Vector3)
    if not is_finite(clearance) or clearance < 0.0 or clearance > segment_length + 0.001:
        return {}
    var collider_path := ""
    var collider: Variant = hit.get("collider", null)
    if collider is Node:
        collider_path = str((collider as Node).get_path())
    return {
        "hit": true,
        "clearance_m": clearance,
        "segment_m": segment_length,
        "collider_path": collider_path,
    }

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 2:
        _fail("expected view id and output PNG path")
        return
    var view_id := str(args[0])
    var output_path := str(args[1])
    var contract := _read_contract()
    if contract.is_empty() or str(contract.get("schema", "")) != "grand-bruxelles-grand-place-complete-contour-multiview-v1":
        _fail("multiview contract missing")
        return
    var rules: Dictionary = contract.get("capture_rules", {})
    if not bool(rules.get("derive_views_only_by_exact_yaw_rotation_about_seed_target", false)) or not bool(rules.get("post_capture_camera_tuning_allowed", true)) == false:
        _fail("frozen multiview camera rules missing")
        return
    var seed_contract: Dictionary = contract.get("camera_seed", {})
    var resolution: Variant = seed_contract.get("resolution", [])
    if typeof(resolution) != TYPE_ARRAY or resolution.size() != 2 or int(resolution[0]) != WIDTH or int(resolution[1]) != HEIGHT:
        _fail("resolution drifted")
        return
    var seed_position := _exact_vec3(seed_contract.get("position", []))
    var target := _exact_vec3(seed_contract.get("target", []))
    if not seed_position.is_finite() or not target.is_finite():
        _fail("seed camera is invalid")
        return
    var view := _find_view(contract, view_id)
    if view.is_empty():
        _fail("unknown view id %s" % view_id)
        return
    var yaw_raw: Variant = view.get("yaw_degrees_from_seed", null)
    if typeof(yaw_raw) != TYPE_INT and typeof(yaw_raw) != TYPE_FLOAT:
        _fail("view yaw is not numeric")
        return
    var yaw := deg_to_rad(float(yaw_raw))
    if not is_finite(yaw):
        _fail("view yaw is not finite")
        return
    var seed_offset := seed_position - target
    var rotated_offset := seed_offset.rotated(Vector3.UP, yaw)
    var camera_position := target + rotated_offset
    if not camera_position.is_finite() or absf(rotated_offset.length() - seed_offset.length()) > 0.0001 or absf(camera_position.y - seed_position.y) > 0.0001:
        _fail("derived camera violated frozen seed radius/height")
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
    witness_camera.name = "GrandPlaceFrozenMultiviewCamera_%s" % view_id
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
    if contour == null or not contour.has_method("ready_complete") or not bool(contour.call("ready_complete")) or bool(contour.call("failed")):
        _fail("complete contour runtime not ready")
        return
    if int(contour.call("owner_count")) != 23:
        _fail("complete contour owner count drifted")
        return
    var camera_world := witness_camera.get_world_3d()
    if camera_world == null or not contour.has_method("world_matches") or not bool(contour.call("world_matches", camera_world)):
        _fail("camera/runtime World3D mismatch")
        return

    var clearance := _measure_center_ray_clearance(camera_world, camera_position, target)
    if clearance.is_empty():
        _fail("could not measure deterministic center-ray collision clearance")
        return
    print("GRAND_PLACE_MULTIVIEW_CLEARANCE_OK: view=%s hit=%s clearance_m=%.6f segment_m=%.6f ratio=%.6f collider=%s diagnostic_only=true selection_authorized=false" % [view_id, str(clearance["hit"]), float(clearance["clearance_m"]), float(clearance["segment_m"]), float(clearance["clearance_m"]) / float(clearance["segment_m"]), str(clearance["collider_path"])])

    scene.process_mode = Node.PROCESS_MODE_DISABLED
    RenderingServer.force_draw()
    await process_frame
    await process_frame
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty() or image.get_size() != Vector2i(WIDTH, HEIGHT):
        _fail("capture image invalid")
        return
    var absolute := output_path if output_path.begins_with("/") else ProjectSettings.globalize_path(output_path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    if image.save_png(absolute) != OK:
        _fail("could not save PNG")
        return
    print("GRAND_PLACE_MULTIVIEW_CAPTURE_OK: view=%s output=%s camera=%s target=%s fov=%.1f owners=23 deterministic_orbit=true" % [view_id, absolute, str(camera_position), str(target), witness_camera.fov])
    viewport.queue_free()
    quit(0)
