extends SceneTree

const MAIN_SCENE = preload("res://game/main.tscn")
const CONTRACT_PATH := "res://data/qa/grand_place_town_hall_roof_winner_strict.json"
const OUTPUT_PATH := "res://artifacts/qa/grand_place_town_hall_roof_winner_strict.json"
const BEFORE_PATH := "res://artifacts/qa/grand_place_town_hall_roof_winner_strict_before.png"
const AFTER_PATH := "res://artifacts/qa/grand_place_town_hall_roof_winner_strict_after.png"
const WIDTH := 1280
const HEIGHT := 720

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_TOWN_HALL_ROOF_WINNER_STRICT_FAIL: " + message)
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

func _short_id(raw: Variant) -> String:
    return str(raw).rsplit("/", false, 1)[-1]

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
    for _frame: int in range(5):
        RenderingServer.force_draw()
        await process_frame
    var image := root.get_viewport().get_texture().get_image()
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        image.resize(WIDTH, HEIGHT, Image.INTERPOLATE_LANCZOS)
    image.save_png(ProjectSettings.globalize_path(path))
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

func _find_face(faces: Array, face_id: String) -> Dictionary:
    for raw_face: Variant in faces:
        if typeof(raw_face) == TYPE_DICTIONARY and _short_id((raw_face as Dictionary).get("id", "")) == face_id:
            return raw_face as Dictionary
    return {}

func _face_normal(face: Dictionary) -> Vector3:
    for raw_triangle: Variant in face.get("triangles", []):
        if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
            continue
        var a := _v3(raw_triangle[0])
        var b := _v3(raw_triangle[1])
        var c := _v3(raw_triangle[2])
        var normal := (b - a).cross(c - a).normalized()
        if normal.is_finite() and normal.length_squared() > 0.5:
            if normal.y < 0.0:
                normal = -normal
            return normal
    return Vector3.ZERO

func _overlay(face: Dictionary, normal: Vector3, offset: float) -> MeshInstance3D:
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
            if point.is_finite():
                tool.set_normal(normal)
                tool.add_vertex(point + normal * offset)
    var mesh := MeshInstance3D.new()
    mesh.mesh = tool.commit()
    mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    return mesh

func _run() -> void:
    var contract := _json(CONTRACT_PATH)
    if str(contract.get("schema", "")) != "grand-bruxelles-town-hall-roof-winner-strict-v1":
        _fail("contract missing or schema drift")
        return
    if str(contract.get("production_base", "")) != "0748e960b13c17c755a0939e0b231c2296201e37":
        _fail("production base drift")
        return
    var geometry := _json(str(contract.get("geometry_path", "")))
    var source: Dictionary = geometry.get("source", {})
    if str(source.get("building_2d_id", "")) != str(contract.get("expected_building_id", "")):
        _fail("building identity drift")
        return
    if str(source.get("package_sha256", "")) != str(contract.get("expected_package_sha256", "")):
        _fail("official package digest drift")
        return
    var face := _find_face(geometry.get("faces", []), str(contract.get("candidate_face_id", "")))
    if face.is_empty() or str(face.get("type", "")) != "ROOFSURFACE":
        _fail("candidate face missing or not ROOFSURFACE")
        return

    var camera_contract := _json(str(contract.get("camera_contract_path", "")))
    var camera_position := _v3(camera_contract.get("camera_position", []))
    var camera_target := _v3(camera_contract.get("camera_target", []))
    var camera_fov := float(camera_contract.get("camera_fov_deg", 0.0))
    if camera_position.distance_to(Vector3(319.01, 1.72, -535.20)) > 0.0001 or camera_target.distance_to(Vector3(321.91, 11.8, -485.66)) > 0.0001 or absf(camera_fov - 62.0) > 0.0001:
        _fail("canonical camera drift")
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
    for _frame: int in range(240):
        if official != null and bool(official.get("geometry_loaded")):
            break
        await process_frame
        official = root.get_node_or_null("GrandPlaceOfficialLod2")
    if official == null or not bool(official.get("geometry_loaded")):
        _fail("production Town Hall did not load")
        return

    var hidden_canvas_items := _hide_canvas_recursive(main)
    var frozen_dynamics := _freeze_dynamics()
    if bool(contract.get("require_hidden_canvas_items", true)) and hidden_canvas_items <= 0:
        _fail("strict witness hid no Canvas UI")
        return
    await process_frame
    hidden_canvas_items += _hide_canvas_recursive(main)
    _freeze_dynamics()

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/qa"))
    var before := await _capture(BEFORE_PATH)
    var normal := _face_normal(face)
    if normal.length_squared() < 0.5:
        _fail("candidate face has no valid normal")
        return
    var overlay := _overlay(face, normal, float(contract.get("overlay_offset_m", 0.015)))
    main.add_child(overlay)
    await process_frame
    _hide_canvas_recursive(main)
    _freeze_dynamics()
    var after := await _capture(AFTER_PATH)
    var metrics := _diff(before, after)
    if int(metrics.get("changed_gt8_pixels", 0)) < int(contract.get("minimum_changed_gt8_pixels", 250)):
        _fail("strict clean winner falls below frozen pixel floor")
        return
    if int(metrics.get("bbox_width", 0)) < int(contract.get("minimum_bbox_width_px", 20)) or int(metrics.get("bbox_height", 0)) < int(contract.get("minimum_bbox_height_px", 20)):
        _fail("strict clean winner bbox below frozen floor")
        return

    var output_data := {
        "schema": "grand-bruxelles-town-hall-roof-winner-strict-evidence-v1",
        "production_base": str(contract.get("production_base", "")),
        "candidate_face_id": str(contract.get("candidate_face_id", "")),
        "hidden_canvas_items": hidden_canvas_items,
        "frozen_dynamic_nodes": frozen_dynamics,
        "metrics": metrics,
        "runtime_changed": false,
        "geometry_changed": false,
        "implementation_authorized": false,
        "visual_candidate_approved": false,
        "next_step": "source_semantic_registration_only"
    }
    var output := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
    if output == null:
        _fail("cannot write strict evidence")
        return
    output.store_string(JSON.stringify(output_data, "  "))
    output.close()
    print("GRAND_PLACE_TOWN_HALL_ROOF_WINNER_STRICT_JSON " + JSON.stringify(output_data))
    print("GRAND_PLACE_TOWN_HALL_ROOF_WINNER_STRICT_OK face=%s pixels=%d hidden_ui=%d" % [str(contract.get("candidate_face_id", "")), int(metrics.get("changed_gt8_pixels", 0)), hidden_canvas_items])
    quit(0)
