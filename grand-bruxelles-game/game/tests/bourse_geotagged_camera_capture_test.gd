extends SceneTree

const WIDTH := 1280
const HEIGHT := 960
const WARMUP_FRAMES := 90
const EVIDENCE_PATH := "res://data/qa/photo_match/bourse_2019_geotagged_camera_evidence.json"
const OUTPUT_PATH := "res://artifacts/photo-match/bourse_2019_geotagged_camera.png"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_GEOTAGGED_CAPTURE_FAIL: %s" % message)
    quit(1)

func _vector3(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY:
        return Vector3.ZERO
    var values := raw as Array
    if values.size() != 3:
        return Vector3.ZERO
    return Vector3(float(values[0]), float(values[1]), float(values[2]))

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
    for node_path: String in ["Player", "PrototypeCar", "MidiHeroZone"]:
        var spatial := scene.get_node_or_null(node_path) as Node3D
        if spatial != null:
            spatial.visible = false
    _hide_generated_labels(scene)

func _run() -> void:
    if not FileAccess.file_exists(EVIDENCE_PATH):
        _fail("geotagged camera evidence is missing")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EVIDENCE_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("geotagged camera evidence is invalid JSON")
        return
    var evidence := parsed as Dictionary
    if str(evidence.get("schema", "")) != "grand-bruxelles-bourse-geotagged-camera-evidence-v1":
        _fail("unsupported evidence schema")
        return
    if bool(evidence.get("runtime_approved", true)):
        _fail("QA witness must remain runtime_approved=false")
        return

    var candidate: Dictionary = evidence.get("candidate_game_camera_transform", {})
    if candidate.is_empty():
        _fail("candidate camera transform is missing")
        return
    var position := _vector3(candidate.get("position", []))
    var rotation := _vector3(candidate.get("rotation_degrees", []))
    var horizontal_fov := float(candidate.get("horizontal_fov_degrees", 0.0))
    var vertical_fov := _horizontal_to_vertical_fov(horizontal_fov, float(WIDTH) / float(HEIGHT))
    if vertical_fov <= 0.0:
        _fail("candidate FOV is invalid")
        return

    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    if scene == null:
        _fail("main scene did not instantiate")
        return

    var capture_viewport := SubViewport.new()
    capture_viewport.name = "BourseGeotaggedViewport"
    capture_viewport.size = Vector2i(WIDTH, HEIGHT)
    capture_viewport.own_world_3d = true
    capture_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    capture_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(capture_viewport)

    var traffic_manager := scene.get_node_or_null("TrafficManager")
    if traffic_manager != null:
        traffic_manager.set("auto_spawn_runtime", false)
    _hide_capture_noise(scene)
    capture_viewport.add_child(scene)

    var existing_camera := scene.get_viewport().get_camera_3d()
    if existing_camera != null:
        existing_camera.current = false

    var camera := Camera3D.new()
    camera.name = "BourseGeotaggedCaptureCamera"
    camera.position = position
    camera.rotation_degrees = rotation
    camera.keep_aspect = Camera3D.KEEP_HEIGHT
    camera.fov = vertical_fov
    camera.current = true
    scene.add_child(camera)

    print(
        "BOURSE_GEOTAGGED_CAMERA: pos=%s rot=%s horizontal_fov=%.6f vertical_fov=%.6f" %
        [str(position), str(rotation), horizontal_fov, vertical_fov]
    )

    for _frame: int in range(WARMUP_FRAMES):
        await process_frame
    _hide_capture_noise(scene)
    RenderingServer.force_draw()
    await process_frame

    var image := capture_viewport.get_texture().get_image()
    if image == null or image.is_empty():
        _fail("captured viewport is empty")
        return
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        _fail("unexpected capture dimensions")
        return

    var absolute_output := ProjectSettings.globalize_path(OUTPUT_PATH)
    var dir_error := DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
    if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
        _fail("could not create artifact directory")
        return
    var save_error := image.save_png(absolute_output)
    if save_error != OK:
        _fail("could not save capture: %s" % error_string(save_error))
        return

    print("BOURSE_GEOTAGGED_CAPTURE_OK: %s" % OUTPUT_PATH)
    capture_viewport.queue_free()
    quit(0)
