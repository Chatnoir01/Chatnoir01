extends SceneTree

const MAIN_SCENE = preload("res://game/main.tscn")
const CONTRACT_PATH := "res://data/qa/grand_place_town_hall_left_gallery_screen_contract.json"
const WIDTH := 1280
const HEIGHT := 720

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_LEFT_GALLERY_SCREEN_FAIL: " + message)
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

func _find_face(geometry: Dictionary, face_id: String) -> Dictionary:
    for raw_face: Variant in geometry.get("faces", []):
        if typeof(raw_face) == TYPE_DICTIONARY and str((raw_face as Dictionary).get("id", "")) == face_id:
            return raw_face as Dictionary
    return {}

func _face_normal(face: Dictionary) -> Vector3:
    for raw_triangle: Variant in face.get("triangles", []):
        if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
            continue
        var a := _v3(raw_triangle[0])
        var b := _v3(raw_triangle[1])
        var c := _v3(raw_triangle[2])
        var normal := (b - a).cross(c - a)
        if normal.length_squared() > 0.000001:
            return normal.normalized()
    return Vector3.ZERO

func _overlay(face: Dictionary, offset_m: float) -> MeshInstance3D:
    var normal := _face_normal(face)
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(1.0, 0.02, 0.58, 1.0)
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    tool.set_material(material)
    for raw_triangle: Variant in face.get("triangles", []):
        if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
            continue
        for raw_point: Variant in raw_triangle:
            var point := _v3(raw_point)
            tool.set_normal(normal)
            tool.add_vertex(point + normal * offset_m)
    var instance := MeshInstance3D.new()
    instance.mesh = tool.commit()
    return instance

func _hide_dynamic_and_ui(root_node: Node) -> void:
    for group_name: String in ["vehicle", "npc", "ambient_pedestrian", "ambient_traffic", "police"]:
        for node: Node in get_nodes_in_group(group_name):
            node.process_mode = Node.PROCESS_MODE_DISABLED
            if node is Node3D:
                (node as Node3D).visible = false
    for child: Node in root_node.get_children():
        if child is CanvasLayer:
            (child as CanvasLayer).visible = false

func _capture(path: String) -> Image:
    for _frame: int in range(6):
        RenderingServer.force_draw()
        await process_frame
    var image := root.get_viewport().get_texture().get_image()
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        image.resize(WIDTH, HEIGHT, Image.INTERPOLATE_LANCZOS)
    image.save_png(path)
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
            var delta := maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), absf(ca.b - cb.b))) * 255.0
            if delta > 8.0:
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
    if contract.is_empty():
        _fail("contract missing")
        return
    var hard: Dictionary = contract.get("hard_rules", {})
    for key: String in ["runtime_changed", "geometry_changed", "source_vertices_changed", "openings_authorized", "arch_dimensions_authorized", "right_gallery_dimensions_reusable", "visual_candidate_approved"]:
        if bool(hard.get(key, true)):
            _fail("fail-closed hard rule drift: " + key)
            return
    var target: Dictionary = contract.get("target", {})
    var geometry := _json(str(target.get("geometry_path", "")))
    if geometry.is_empty():
        _fail("official Town Hall geometry missing")
        return
    var source: Dictionary = geometry.get("source", {})
    if str(source.get("building_2d_id", "")) != str(target.get("urbis_building_id", "")) or str(source.get("package_sha256", "")) != str(target.get("expected_package_sha256", "")):
        _fail("official source contract drift")
        return
    var face_id := str(target.get("candidate_face_id", ""))
    var face := _find_face(geometry, face_id)
    if face.is_empty() or str(face.get("type", "")) != "WALLSURFACE":
        _fail("candidate official WALLSURFACE missing")
        return

    var camera_contract := _json(str(contract.get("camera_contract_path", "")))
    var camera_position := _v3(camera_contract.get("camera_position", []))
    var camera_target := _v3(camera_contract.get("camera_target", []))
    var fov := float(camera_contract.get("camera_fov_deg", 0.0))
    if int(camera_contract.get("source_pr", 0)) != 711 or not camera_position.is_finite() or not camera_target.is_finite() or fov <= 0.0:
        _fail("canonical Grand-Place camera contract drift")
        return

    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    var old_camera := main.get_viewport().get_camera_3d()
    if old_camera != null:
        old_camera.current = false
    var camera := Camera3D.new()
    camera.position = camera_position
    camera.fov = fov
    main.add_child(camera)
    camera.look_at(camera_target, Vector3.UP)
    camera.current = true
    _hide_dynamic_and_ui(main)

    var official: Node = root.get_node_or_null("GrandPlaceOfficialLod2")
    for _frame: int in range(240):
        if official != null and bool(official.get("geometry_loaded")):
            break
        await process_frame
        official = root.get_node_or_null("GrandPlaceOfficialLod2")
    if official == null or not bool(official.get("geometry_loaded")):
        _fail("production GrandPlaceOfficialLod2 did not load")
        return

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/qa"))
    var before := await _capture("res://artifacts/qa/grand_place_left_gallery_face_before.png")
    var overlay := _overlay(face, float((contract.get("visibility_gate", {}) as Dictionary).get("overlay_offset_m", 0.012)))
    main.add_child(overlay)
    var after := await _capture("res://artifacts/qa/grand_place_left_gallery_face_after.png")
    var metrics := _diff(before, after)
    var gate: Dictionary = contract.get("visibility_gate", {})
    if int(metrics.get("changed_gt8_pixels", 0)) < int(gate.get("minimum_changed_gt8_pixels", 0)):
        _fail("candidate face is not materially exposed: changed pixels below frozen gate")
        return
    if int(metrics.get("bbox_width", 0)) < int(gate.get("minimum_bbox_width_px", 0)) or int(metrics.get("bbox_height", 0)) < int(gate.get("minimum_bbox_height_px", 0)):
        _fail("candidate face visible bbox below frozen gate")
        return

    var evidence := {
        "schema": "grand-bruxelles-town-hall-left-gallery-screen-evidence-v1",
        "status": "evidence_only",
        "base_main_sha": contract.get("base_main_sha", ""),
        "candidate_face_id": face_id,
        "metrics": metrics,
        "runtime_authorized": false,
        "openings_authorized": false,
        "arch_dimensions_authorized": false,
        "right_gallery_dimensions_reusable": false,
        "next_required_evidence": "left-gallery-specific dimensional source before any eleven-arch implementation"
    }
    var output := FileAccess.open("res://artifacts/qa/grand_place_left_gallery_screen_evidence.json", FileAccess.WRITE)
    output.store_string(JSON.stringify(evidence, "  "))
    output.close()
    print("GRAND_PLACE_LEFT_GALLERY_SCREEN_OK " + JSON.stringify(evidence))
    quit(0)
