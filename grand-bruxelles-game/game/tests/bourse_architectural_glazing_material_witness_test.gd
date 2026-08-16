extends SceneTree

const WIDTH := 1280
const HEIGHT := 960
const WARMUP_FRAMES := 90
const SETTLE_FRAMES := 8
const EVIDENCE_PATH := "res://data/qa/photo_match/bourse_2019_geotagged_camera_evidence.json"
const IDENTITY_PATH := "res://data/visual/bourse_architectural_glazing_material_identity.json"
const BEFORE_PATH := "res://artifacts/visual/bourse_glazing_before.png"
const AFTER_PATH := "res://artifacts/visual/bourse_glazing_after.png"
const MIN_CHANGED_3 := 0.006
const MIN_CHANGED_8 := 0.002

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_GLAZING_WITNESS_FAIL: %s" % message)
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
    _hide_labels(scene)

func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}

func _capture(viewport: SubViewport, output_path: String) -> Image:
    RenderingServer.force_draw()
    await process_frame
    var image := viewport.get_texture().get_image()
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
    var identity := _read_json(IDENTITY_PATH)
    if identity.is_empty():
        _fail("material identity missing")
        return
    var contract := identity.get("presentation_contract", {}) as Dictionary
    if bool(contract.get("geometry_changed", true)) or bool(contract.get("surface_selection_changed", true)):
        _fail("glazing pass must be material-only")
        return
    if bool(contract.get("pane_layout_authored", true)) or bool(contract.get("mullions_authored", true)) or bool(contract.get("interior_authored", true)):
        _fail("glazing contract overclaims architectural detail")
        return

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
    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    _hide_noise(scene)
    viewport.add_child(scene)

    var existing_camera := scene.get_viewport().get_camera_3d()
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

    var runtime := root.get_node_or_null("BourseArchitecturalGlazingSurfaceRuntime")
    var portico := scene.get_node_or_null("BoursePorticoArticulation")
    if runtime == null or portico == null:
        _fail("runtime or portico missing")
        return
    if int(runtime.call("diagnostic_target_count")) != 5:
        runtime.call("bind_portico", portico)
    if bool(runtime.call("diagnostic_identity_failure")):
        _fail("runtime identity validation failed")
        return
    if int(runtime.call("diagnostic_target_count")) != 5:
        _fail("expected five glazed surfaces")
        return

    runtime.call("set_enhanced_material_enabled", false)
    for _frame: int in range(SETTLE_FRAMES):
        await process_frame
    var before := await _capture(viewport, BEFORE_PATH)
    if before == null:
        _fail("before capture failed")
        return

    runtime.call("set_enhanced_material_enabled", true)
    for _frame: int in range(SETTLE_FRAMES):
        await process_frame
    var after := await _capture(viewport, AFTER_PATH)
    if after == null:
        _fail("after capture failed")
        return

    var changed_3 := _changed_fraction(before, after, 3)
    var changed_8 := _changed_fraction(before, after, 8)
    print("BOURSE_GLAZING_METRICS: changed_gt3=%.6f changed_gt8=%.6f targets=5" % [changed_3, changed_8])
    if changed_3 < MIN_CHANGED_3:
        _fail("visual impact below >3 RGB gate: %.4f%% < %.4f%%" % [changed_3 * 100.0, MIN_CHANGED_3 * 100.0])
        return
    if changed_8 < MIN_CHANGED_8:
        _fail("visual impact below >8 RGB gate: %.4f%% < %.4f%%" % [changed_8 * 100.0, MIN_CHANGED_8 * 100.0])
        return

    print("BOURSE_GLAZING_WITNESS_OK: changed_gt3=%.4f%% changed_gt8=%.4f%%" % [changed_3 * 100.0, changed_8 * 100.0])
    viewport.queue_free()
    quit(0)
