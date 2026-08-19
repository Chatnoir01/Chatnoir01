extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const CONTRACT_PATH := "res://data/qa/grand_place_town_hall_central_wall_drilldown.json"
const WIDTH := 1280
const HEIGHT := 720

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_CENTRAL_WALL_DRILLDOWN_FAIL: " + message)
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

func _walk(node: Node, out: Array[Node]) -> void:
    out.append(node)
    for child: Node in node.get_children():
        _walk(child, out)

func _freeze_world(main: Node) -> void:
    var nodes: Array[Node] = []
    _walk(root, nodes)
    for node: Node in nodes:
        if node is CanvasLayer:
            (node as CanvasLayer).visible = false
        elif node is CanvasItem:
            (node as CanvasItem).visible = false
        if node.is_in_group("vehicle") or node.is_in_group("npc") or node.is_in_group("ambient_pedestrian") or node.is_in_group("ambient_traffic"):
            node.process_mode = Node.PROCESS_MODE_DISABLED
            if node is Node3D:
                (node as Node3D).visible = false
    for path: String in ["Player", "PrototypeCar", "PhysicalCar", "PhysicalCarB", "TrafficManager", "NpcPopulationDirector", "NpcRuntimeIntegration", "MidiUrbanLife"]:
        var target: Node = main.get_node_or_null(path)
        if target != null:
            target.process_mode = Node.PROCESS_MODE_DISABLED
            if target is Node3D:
                (target as Node3D).visible = false

func _face_points(face: Dictionary) -> Array[Vector3]:
    var points: Array[Vector3] = []
    for raw_triangle: Variant in face.get("triangles", []):
        if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
            continue
        for raw_point: Variant in raw_triangle:
            var point: Vector3 = _v3(raw_point)
            if point.is_finite():
                points.append(point)
    return points

func _centroid(points: Array[Vector3]) -> Vector3:
    var total: Vector3 = Vector3.ZERO
    for point: Vector3 in points:
        total += point
    return total / float(points.size()) if not points.is_empty() else Vector3.ZERO

func _normal(face: Dictionary, camera_position: Vector3) -> Vector3:
    for raw_triangle: Variant in face.get("triangles", []):
        if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
            continue
        var a: Vector3 = _v3(raw_triangle[0])
        var b: Vector3 = _v3(raw_triangle[1])
        var c: Vector3 = _v3(raw_triangle[2])
        var normal: Vector3 = (b - a).cross(c - a)
        if normal.length_squared() <= 0.000001:
            continue
        normal = normal.normalized()
        var center: Vector3 = _centroid(_face_points(face))
        if normal.dot(camera_position - center) < 0.0:
            normal = -normal
        return normal
    return Vector3.ZERO

func _screen_candidate(camera: Camera3D, face: Dictionary) -> bool:
    for point: Vector3 in _face_points(face):
        if camera.is_position_behind(point):
            continue
        var screen: Vector2 = camera.unproject_position(point)
        if screen.x >= 0.0 and screen.x < float(WIDTH) and screen.y >= 0.0 and screen.y < float(HEIGHT):
            return true
    return false

func _overlay(face: Dictionary, camera_position: Vector3, offset: float) -> MeshInstance3D:
    var normal: Vector3 = _normal(face, camera_position)
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
            var point: Vector3 = _v3(raw_point)
            tool.set_normal(normal)
            tool.add_vertex(point + normal * offset)
    var instance := MeshInstance3D.new()
    instance.name = "TownHallWallFaceQaOverlay"
    instance.mesh = tool.commit()
    return instance

func _capture() -> Image:
    for _frame: int in range(4):
        RenderingServer.force_draw()
        await process_frame
    var image: Image = root.get_viewport().get_texture().get_image()
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        image.resize(WIDTH, HEIGHT, Image.INTERPOLATE_LANCZOS)
    return image

func _metrics(a: Image, b: Image) -> Dictionary:
    var changed: int = 0
    var min_x: int = WIDTH
    var min_y: int = HEIGHT
    var max_x: int = -1
    var max_y: int = -1
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var ca: Color = a.get_pixel(x, y)
            var cb: Color = b.get_pixel(x, y)
            var delta: float = maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), absf(ca.b - cb.b))) * 255.0
            if delta > 8.0:
                changed += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
    return {
        "gt8_pixels": changed,
        "gt8_percent": 100.0 * float(changed) / float(WIDTH * HEIGHT),
        "bbox_width": max_x - min_x + 1 if changed > 0 else 0,
        "bbox_height": max_y - min_y + 1 if changed > 0 else 0,
        "bbox": [min_x, min_y, max_x, max_y] if changed > 0 else null
    }

func _short_id(raw_id: String) -> String:
    return raw_id.get_file()

func _is_excluded(face_id: String, contract: Dictionary) -> bool:
    var known: Dictionary = contract.get("known_faces", {})
    for group_name: String in known.keys():
        for raw_id: Variant in known.get(group_name, []):
            if face_id == str(raw_id):
                return true
    return false

func _run() -> void:
    var contract: Dictionary = _json(CONTRACT_PATH)
    if str(contract.get("schema", "")) != "grand-bruxelles-town-hall-central-wall-drilldown-v1":
        _fail("contract schema invalid")
        return
    var hard: Dictionary = contract.get("hard_rules", {})
    for key: String in ["runtime_changed", "geometry_changed", "source_vertices_changed", "implementation_authorized", "author_openings", "author_portal_depth", "author_statuary", "reuse_right_gallery_dimensions", "camera_rescue", "threshold_rescue"]:
        if bool(hard.get(key, true)):
            _fail("hard rule drift: " + key)
            return
    var target: Dictionary = contract.get("target", {})
    var geometry: Dictionary = _json(str(target.get("geometry_path", "")))
    var source: Dictionary = geometry.get("source", {})
    var evidence: Dictionary = geometry.get("evidence", {})
    var counts: Dictionary = evidence.get("face_type_counts", {})
    if str(source.get("building_2d_id", "")) != str(target.get("urbis_building_id", "")):
        _fail("UrbIS building identity drift")
        return
    if str(source.get("package_sha256", "")) != str(target.get("expected_package_sha256", "")):
        _fail("UrbIS package hash drift")
        return
    if int(counts.get("WALLSURFACE", 0)) != int(target.get("expected_wall_face_count", 0)):
        _fail("wall face count drift")
        return
    var camera_contract: Dictionary = _json(str(contract.get("camera_contract_path", "")))
    if int(camera_contract.get("source_pr", 0)) != 711:
        _fail("canonical camera contract drift")
        return
    var camera_position: Vector3 = _v3(camera_contract.get("camera_position", []))
    var camera_target: Vector3 = _v3(camera_contract.get("camera_target", []))
    var camera_fov: float = float(camera_contract.get("camera_fov_deg", 0.0))

    var main: Node = MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    var old_camera: Camera3D = main.get_viewport().get_camera_3d()
    if old_camera != null:
        old_camera.current = false
    var camera := Camera3D.new()
    camera.position = camera_position
    camera.fov = camera_fov
    main.add_child(camera)
    camera.look_at(camera_target, Vector3.UP)
    camera.current = true
    for _frame: int in range(120):
        _freeze_world(main)
        await process_frame
    var baseline: Image = await _capture()
    baseline.save_png("/tmp/grand-place-central-wall-baseline.png")

    var gate: Dictionary = contract.get("gate", {})
    var rows: Array[Dictionary] = []
    for raw_face: Variant in geometry.get("faces", []):
        if typeof(raw_face) != TYPE_DICTIONARY:
            continue
        var face: Dictionary = raw_face as Dictionary
        if str(face.get("type", "")) != "WALLSURFACE" or not _screen_candidate(camera, face):
            continue
        var face_id: String = _short_id(str(face.get("id", "")))
        var overlay: MeshInstance3D = _overlay(face, camera_position, float(gate.get("overlay_offset_m", 0.012)))
        main.add_child(overlay)
        for _wait: int in range(2):
            _freeze_world(main)
            await process_frame
        var candidate: Image = await _capture()
        overlay.queue_free()
        await process_frame
        var row: Dictionary = {
            "face_id": face_id,
            "excluded_from_nomination": _is_excluded(face_id, contract),
            "metrics": _metrics(baseline, candidate)
        }
        rows.append(row)
    rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int((a.get("metrics", {}) as Dictionary).get("gt8_pixels", 0)) > int((b.get("metrics", {}) as Dictionary).get("gt8_pixels", 0)))
    var winner: Dictionary = {}
    for row: Dictionary in rows:
        if bool(row.get("excluded_from_nomination", true)):
            continue
        var metrics: Dictionary = row.get("metrics", {})
        if int(metrics.get("gt8_pixels", 0)) >= int(gate.get("minimum_gt8_pixels", 5000)) and int(metrics.get("bbox_width", 0)) >= int(gate.get("minimum_bbox_width", 80)) and int(metrics.get("bbox_height", 0)) >= int(gate.get("minimum_bbox_height", 100)):
            winner = row
            break
    if winner.is_empty():
        _fail("no non-excluded WALLSURFACE passes frozen exposure gate")
        return
    var winner_id: String = str(winner.get("face_id", ""))
    var winner_face: Dictionary = {}
    for raw_face: Variant in geometry.get("faces", []):
        if typeof(raw_face) == TYPE_DICTIONARY and _short_id(str((raw_face as Dictionary).get("id", ""))) == winner_id:
            winner_face = raw_face as Dictionary
            break
    var winner_overlay: MeshInstance3D = _overlay(winner_face, camera_position, float(gate.get("overlay_offset_m", 0.012)))
    main.add_child(winner_overlay)
    for _wait: int in range(2):
        _freeze_world(main)
        await process_frame
    var winner_image: Image = await _capture()
    winner_image.save_png("/tmp/grand-place-central-wall-winner.png")
    var output: Dictionary = {
        "schema": "grand-bruxelles-town-hall-central-wall-drilldown-evidence-v1",
        "status": "evidence_only",
        "base_main": str(contract.get("base_main", "")),
        "winner": winner,
        "ranked_faces": rows,
        "implementation_authorized": false
    }
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/qa"))
    var file := FileAccess.open("res://artifacts/qa/grand_place_town_hall_central_wall_drilldown.json", FileAccess.WRITE)
    if file == null:
        _fail("cannot write evidence")
        return
    file.store_string(JSON.stringify(output, "  "))
    file.close()
    print("GRAND_PLACE_CENTRAL_WALL_DRILLDOWN_JSON " + JSON.stringify(output))
    print("GRAND_PLACE_CENTRAL_WALL_DRILLDOWN_OK winner=%s gt8=%d" % [winner_id, int((winner.get("metrics", {}) as Dictionary).get("gt8_pixels", 0))])
    quit(0)
