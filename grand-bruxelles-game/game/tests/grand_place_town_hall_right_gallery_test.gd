extends SceneTree

const MAIN_SCENE = preload("res://game/main.tscn")
const CONTRACT_PATH := "res://data/qa/grand_place_town_hall_right_gallery_contract.json"
const WIDTH := 1280
const HEIGHT := 720

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_TOWN_HALL_RIGHT_GALLERY_FAIL: " + message)
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

func _capture(path: String) -> Image:
    for _frame: int in range(8):
        RenderingServer.force_draw()
        await process_frame
    var image: Image = root.get_viewport().get_texture().get_image()
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        image.resize(WIDTH, HEIGHT, Image.INTERPOLATE_LANCZOS)
    image.save_png(path)
    return image

func _diff(a: Image, b: Image) -> Dictionary:
    var gt3 := 0
    var gt8 := 0
    var x0 := WIDTH
    var y0 := HEIGHT
    var x1 := -1
    var y1 := -1
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var ca: Color = a.get_pixel(x, y)
            var cb: Color = b.get_pixel(x, y)
            var delta := maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), absf(ca.b - cb.b))) * 255.0
            if delta > 3.0:
                gt3 += 1
                x0 = mini(x0, x)
                y0 = mini(y0, y)
                x1 = maxi(x1, x)
                y1 = maxi(y1, y)
            if delta > 8.0:
                gt8 += 1
    return {
        "changed_gt3_pixels": gt3,
        "changed_gt8_pixels": gt8,
        "changed_gt3_percent": 100.0 * float(gt3) / float(WIDTH * HEIGHT),
        "changed_gt8_percent": 100.0 * float(gt8) / float(WIDTH * HEIGHT),
        "bbox": [x0,y0,x1,y1] if gt3 > 0 else null,
        "bbox_width": x1 - x0 + 1 if gt3 > 0 else 0,
        "bbox_height": y1 - y0 + 1 if gt3 > 0 else 0
    }

func _run() -> void:
    var contract := _json(CONTRACT_PATH)
    if contract.is_empty():
        _fail("contract missing")
        return
    var hard: Dictionary = contract.get("hard_rules", {})
    for key: String in ["character_npc_changed","shared_environment_changed","citygen_changed","official_geometry_changed","portal_depth_authored","statuary_authored","runtime_approved","realism_complete"]:
        if bool(hard.get(key, true)):
            _fail("hard rule drift: " + key)
            return
    var visual: Dictionary = contract.get("visualization", {})
    if int(visual.get("bay_count", 0)) != 6 or absf(float(visual.get("opening_depth_m", 1.0))) > 0.0001:
        _fail("source-backed six-bay flat-articulation contract drift")
        return
    var target: Dictionary = contract.get("target", {})
    var geometry := _json(str(target.get("official_geometry_path", "")))
    var source: Dictionary = geometry.get("source", {})
    if str(source.get("building_2d_id", "")) != str(target.get("urbis_building_id", "")) or str(source.get("package_sha256", "")) != str(target.get("official_package_sha256", "")):
        _fail("official UrbIS source drift")
        return
    var ids: Array = target.get("face_ids", [])
    var found: Dictionary = {}
    for raw_face: Variant in geometry.get("faces", []):
        if typeof(raw_face) == TYPE_DICTIONARY:
            var face: Dictionary = raw_face as Dictionary
            var face_id := str(face.get("id", ""))
            if ids.has(face_id):
                found[face_id] = true
    if found.size() != 2:
        _fail("exact source faces missing")
        return

    var main: Node = MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    var old_camera := main.get_viewport().get_camera_3d()
    if old_camera != null:
        old_camera.current = false
    var camera_contract := _json(str((contract.get("witness", {}) as Dictionary).get("camera_contract_path", "")))
    var camera := Camera3D.new()
    camera.position = _v3(camera_contract.get("camera_position", []))
    camera.fov = float(camera_contract.get("camera_fov_deg", 0.0))
    main.add_child(camera)
    camera.look_at(_v3(camera_contract.get("camera_target", [])), Vector3.UP)
    camera.current = true
    for node: Node in get_nodes_in_group("vehicle") + get_nodes_in_group("npc") + get_nodes_in_group("ambient_pedestrian") + get_nodes_in_group("ambient_traffic"):
        node.process_mode = Node.PROCESS_MODE_DISABLED
        if node is Node3D:
            (node as Node3D).visible = false
    for child: Node in main.get_children():
        if child is CanvasLayer:
            (child as CanvasLayer).visible = false

    var official: Node = null
    for _frame: int in range(240):
        official = root.get_node_or_null("GrandPlaceOfficialLod2")
        if official != null and bool(official.get("geometry_loaded")):
            break
        await process_frame
    if official == null or not bool(official.get("geometry_loaded")):
        _fail("official Town Hall did not load")
        return
    if not official.has_method("set_right_gallery_visible") or not official.has_method("right_gallery_contract"):
        _fail("RED-first witness: right-gallery runtime missing")
        return
    var runtime_contract: Dictionary = official.call("right_gallery_contract") as Dictionary
    if int(runtime_contract.get("bay_count", 0)) != 6 or str(runtime_contract.get("source_face_chain", "")) != "10792525+10798452":
        _fail("runtime source contract mismatch")
        return

    official.call("set_right_gallery_visible", false)
    var before := await _capture("/tmp/grand-place-town-hall-right-gallery-before.png")
    official.call("set_right_gallery_visible", true)
    var after := await _capture("/tmp/grand-place-town-hall-right-gallery-after.png")
    var metrics := _diff(before, after)
    var witness: Dictionary = contract.get("witness", {})
    if float(metrics.get("changed_gt3_percent", 0.0)) < float(witness.get("min_changed_gt3_percent", 0.0)):
        _fail("gt3 visibility gate failed: %s" % metrics)
        return
    if float(metrics.get("changed_gt8_percent", 0.0)) < float(witness.get("min_changed_gt8_percent", 0.0)):
        _fail("gt8 visibility gate failed: %s" % metrics)
        return
    if int(metrics.get("bbox_width", 0)) < int(witness.get("min_bbox_width_px", 0)) or int(metrics.get("bbox_height", 0)) < int(witness.get("min_bbox_height_px", 0)):
        _fail("bbox visibility gate failed: %s" % metrics)
        return
    var out := FileAccess.open("/tmp/grand-place-town-hall-right-gallery-metrics.json", FileAccess.WRITE)
    out.store_string(JSON.stringify({"schema":"grand-bruxelles-town-hall-right-gallery-witness-v1","metrics":metrics,"contract":runtime_contract}, "  "))
    out.close()
    print("GRAND_PLACE_TOWN_HALL_RIGHT_GALLERY_OK " + JSON.stringify(metrics))
    quit(0)
