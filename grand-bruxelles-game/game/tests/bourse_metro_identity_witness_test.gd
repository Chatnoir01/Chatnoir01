extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/bourse_metro_identity_runtime.gd")
const WIDTH := 1280
const HEIGHT := 720
const WARMUP_FRAMES := 60
const EVIDENCE_PATH := "res://data/qa/photo_match/bourse_2019_geotagged_camera_evidence.json"
const BEFORE_PATH := "res://artifacts/visual/bourse_metro_identity_before.png"
const AFTER_PATH := "res://artifacts/visual/bourse_metro_identity_after.png"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_METRO_IDENTITY_WITNESS_FAIL: %s" % message)
    quit(1)

func _vector3(raw: Variant) -> Vector3:
    var values := raw as Array
    return Vector3(float(values[0]), float(values[1]), float(values[2]))

func _horizontal_to_vertical_fov(horizontal_degrees: float, aspect: float) -> float:
    return rad_to_deg(2.0 * atan(tan(deg_to_rad(horizontal_degrees) * 0.5) / aspect))

func _hide_ui_and_player(scene: Node) -> void:
    for node_path: String in ["LocationLabel", "MissionLabel", "PrototypeLabel", "MiniMap", "MobileControls"]:
        var item := scene.get_node_or_null(node_path) as CanvasItem
        if item != null:
            item.visible = false
    for node_path: String in ["Player", "PrototypeCar", "MidiHeroZone"]:
        var spatial := scene.get_node_or_null(node_path) as Node3D
        if spatial != null:
            spatial.visible = false

func _is_dynamic_name(name_text: String) -> bool:
    var lowered := name_text.to_lower()
    for token in ["npc", "traffic", "vehicle", "car", "pedestrian", "agent", "urbanlife", "urban_life"]:
        if lowered.contains(token):
            return true
    return false

func _freeze_dynamic_recursive(node: Node) -> int:
    var frozen := 0
    for child in node.get_children():
        frozen += _freeze_dynamic_recursive(child)
    if node is CharacterBody3D or node is RigidBody3D or node is AnimatableBody3D or node is AnimationPlayer or _is_dynamic_name(node.name):
        node.process_mode = Node.PROCESS_MODE_DISABLED
        if node is RigidBody3D:
            (node as RigidBody3D).freeze = true
        frozen += 1
    return frozen

func _capture(viewport: SubViewport, path: String) -> Image:
    viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
    RenderingServer.force_draw()
    await process_frame
    await process_frame
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        _fail("capture invalid: %s" % path)
        return null
    var absolute_output := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
    if image.save_png(absolute_output) != OK:
        _fail("capture save failed: %s" % path)
        return null
    return image

func _measure(before: Image, after: Image) -> Dictionary:
    var gt3 := 0
    var gt8 := 0
    var total := WIDTH * HEIGHT
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := max(abs(a.r - b.r), max(abs(a.g - b.g), abs(a.b - b.b))) * 255.0
            if delta > 3.0:
                gt3 += 1
            if delta > 8.0:
                gt8 += 1
    return {
        "gt3": gt3,
        "gt8": gt8,
        "pct3": float(gt3) * 100.0 / float(total),
        "pct8": float(gt8) * 100.0 / float(total),
    }

func _run() -> void:
    print("BOURSE_METRO_IDENTITY_WITNESS_STAGE: start")
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EVIDENCE_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("camera evidence invalid")
        return
    var candidate: Dictionary = (parsed as Dictionary).get("candidate_game_camera_transform", {})
    var camera_position := _vector3(candidate.get("position", []))
    var camera_rotation := _vector3(candidate.get("rotation_degrees", []))
    var horizontal_fov := float(candidate.get("horizontal_fov_degrees", 0.0))

    var packed := load("res://game/main.tscn") as PackedScene
    var scene := packed.instantiate()
    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    _hide_ui_and_player(scene)
    viewport.add_child(scene)

    var existing_camera := scene.get_viewport().get_camera_3d()
    if existing_camera != null:
        existing_camera.current = false
    var camera := Camera3D.new()
    camera.position = camera_position
    camera.rotation_degrees = camera_rotation
    camera.keep_aspect = Camera3D.KEEP_HEIGHT
    camera.fov = _horizontal_to_vertical_fov(horizontal_fov, float(WIDTH) / float(HEIGHT))
    camera.current = true
    scene.add_child(camera)

    var runtime := RUNTIME_SCRIPT.new()
    runtime.name = "BourseMetroIdentityWitness"
    runtime.visible = false
    scene.add_child(runtime)
    await process_frame
    if not bool(runtime.get("visual_built")) or int(runtime.get("identity_count")) != 7:
        _fail("runtime identity set did not build")
        return

    for _frame in range(WARMUP_FRAMES):
        await process_frame
    _hide_ui_and_player(scene)
    var frozen_count := _freeze_dynamic_recursive(scene)
    print("BOURSE_METRO_IDENTITY_WITNESS_STAGE: warmed frozen_dynamic_nodes=%d" % frozen_count)
    await process_frame

    runtime.visible = false
    var before := await _capture(viewport, BEFORE_PATH)
    if before == null:
        return
    print("BOURSE_METRO_IDENTITY_WITNESS_STAGE: before_saved")
    runtime.visible = true
    var after := await _capture(viewport, AFTER_PATH)
    if after == null:
        return
    print("BOURSE_METRO_IDENTITY_WITNESS_STAGE: after_saved")

    var metrics := _measure(before, after)
    print("BOURSE_METRO_IDENTITY_WITNESS_METRICS: gt3=%d pct3=%.4f gt8=%d pct8=%.4f frozen_same_scene=true frozen_dynamic_nodes=%d" % [metrics.gt3, metrics.pct3, metrics.gt8, metrics.pct8, frozen_count])
    print("BOURSE_METRO_IDENTITY_WITNESS_OK: before=%s after=%s camera=source_locked entrances=7" % [BEFORE_PATH, AFTER_PATH])
    quit(0)
