extends SceneTree

const MAIN_SCENE = preload("res://game/main.tscn")
const CONTRACT_PATH := "res://data/visual/grand_place_town_hall_dormer_visualization.json"
const CAMERA_PATH := "res://data/qa/grand_place_clean_player_witness.json"
const OUTPUT_PATH := "res://artifacts/qa/grand_place_town_hall_dormer_visual.json"
const BEFORE_PATH := "res://artifacts/qa/grand_place_town_hall_dormer_before.png"
const AFTER_PATH := "res://artifacts/qa/grand_place_town_hall_dormer_after.png"
const WIDTH := 1280
const HEIGHT := 720

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_TOWN_HALL_DORMER_VISUAL_FAIL: " + message)
    quit(1)

func _json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}

func _v3(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.INF
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))

func _hide_canvas_recursive(node: Node) -> int:
    var hidden := 0
    if node is CanvasLayer:
        (node as CanvasLayer).visible = false
        hidden += 1
    if node is CanvasItem:
        (node as CanvasItem).visible = false
        hidden += 1
    for child: Node in node.get_children():
        hidden += _hide_canvas_recursive(child)
    return hidden

func _freeze_dynamics() -> int:
    var count := 0
    for group_name: String in ["vehicle", "npc", "ambient_pedestrian", "ambient_traffic"]:
        for node: Node in get_nodes_in_group(group_name):
            node.process_mode = Node.PROCESS_MODE_DISABLED
            if node is Node3D:
                (node as Node3D).visible = false
            count += 1
    return count

func _capture(path: String) -> Image:
    for _frame: int in range(6):
        _hide_canvas_recursive(root)
        RenderingServer.force_draw()
        await process_frame
    _hide_canvas_recursive(root)
    var texture := root.get_viewport().get_texture()
    if texture == null:
        _fail("viewport texture unavailable; real GL renderer required")
        return Image.new()
    var image := texture.get_image()
    if image == null or image.is_empty():
        _fail("viewport image unavailable; real GL renderer required")
        return Image.new()
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        image.resize(WIDTH, HEIGHT, Image.INTERPOLATE_LANCZOS)
    image.save_png(ProjectSettings.globalize_path(path))
    return image

func _diff(a: Image, b: Image, delta_floor: float) -> Dictionary:
    var pixels := 0
    var x0 := WIDTH
    var y0 := HEIGHT
    var x1 := -1
    var y1 := -1
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var ca := a.get_pixel(x, y)
            var cb := b.get_pixel(x, y)
            var delta := maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), absf(ca.b - cb.b))) * 255.0
            if delta > delta_floor:
                pixels += 1
                x0 = mini(x0, x)
                y0 = mini(y0, y)
                x1 = maxi(x1, x)
                y1 = maxi(y1, y)
    return {
        "changed_gt8_pixels": pixels,
        "changed_gt8_percent": 100.0 * float(pixels) / float(WIDTH * HEIGHT),
        "bbox": [x0, y0, x1, y1] if pixels > 0 else null,
        "bbox_width": x1 - x0 + 1 if pixels > 0 else 0,
        "bbox_height": y1 - y0 + 1 if pixels > 0 else 0
    }

func _run() -> void:
    var contract := _json(CONTRACT_PATH)
    if str(contract.get("schema", "")) != "grand-bruxelles-town-hall-dormer-visualization-v1":
        _fail("candidate contract missing")
        return
    var gate: Dictionary = contract.get("predeclared_visual_gate", {})
    var resolution: Array = gate.get("resolution", [])
    if resolution.size() != 2 or int(resolution[0]) != WIDTH or int(resolution[1]) != HEIGHT:
        _fail("visual gate resolution drift")
        return

    var camera_contract := _json(CAMERA_PATH)
    var camera_position := _v3(camera_contract.get("camera_position", []))
    var camera_target := _v3(camera_contract.get("camera_target", []))
    var camera_fov := float(camera_contract.get("camera_fov_deg", 0.0))
    if camera_position.distance_to(Vector3(319.01, 1.72, -535.20)) > 0.0001 or camera_target.distance_to(Vector3(321.91, 11.8, -485.66)) > 0.0001 or absf(camera_fov - 62.0) > 0.0001:
        _fail("canonical Grand-Place camera drift")
        return

    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    var old_camera := main.get_viewport().get_camera_3d()
    if old_camera != null:
        old_camera.current = false
    var camera := Camera3D.new()
    camera.position = camera_position
    camera.fov = camera_fov
    main.add_child(camera)
    camera.look_at(camera_target, Vector3.UP)
    camera.current = true

    var official: Node = root.get_node_or_null("GrandPlaceOfficialLod2")
    var dormers: Node3D = root.get_node_or_null("GrandPlaceTownHallDormerRuntime") as Node3D
    for _frame: int in range(300):
        if official != null and bool(official.get("geometry_loaded")) and dormers != null and bool(dormers.call("ready_complete")):
            break
        await process_frame
        official = root.get_node_or_null("GrandPlaceOfficialLod2")
        dormers = root.get_node_or_null("GrandPlaceTownHallDormerRuntime") as Node3D
    if official == null or not bool(official.get("geometry_loaded")):
        _fail("production Town Hall did not load")
        return
    if dormers == null or not bool(dormers.call("ready_complete")) or int(dormers.call("dormer_count")) != 16:
        _fail("dormer runtime did not load with 16 details")
        return

    var hidden_canvas_items := _hide_canvas_recursive(root)
    var frozen_dynamics := _freeze_dynamics()
    await process_frame
    hidden_canvas_items += _hide_canvas_recursive(root)
    _freeze_dynamics()

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/qa"))
    dormers.visible = false
    var before := await _capture(BEFORE_PATH)
    if before.is_empty():
        return
    dormers.visible = true
    var after := await _capture(AFTER_PATH)
    if after.is_empty():
        return

    var metrics := _diff(before, after, float(gate.get("rgb_delta_threshold", 8)))
    if int(metrics.get("changed_gt8_pixels", 0)) < int(gate.get("minimum_changed_pixels", 350)):
        _fail("dormers fall below predeclared changed-pixel floor")
        return
    if int(metrics.get("bbox_width", 0)) < int(gate.get("minimum_bbox_width_px", 50)) or int(metrics.get("bbox_height", 0)) < int(gate.get("minimum_bbox_height_px", 25)):
        _fail("dormer visual bbox falls below predeclared floor")
        return

    var output_data := {
        "schema": "grand-bruxelles-town-hall-dormer-visual-evidence-v1",
        "production_base": str(contract.get("production_base", "")),
        "candidate_face_id": "9369301",
        "dormer_count": 16,
        "row_population_top_to_bottom": [3, 4, 4, 5],
        "placement_source": "photo_fit_visualization_convention_not_survey_coordinates",
        "hidden_canvas_items": hidden_canvas_items,
        "frozen_dynamic_nodes": frozen_dynamics,
        "metrics": metrics,
        "urbis_mesh_modified": false,
        "human_visual_review_required": true
    }
    var output := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
    if output == null:
        _fail("cannot write visual evidence")
        return
    output.store_string(JSON.stringify(output_data, "  "))
    output.close()
    print("GRAND_PLACE_TOWN_HALL_DORMER_VISUAL_JSON " + JSON.stringify(output_data))
    print("GRAND_PLACE_TOWN_HALL_DORMER_VISUAL_OK pixels=%d bbox=%dx%d dormers=16" % [int(metrics.get("changed_gt8_pixels", 0)), int(metrics.get("bbox_width", 0)), int(metrics.get("bbox_height", 0))])
    quit(0)
