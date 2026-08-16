extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const WARMUP_FRAMES := 90
const SETTLE_FRAMES := 8
const EVIDENCE_PATH := "res://data/qa/photo_match/bourse_2019_geotagged_camera_evidence.json"
const BEFORE_PATH := "res://artifacts/visual/bourse_pediment_before.png"
const AFTER_PATH := "res://artifacts/visual/bourse_pediment_after.png"
const MIN_CHANGED_3 := 0.0015
const MIN_CHANGED_8 := 0.0005
const MAX_CHANGED_3 := 0.12

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_PEDIMENT_WITNESS_FAIL: %s" % message)
    quit(1)

func _vector3(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.ZERO
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))

func _horizontal_to_vertical_fov(horizontal_degrees: float, aspect: float) -> float:
    return rad_to_deg(2.0 * atan(tan(deg_to_rad(horizontal_degrees) * 0.5) / aspect))

func _hide_labels(node: Node) -> void:
    if node is Label3D:
        (node as Label3D).visible = false
    for child: Node in node.get_children():
        _hide_labels(child)

func _hide_noise(scene: Node) -> void:
    for node_path: String in ["LocationLabel", "MissionLabel", "PrototypeLabel", "MiniMap", "MobileControls"]:
        var item := scene.get_node_or_null(node_path) as CanvasItem
        if item != null:
            item.visible = false
    for node_path: String in ["Player", "PrototypeCar", "PhysicalCarB", "MidiHeroZone", "MidiUrbanLife"]:
        var spatial := scene.get_node_or_null(node_path) as Node3D
        if spatial != null:
            spatial.visible = false
    var traffic := scene.get_node_or_null("TrafficManager")
    if traffic != null:
        traffic.set("auto_spawn_runtime", false)
        if traffic is Node3D:
            (traffic as Node3D).visible = false
    for autoload_name: String in [
        "DirectSpawnPresentation",
        "LivingCityShowcaseRuntime",
        "MidiAmbientNpcVisualRuntime",
        "MidiProfiledNpcGaitRuntime",
        "VisibleCityRuntime"
    ]:
        var autoload := root.get_node_or_null(autoload_name)
        if autoload is Node3D:
            (autoload as Node3D).visible = false
    _hide_labels(scene)

func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}

func _capture(output_path: String) -> Image:
    RenderingServer.force_draw()
    await process_frame
    var image := root.get_texture().get_image()
    if image == null or image.is_empty():
        return null
    var absolute := ProjectSettings.globalize_path(output_path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    if image.save_png(absolute) != OK:
        return null
    return image

func _changed_fraction(before: Image, after: Image, threshold: int) -> float:
    if before == null or after == null or before.get_size() != after.get_size():
        return -1.0
    var changed := 0
    var total := before.get_width() * before.get_height()
    var limit := float(threshold) / 255.0
    for y: int in range(before.get_height()):
        for x: int in range(before.get_width()):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            if max(abs(a.r - b.r), max(abs(a.g - b.g), abs(a.b - b.b))) > limit:
                changed += 1
    return float(changed) / float(total)

func _run() -> void:
    root.size = Vector2i(WIDTH, HEIGHT)
    var evidence := _read_json(EVIDENCE_PATH)
    var candidate := evidence.get("candidate_game_camera_transform", {}) as Dictionary
    var position := _vector3(candidate.get("position", []))
    var rotation := _vector3(candidate.get("rotation_degrees", []))
    var horizontal_fov := float(candidate.get("horizontal_fov_degrees", 0.0))
    if horizontal_fov <= 0.0:
        _fail("invalid camera evidence")
        return

    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    _hide_noise(scene)

    var existing_camera := root.get_camera_3d()
    if existing_camera != null:
        existing_camera.current = false
    var camera := Camera3D.new()
    camera.position = position
    camera.rotation_degrees = rotation
    camera.keep_aspect = Camera3D.KEEP_HEIGHT
    camera.fov = _horizontal_to_vertical_fov(horizontal_fov, float(WIDTH) / float(HEIGHT))
    camera.current = true
    scene.add_child(camera)

    for _frame: int in range(WARMUP_FRAMES):
        await process_frame
    _hide_noise(scene)

    var runtime := root.get_node_or_null("BourseOfficialPedimentSurfaceRuntime")
    if runtime == null:
        _fail("pediment runtime missing")
        return
    var wait_frames := 0
    while not bool(runtime.call("diagnostic_ready_complete")) and wait_frames < 120:
        await process_frame
        wait_frames += 1
    if not bool(runtime.call("diagnostic_ready_complete")):
        _fail("pediment runtime did not finish")
        return
    if bool(runtime.call("diagnostic_identity_failure")):
        _fail("pediment source identity validation failed")
        return
    var source_triangles := int(runtime.call("diagnostic_source_triangle_count"))
    if source_triangles <= 0:
        _fail("pediment source selection returned zero triangles")
        return

    runtime.call("set_enabled", false)
    for _frame: int in range(SETTLE_FRAMES):
        await process_frame
    var before := await _capture(BEFORE_PATH)
    if before == null:
        _fail("before capture failed")
        return

    runtime.call("set_enabled", true)
    for _frame: int in range(SETTLE_FRAMES):
        await process_frame
    var after := await _capture(AFTER_PATH)
    if after == null:
        _fail("after capture failed")
        return

    var changed_3 := _changed_fraction(before, after, 3)
    var changed_8 := _changed_fraction(before, after, 8)
    print("BOURSE_PEDIMENT_METRICS: changed_gt3=%.6f changed_gt8=%.6f source_triangles=%d" % [changed_3, changed_8, source_triangles])
    if changed_3 < MIN_CHANGED_3:
        _fail("visual impact below >3 RGB gate: %.4f%% < %.4f%%" % [changed_3 * 100.0, MIN_CHANGED_3 * 100.0])
        return
    if changed_8 < MIN_CHANGED_8:
        _fail("visual impact below >8 RGB gate: %.4f%% < %.4f%%" % [changed_8 * 100.0, MIN_CHANGED_8 * 100.0])
        return
    if changed_3 > MAX_CHANGED_3:
        _fail("pediment reveal is not localized enough: %.4f%% > %.4f%%" % [changed_3 * 100.0, MAX_CHANGED_3 * 100.0])
        return

    print("BOURSE_PEDIMENT_WITNESS_OK: changed_gt3=%.4f%% changed_gt8=%.4f%% source_triangles=%d" % [changed_3 * 100.0, changed_8 * 100.0, source_triangles])
    scene.queue_free()
    quit(0)
