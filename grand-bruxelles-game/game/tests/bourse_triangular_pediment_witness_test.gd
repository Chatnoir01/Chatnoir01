extends SceneTree

const SCRIPT := preload("res://game/scripts/bourse_triangular_pediment_runtime.gd")
const WIDTH := 1280
const HEIGHT := 960
const WARMUP_FRAMES := 90
const SETTLE_FRAMES := 8
const EVIDENCE_PATH := "res://data/qa/photo_match/bourse_2019_geotagged_camera_evidence.json"
const BEFORE_PATH := "res://artifacts/visual/bourse_triangular_pediment_before.png"
const AFTER_PATH := "res://artifacts/visual/bourse_triangular_pediment_after.png"
const METRICS_PATH := "res://artifacts/visual/bourse_triangular_pediment_metrics.json"
const MIN_CHANGED_3_PERCENT := 1.0
const MIN_CHANGED_8_PERCENT := 0.5
const MIN_BBOX_WIDTH := 500
const MIN_BBOX_HEIGHT := 40

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_TRIANGULAR_PEDIMENT_WITNESS_FAIL: %s" % message)
    quit(1)

func _vector3(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.ZERO
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))

func _horizontal_to_vertical_fov(horizontal_degrees: float, aspect: float) -> float:
    return rad_to_deg(2.0 * atan(tan(deg_to_rad(horizontal_degrees) * 0.5) / aspect))

func _mask_canvas(node: Node) -> void:
    if node is CanvasItem:
        (node as CanvasItem).visible = false
    for child: Node in node.get_children():
        _mask_canvas(child)

func _hide_labels(node: Node) -> void:
    if node is Label3D:
        (node as Label3D).visible = false
    for child: Node in node.get_children():
        _hide_labels(child)

func _freeze_dynamic(scene: Node) -> void:
    for group_name: String in ["ambient_pedestrian", "ambient_traffic", "npc", "police", "vehicle"]:
        for raw_node: Node in scene.get_tree().get_nodes_in_group(group_name):
            raw_node.process_mode = Node.PROCESS_MODE_DISABLED
            if raw_node is Node3D:
                (raw_node as Node3D).visible = false
    for node_path: String in ["Player", "PrototypeCar", "PhysicalCarB", "MidiHeroZone", "MidiUrbanLife", "TrafficManager"]:
        var node := scene.get_node_or_null(node_path)
        if node != null:
            node.process_mode = Node.PROCESS_MODE_DISABLED
            if node is Node3D:
                (node as Node3D).visible = false
    _hide_labels(scene)
    _mask_canvas(scene)

func _capture(viewport: SubViewport, scene: Node, output_path: String) -> Image:
    _freeze_dynamic(scene)
    RenderingServer.force_draw()
    await process_frame
    _freeze_dynamic(scene)
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

func _metrics(before: Image, after: Image) -> Dictionary:
    var changed_3 := 0
    var changed_8 := 0
    var min_x := WIDTH
    var min_y := HEIGHT
    var max_x := -1
    var max_y := -1
    var limit_3 := 3.0 / 255.0
    var limit_8 := 8.0 / 255.0
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := max(abs(a.r - b.r), max(abs(a.g - b.g), abs(a.b - b.b)))
            if delta > limit_3:
                changed_3 += 1
            if delta > limit_8:
                changed_8 += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
    var total := WIDTH * HEIGHT
    var bbox_width := 0
    var bbox_height := 0
    if max_x >= min_x and max_y >= min_y:
        bbox_width = max_x - min_x + 1
        bbox_height = max_y - min_y + 1
    return {
        "changed_gt3_pixels": changed_3,
        "changed_gt8_pixels": changed_8,
        "changed_gt3_percent": float(changed_3) * 100.0 / float(total),
        "changed_gt8_percent": float(changed_8) * 100.0 / float(total),
        "bbox": [min_x, min_y, max_x, max_y] if bbox_width > 0 else [],
        "bbox_width": bbox_width,
        "bbox_height": bbox_height,
        "camera_rescue_used": false,
        "threshold_rescue_used": false,
        "dynamic_world_frozen": true,
        "canvas_ui_masked": true
    }

func _write_metrics(metrics: Dictionary) -> void:
    var absolute := ProjectSettings.globalize_path(METRICS_PATH)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    var file := FileAccess.open(absolute, FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify(metrics, "  "))

func _run() -> void:
    if not FileAccess.file_exists(EVIDENCE_PATH):
        _fail("camera evidence missing")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EVIDENCE_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("camera evidence invalid")
        return
    var evidence: Dictionary = parsed as Dictionary
    var candidate: Dictionary = evidence.get("candidate_game_camera_transform", {}) as Dictionary
    var position := _vector3(candidate.get("position", []))
    var rotation := _vector3(candidate.get("rotation_degrees", []))
    var horizontal_fov := float(candidate.get("horizontal_fov_degrees", 0.0))
    if horizontal_fov <= 0.0:
        _fail("camera FOV invalid")
        return
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene missing")
        return
    var scene := packed.instantiate()
    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
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
        _freeze_dynamic(scene)
        await process_frame
    var before := await _capture(viewport, scene, BEFORE_PATH)
    if before == null:
        _fail("before capture failed")
        return
    var runtime := SCRIPT.new()
    runtime.name = "BourseTriangularPedimentWitnessRuntime"
    scene.add_child(runtime)
    for _frame: int in range(SETTLE_FRAMES):
        _freeze_dynamic(scene)
        await process_frame
    if runtime.diagnostic_pediment_count() != 1:
        _fail("pediment runtime failed to materialize")
        return
    var after := await _capture(viewport, scene, AFTER_PATH)
    if after == null:
        _fail("after capture failed")
        return
    var metrics := _metrics(before, after)
    _write_metrics(metrics)
    print("BOURSE_TRIANGULAR_PEDIMENT_METRICS: gt3=%.4f%% gt8=%.4f%% bbox=%dx%d" % [float(metrics["changed_gt3_percent"]), float(metrics["changed_gt8_percent"]), int(metrics["bbox_width"]), int(metrics["bbox_height"])])
    if float(metrics["changed_gt3_percent"]) < MIN_CHANGED_3_PERCENT:
        _fail("visual impact below >3 RGB gate")
        return
    if float(metrics["changed_gt8_percent"]) < MIN_CHANGED_8_PERCENT:
        _fail("visual impact below >8 RGB gate")
        return
    if int(metrics["bbox_width"]) < MIN_BBOX_WIDTH or int(metrics["bbox_height"]) < MIN_BBOX_HEIGHT:
        _fail("visual impact bbox too small")
        return
    print("BOURSE_TRIANGULAR_PEDIMENT_WITNESS_OK")
    viewport.queue_free()
    quit(0)
