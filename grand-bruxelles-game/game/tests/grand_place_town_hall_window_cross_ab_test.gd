extends SceneTree

const MAIN_SCENE = preload("res://game/main.tscn")
const RUNTIME_NAME := "GrandPlaceTownHallWindowRhythmRuntime"
const CAMERA_PATH := "res://data/qa/grand_place_clean_player_witness.json"
const BEFORE_PATH := "res://artifacts/qa/grand_place_town_hall_window_cross_before.png"
const AFTER_PATH := "res://artifacts/qa/grand_place_town_hall_window_cross_after.png"
const OUTPUT_PATH := "res://artifacts/qa/grand_place_town_hall_window_cross.json"
const WIDTH := 1280
const HEIGHT := 720
const MIN_CHANGED_GT8 := 900
const MIN_BBOX_WIDTH := 220
const MIN_BBOX_HEIGHT := 160
const MAX_CHANGED_PERCENT := 5.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_TOWN_HALL_WINDOW_CROSS_AB_FAIL: " + message)
    quit(1)

func _json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path): return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}

func _v3(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3: return Vector3.INF
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))

func _mask_canvas(node: Node) -> int:
    var hidden := 0
    if node is CanvasLayer:
        (node as CanvasLayer).visible = false
        hidden += 1
    if node is CanvasItem:
        (node as CanvasItem).visible = false
        hidden += 1
    for child: Node in node.get_children():
        hidden += _mask_canvas(child)
    return hidden

func _freeze_dynamics() -> int:
    var count := 0
    for group_name: String in ["vehicle", "npc", "ambient_pedestrian", "ambient_traffic", "ambient", "traffic"]:
        for node: Node in get_nodes_in_group(group_name):
            node.process_mode = Node.PROCESS_MODE_DISABLED
            if node is Node3D: (node as Node3D).visible = false
            count += 1
    return count

func _capture(path: String) -> Image:
    for _frame: int in range(8):
        _mask_canvas(root)
        RenderingServer.force_draw()
        await process_frame
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
    if image.save_png(ProjectSettings.globalize_path(path)) != OK:
        _fail("capture save failed: " + path)
        return Image.new()
    return image

func _diff(a: Image, b: Image) -> Dictionary:
    var pixels := 0
    var x0 := WIDTH
    var y0 := HEIGHT
    var x1 := -1
    var y1 := -1
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var ca := a.get_pixel(x, y)
            var cb := b.get_pixel(x, y)
            var d := maxf(absf(ca.r-cb.r), maxf(absf(ca.g-cb.g), absf(ca.b-cb.b))) * 255.0
            if d > 8.0:
                pixels += 1
                x0 = mini(x0, x); y0 = mini(y0, y); x1 = maxi(x1, x); y1 = maxi(y1, y)
    return {
        "changed_gt8_pixels": pixels,
        "changed_gt8_percent": 100.0 * float(pixels) / float(WIDTH * HEIGHT),
        "bbox": [x0,y0,x1,y1] if pixels > 0 else null,
        "bbox_width": x1-x0+1 if pixels > 0 else 0,
        "bbox_height": y1-y0+1 if pixels > 0 else 0,
    }

func _run() -> void:
    var camera_contract := _json(CAMERA_PATH)
    var resolution: Array = camera_contract.get("resolution", [])
    if resolution.size() != 2 or int(resolution[0]) != WIDTH or int(resolution[1]) != HEIGHT:
        _fail("canonical resolution drift")
        return
    var camera_position := _v3(camera_contract.get("camera_position", []))
    var camera_target := _v3(camera_contract.get("camera_target", []))
    var camera_fov := float(camera_contract.get("camera_fov_deg", 0.0))
    if camera_position.distance_to(Vector3(319.01,1.72,-535.20)) > 0.0001 or camera_target.distance_to(Vector3(321.91,11.8,-485.66)) > 0.0001 or absf(camera_fov-62.0) > 0.0001:
        _fail("canonical camera drift")
        return

    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    var runtime := root.get_node_or_null(RUNTIME_NAME)
    if runtime == null:
        _fail("window rhythm runtime missing")
        return
    for _frame: int in range(480):
        await process_frame
        if bool(runtime.get("articulation_ready")) and runtime.has_method("cross_detail_count") and int(runtime.call("cross_detail_count")) == 20:
            break
    if not bool(runtime.get("articulation_ready")) or not runtime.has_method("set_cross_detail_visible") or int(runtime.call("cross_detail_count")) != 20 or int(runtime.call("cross_strip_count")) != 40:
        _fail("east cross-window runtime not ready")
        return

    var old_camera := main.get_viewport().get_camera_3d()
    if old_camera != null: old_camera.current = false
    var camera := Camera3D.new()
    camera.position = camera_position
    camera.fov = camera_fov
    main.add_child(camera)
    camera.look_at(camera_target, Vector3.UP)
    camera.current = true

    var hidden_ui := _mask_canvas(root)
    var frozen := _freeze_dynamics()
    for _frame: int in range(16):
        hidden_ui += _mask_canvas(root)
        await process_frame

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/qa"))
    runtime.call("set_articulation_visible", true)
    runtime.call("set_cross_detail_visible", false)
    var before := await _capture(BEFORE_PATH)
    if before.is_empty(): return
    runtime.call("set_cross_detail_visible", true)
    var after := await _capture(AFTER_PATH)
    if after.is_empty(): return

    var metrics := _diff(before, after)
    if int(metrics.get("changed_gt8_pixels", 0)) < MIN_CHANGED_GT8:
        _fail("changed pixels below frozen floor")
        return
    if int(metrics.get("bbox_width", 0)) < MIN_BBOX_WIDTH or int(metrics.get("bbox_height", 0)) < MIN_BBOX_HEIGHT:
        _fail("changed bbox below frozen floor")
        return
    if float(metrics.get("changed_gt8_percent", 0.0)) > MAX_CHANGED_PERCENT:
        _fail("change escaped incremental detail ceiling")
        return

    var output_data := {
        "schema": "grand-bruxelles-town-hall-window-cross-ab-v1",
        "camera_source_pr": int(camera_contract.get("source_pr", 0)),
        "panels_preserved": 38,
        "east_crosses": int(runtime.call("cross_detail_count")),
        "strips": int(runtime.call("cross_strip_count")),
        "west_special_ordination_deferred": true,
        "hidden_ui_operations": hidden_ui,
        "frozen_dynamic_nodes": frozen,
        "metrics": metrics,
        "thresholds": {"minimum_changed_gt8_pixels":MIN_CHANGED_GT8,"minimum_bbox_width":MIN_BBOX_WIDTH,"minimum_bbox_height":MIN_BBOX_HEIGHT,"maximum_changed_gt8_percent":MAX_CHANGED_PERCENT},
        "urbis_mesh_modified": false,
        "new_openings_authored": false,
        "human_visual_review_required": true,
    }
    var output := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
    if output == null:
        _fail("cannot write evidence JSON")
        return
    output.store_string(JSON.stringify(output_data, "  "))
    output.close()
    print("GRAND_PLACE_TOWN_HALL_WINDOW_CROSS_AB_JSON " + JSON.stringify(output_data))
    print("GRAND_PLACE_TOWN_HALL_WINDOW_CROSS_AB_OK: pixels=%d bbox=%dx%d east_crosses=20 west_deferred=true clean_player=true" % [int(metrics.get("changed_gt8_pixels",0)), int(metrics.get("bbox_width",0)), int(metrics.get("bbox_height",0))])
    quit(0)
