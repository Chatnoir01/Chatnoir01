extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const WARMUP_FRAMES := 90
const EVIDENCE_PATH := "res://data/qa/photo_match/bourse_2019_geotagged_camera_evidence.json"
const BEFORE_PATH := "res://artifacts/bourse/roof-source-face-smoothing/before.png"
const AFTER_PATH := "res://artifacts/bourse/roof-source-face-smoothing/after.png"


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("BOURSE_ROOF_SOURCE_FACE_SMOOTHING_VISUAL_FAIL: %s" % message)
    quit(1)


func _vector3(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.ZERO
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))


func _horizontal_to_vertical_fov(horizontal_degrees: float, aspect: float) -> float:
    if horizontal_degrees <= 0.0 or horizontal_degrees >= 179.0 or aspect <= 0.0:
        return -1.0
    return rad_to_deg(2.0 * atan(tan(deg_to_rad(horizontal_degrees) * 0.5) / aspect))


func _hide_generated_labels(node: Node) -> void:
    if node is Label3D:
        (node as Label3D).visible = false
    for child: Node in node.get_children():
        _hide_generated_labels(child)


func _hide_capture_noise(scene: Node) -> void:
    for node_path: String in ["LocationLabel", "MissionLabel", "PrototypeLabel", "MiniMap", "MobileControls"]:
        var item := scene.get_node_or_null(node_path) as CanvasItem
        if item != null:
            item.visible = false
    for node_path: String in ["Player", "PrototypeCar", "PhysicalCarB", "MidiHeroZone"]:
        var spatial := scene.get_node_or_null(node_path) as Node3D
        if spatial != null:
            spatial.visible = false
    _hide_generated_labels(scene)


func _camera_contract() -> Dictionary:
    if not FileAccess.file_exists(EVIDENCE_PATH):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EVIDENCE_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    var evidence := parsed as Dictionary
    if str(evidence.get("schema", "")) != "grand-bruxelles-bourse-geotagged-camera-evidence-v1":
        return {}
    return evidence.get("candidate_game_camera_transform", {}) as Dictionary


func _wait_for_reveal(scene: Node) -> bool:
    for _frame: int in range(30):
        await process_frame
        var roofs := scene.get_node_or_null("UrbISHeroGeometry/Hero_Bourse/Roofs") as MeshInstance3D
        if roofs != null and bool(roofs.get_meta("bourse_roof_winding_upward", false)):
            return true
    return false


func _capture(smoothed: bool, output_path: String) -> bool:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        return false
    var scene := packed.instantiate()
    if scene == null:
        return false

    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)

    var traffic_manager := scene.get_node_or_null("TrafficManager")
    if traffic_manager != null:
        traffic_manager.set("auto_spawn_runtime", false)
    _hide_capture_noise(scene)
    viewport.add_child(scene)

    var contract := _camera_contract()
    if contract.is_empty():
        viewport.queue_free()
        return false
    var horizontal_fov := float(contract.get("horizontal_fov_degrees", 0.0))
    var vertical_fov := _horizontal_to_vertical_fov(horizontal_fov, float(WIDTH) / float(HEIGHT))
    if vertical_fov <= 0.0:
        viewport.queue_free()
        return false

    var existing_camera := viewport.get_camera_3d()
    if existing_camera != null:
        existing_camera.current = false
    var camera := Camera3D.new()
    camera.position = _vector3(contract.get("position", []))
    camera.rotation_degrees = _vector3(contract.get("rotation_degrees", []))
    camera.keep_aspect = Camera3D.KEEP_HEIGHT
    camera.fov = vertical_fov
    camera.current = true
    scene.add_child(camera)

    if not await _wait_for_reveal(scene):
        viewport.queue_free()
        return false

    var smoothing := root.get_node_or_null("BourseRoofSourceFaceSmoothing")
    if smoothing == null:
        viewport.queue_free()
        return false
    if smoothed:
        smoothing.set("enabled", true)
        if not bool(smoothing.call("apply_to_scene", scene)):
            viewport.queue_free()
            return false
        if int(smoothing.call("diagnostic_source_face_count")) != 231:
            viewport.queue_free()
            return false
        if int(smoothing.call("diagnostic_source_triangle_count")) <= 0:
            viewport.queue_free()
            return false
        if int(smoothing.call("diagnostic_smoothed_vertex_occurrences")) <= 0:
            viewport.queue_free()
            return false

    for _frame: int in range(WARMUP_FRAMES):
        await process_frame
    _hide_capture_noise(scene)
    RenderingServer.force_draw()
    await process_frame

    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty() or image.get_size() != Vector2i(WIDTH, HEIGHT):
        viewport.queue_free()
        return false
    var absolute_output := ProjectSettings.globalize_path(output_path)
    var dir_error := DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
    if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
        viewport.queue_free()
        return false
    if image.save_png(absolute_output) != OK:
        viewport.queue_free()
        return false

    viewport.queue_free()
    await process_frame
    return true


func _run() -> void:
    if not await _capture(false, BEFORE_PATH):
        _fail("baseline capture failed")
        return
    if not await _capture(true, AFTER_PATH):
        _fail("smoothed capture failed")
        return
    print("BOURSE_ROOF_SOURCE_FACE_SMOOTHING_VISUAL_OK before=%s after=%s" % [BEFORE_PATH, AFTER_PATH])
    quit(0)
