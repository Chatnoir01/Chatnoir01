extends SceneTree

const WIDTH := 1280
const HEIGHT := 960
const WARMUP_FRAMES := 90
const MANIFEST_PATH := "res://data/qa/photo_match/manifest.json"
const OUTPUT_PATH := "res://artifacts/photo-match/bourse_2024_cc0_01.png"
const REFERENCE_ID := "bourse_2024_cc0_01"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("PHOTO_MATCH_CAPTURE_FAIL: %s" % message)
    quit(1)

func _read_manifest_reference() -> Dictionary:
    if not FileAccess.file_exists(MANIFEST_PATH):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    for raw_reference: Variant in (parsed as Dictionary).get("references", []):
        if typeof(raw_reference) != TYPE_DICTIONARY:
            continue
        var reference := raw_reference as Dictionary
        if str(reference.get("id", "")) == REFERENCE_ID:
            return reference
    return {}

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
    var horizontal_radians := deg_to_rad(horizontal_degrees)
    return rad_to_deg(2.0 * atan(tan(horizontal_radians * 0.5) / aspect))

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
    var reference := _read_manifest_reference()
    if reference.is_empty():
        _fail("reference %s is missing from manifest" % REFERENCE_ID)
        return
    var viewpoint: Dictionary = reference.get("viewpoint", {})
    var camera_transform: Dictionary = viewpoint.get("game_camera_transform", {})
    if camera_transform.is_empty():
        _fail("reference has no game_camera_transform")
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
    capture_viewport.name = "PhotoMatchViewport"
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
    camera.name = "PhotoMatchCaptureCamera"
    camera.position = _vector3(camera_transform.get("position", []))
    camera.rotation_degrees = _vector3(camera_transform.get("rotation_degrees", []))
    camera.keep_aspect = Camera3D.KEEP_HEIGHT
    var manifest_horizontal_fov := float(camera_transform.get("fov_degrees", 69.4))
    var vertical_fov := _horizontal_to_vertical_fov(manifest_horizontal_fov, float(WIDTH) / float(HEIGHT))
    if vertical_fov <= 0.0:
        _fail("invalid horizontal FOV/aspect conversion")
        return
    camera.fov = vertical_fov
    camera.current = true
    scene.add_child(camera)
    print(
        "PHOTO_MATCH_CAMERA: horizontal_fov=%.4f, vertical_fov=%.4f, viewport=%dx%d" %
        [manifest_horizontal_fov, vertical_fov, WIDTH, HEIGHT]
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
        _fail(
            "captured viewport is %dx%d, expected %dx%d" %
            [image.get_width(), image.get_height(), WIDTH, HEIGHT]
        )
        return
    var absolute_output := ProjectSettings.globalize_path(OUTPUT_PATH)
    var dir_error := DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
    if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
        _fail("could not create artifact directory: %s" % error_string(dir_error))
        return
    var save_error := image.save_png(absolute_output)
    if save_error != OK:
        _fail("could not save screenshot: %s" % error_string(save_error))
        return

    print(
        "PHOTO_MATCH_CAPTURE_OK: %s -> %s (%dx%d)" %
        [REFERENCE_ID, OUTPUT_PATH, image.get_width(), image.get_height()]
    )
    capture_viewport.queue_free()
    quit(0)
