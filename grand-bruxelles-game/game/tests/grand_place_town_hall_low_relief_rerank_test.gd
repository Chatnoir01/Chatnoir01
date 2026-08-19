extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const BrusselsWhiteStoneMaterial := preload("res://game/scripts/brussels_white_stone_material.gd")
const CONTRACT_PATH := "res://data/qa/grand_place_town_hall_low_relief_rerank.json"
const WIDTH := 1280
const HEIGHT := 720

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_LOW_RELIEF_RERANK_FAIL: " + message)
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

func _color(raw: Variant) -> Color:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 4:
        return Color.WHITE
    return Color(float(raw[0]), float(raw[1]), float(raw[2]), float(raw[3]))

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
        if node.is_in_group("vehicle") or node.is_in_group("npc") or node.is_in_group("ambient_pedestrian") or node.is_in_group("ambient_traffic") or node.is_in_group("ambient") or node.is_in_group("traffic"):
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
    if points.is_empty():
        return Vector3.ZERO
    var total := Vector3.ZERO
    for point: Vector3 in points:
        total += point
    return total / float(points.size())

func _normal(face: Dictionary, camera_position: Vector3) -> Vector3:
    var points := _face_points(face)
    var center := _centroid(points)
    for raw_triangle: Variant in face.get("triangles", []):
        if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
            continue
        var a := _v3(raw_triangle[0])
        var b := _v3(raw_triangle[1])
        var c := _v3(raw_triangle[2])
        var normal := (b - a).cross(c - a)
        if normal.length_squared() <= 0.000001:
            continue
        normal = normal.normalized()
        if normal.dot(camera_position - center) < 0.0:
            normal = -normal
        return normal
    return Vector3.ZERO

func _screen_candidate(camera: Camera3D, face: Dictionary) -> bool:
    var any_front := false
    var min_x := INF
    var min_y := INF
    var max_x := -INF
    var max_y := -INF
    for point: Vector3 in _face_points(face):
        if camera.is_position_behind(point):
            continue
        any_front = true
        var screen := camera.unproject_position(point)
        min_x = minf(min_x, screen.x)
        min_y = minf(min_y, screen.y)
        max_x = maxf(max_x, screen.x)
        max_y = maxf(max_y, screen.y)
    if not any_front:
        return false
    return max_x >= 0.0 and min_x < float(WIDTH) and max_y >= 0.0 and min_y < float(HEIGHT)

func _probe(face: Dictionary, camera_position: Vector3, offset: float, material: Material) -> MeshInstance3D:
    var normal := _normal(face, camera_position)
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    for raw_triangle: Variant in face.get("triangles", []):
        if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
            continue
        for raw_point: Variant in raw_triangle:
            var point := _v3(raw_point)
            tool.set_normal(normal)
            tool.add_vertex(point + normal * offset)
    var instance := MeshInstance3D.new()
    instance.name = "TownHallWallFaceLowReliefQaProbe"
    instance.mesh = tool.commit()
    instance.material_override = material
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    instance.set_meta("qa_only", true)
    instance.set_meta("production_geometry_changed", false)
    return instance

func _capture() -> Image:
    for _frame: int in range(4):
        _freeze_world(current_scene)
        RenderingServer.force_draw()
        await process_frame
    var texture := root.get_viewport().get_texture()
    if texture == null:
        return Image.new()
    var image := texture.get_image()
    if image == null or image.is_empty():
        return Image.new()
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        image.resize(WIDTH, HEIGHT, Image.INTERPOLATE_LANCZOS)
    return image

func _metrics(a: Image, b: Image) -> Dictionary:
    var gt3 := 0
    var gt8 := 0
    var min_x := WIDTH
    var min_y := HEIGHT
    var max_x := -1
    var max_y := -1
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var ca := a.get_pixel(x, y)
            var cb := b.get_pixel(x, y)
            var delta := maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), absf(ca.b - cb.b))) * 255.0
            if delta > 3.0:
                gt3 += 1
            if delta > 8.0:
                gt8 += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
    var bbox_width := max_x - min_x + 1 if gt8 > 0 else 0
    var bbox_height := max_y - min_y + 1 if gt8 > 0 else 0
    var edge_margin := mini(min_x, WIDTH - 1 - max_x) if gt8 > 0 else 0
    var center_x := 0.5 * float(min_x + max_x) if gt8 > 0 else 0.0
    var center_distance := absf(center_x - float(WIDTH) * 0.5) if gt8 > 0 else float(WIDTH)
    var centrality := clampf(1.0 - center_distance / (float(WIDTH) * 0.5), 0.0, 1.0)
    return {
        "gt3_pixels": gt3,
        "gt3_percent": 100.0 * float(gt3) / float(WIDTH * HEIGHT),
        "gt8_pixels": gt8,
        "gt8_percent": 100.0 * float(gt8) / float(WIDTH * HEIGHT),
        "bbox": [min_x, min_y, max_x, max_y] if gt8 > 0 else null,
        "bbox_width": bbox_width,
        "bbox_height": bbox_height,
        "horizontal_edge_margin": edge_margin,
        "horizontal_center_distance": center_distance,
        "horizontal_centrality": centrality
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

func _passes_gate(metrics: Dictionary, gate: Dictionary) -> bool:
    return (
        int(metrics.get("gt3_pixels", 0)) >= int(gate.get("minimum_gt3_pixels", 2500))
        and int(metrics.get("gt8_pixels", 0)) >= int(gate.get("minimum_gt8_pixels", 1200))
        and int(metrics.get("bbox_width", 0)) >= int(gate.get("minimum_bbox_width", 100))
        and int(metrics.get("bbox_height", 0)) >= int(gate.get("minimum_bbox_height", 180))
        and int(metrics.get("horizontal_edge_margin", 0)) >= int(gate.get("minimum_horizontal_edge_margin", 64))
    )

func _score(metrics: Dictionary) -> float:
    var centrality := float(metrics.get("horizontal_centrality", 0.0))
    var edge_margin := float(metrics.get("horizontal_edge_margin", 0))
    var edge_factor := 0.75 + 0.25 * clampf(edge_margin / 200.0, 0.0, 1.0)
    return float(metrics.get("gt8_pixels", 0)) * (0.60 + 0.40 * centrality) * edge_factor

func _find_face(geometry: Dictionary, face_id: String) -> Dictionary:
    for raw_face: Variant in geometry.get("faces", []):
        if typeof(raw_face) == TYPE_DICTIONARY:
            var face := raw_face as Dictionary
            if _short_id(str(face.get("id", ""))) == face_id:
                return face
    return {}

func _run() -> void:
    var contract := _json(CONTRACT_PATH)
    if str(contract.get("schema", "")) != "grand-bruxelles-town-hall-low-relief-rerank-v1":
        _fail("contract schema invalid")
        return
    var hard: Dictionary = contract.get("hard_rules", {})
    for key: String in ["runtime_changed", "geometry_changed", "source_vertices_changed", "implementation_authorized", "author_openings", "author_portal_depth", "author_statuary", "claim_probe_as_exact_material", "camera_rescue", "threshold_rescue"]:
        if bool(hard.get(key, true)):
            _fail("hard rule drift: " + key)
            return
    if not bool(hard.get("source_registration_authorized_only_after_human_review", false)):
        _fail("source-registration human gate removed")
        return

    var target: Dictionary = contract.get("target", {})
    var geometry := _json(str(target.get("geometry_path", "")))
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

    var camera_contract := _json(str(contract.get("camera_contract_path", "")))
    if int(camera_contract.get("source_pr", 0)) != 711:
        _fail("canonical camera contract drift")
        return
    var camera_position := _v3(camera_contract.get("camera_position", []))
    var camera_target := _v3(camera_contract.get("camera_target", []))
    var camera_fov := float(camera_contract.get("camera_fov_deg", 0.0))
    if camera_position.distance_to(Vector3(319.01, 1.72, -535.20)) > 0.0001 or camera_target.distance_to(Vector3(321.91, 11.8, -485.66)) > 0.0001 or absf(camera_fov - 62.0) > 0.0001:
        _fail("canonical camera values drift")
        return

    var probe_contract: Dictionary = contract.get("probe", {})
    if bool(probe_contract.get("claims_exact_material_identity", true)) or bool(probe_contract.get("claims_surveyed_relief", true)):
        _fail("QA probe overclaims source truth")
        return
    var probe_material: ShaderMaterial = BrusselsWhiteStoneMaterial.create(
        _color(probe_contract.get("cool_color", [])),
        _color(probe_contract.get("warm_color", [])),
        float(probe_contract.get("base_roughness", 0.82)),
        "QA-only Town Hall WALLSURFACE low-relief visibility rerank; no exact material claim"
    )
    if str(probe_material.get_meta("material_family", "")) != str(probe_contract.get("material_family", "")):
        _fail("probe material family drift")
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
    for _frame: int in range(120):
        _freeze_world(main)
        await process_frame

    var baseline := await _capture()
    if baseline.is_empty():
        _fail("baseline capture unavailable")
        return
    baseline.save_png("/tmp/grand-place-low-relief-baseline.png")

    var gate: Dictionary = contract.get("nomination_gate", {})
    var offset := float(probe_contract.get("offset_m", 0.028))
    var rows: Array[Dictionary] = []
    for raw_face: Variant in geometry.get("faces", []):
        if typeof(raw_face) != TYPE_DICTIONARY:
            continue
        var face := raw_face as Dictionary
        if str(face.get("type", "")) != "WALLSURFACE" or not _screen_candidate(camera, face):
            continue
        var face_id := _short_id(str(face.get("id", "")))
        var probe := _probe(face, camera_position, offset, probe_material)
        main.add_child(probe)
        for _wait: int in range(2):
            _freeze_world(main)
            await process_frame
        var candidate := await _capture()
        probe.queue_free()
        await process_frame
        if candidate.is_empty():
            _fail("candidate capture unavailable for " + face_id)
            return
        var metrics := _metrics(baseline, candidate)
        var excluded := _is_excluded(face_id, contract)
        var gate_pass := (not excluded) and _passes_gate(metrics, gate)
        rows.append({
            "face_id": face_id,
            "excluded_from_nomination": excluded,
            "passes_frozen_nomination_gate": gate_pass,
            "score": _score(metrics) if gate_pass else 0.0,
            "metrics": metrics
        })

    rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        var a_pass := bool(a.get("passes_frozen_nomination_gate", false))
        var b_pass := bool(b.get("passes_frozen_nomination_gate", false))
        if a_pass != b_pass:
            return a_pass
        if a_pass:
            return float(a.get("score", 0.0)) > float(b.get("score", 0.0))
        return int((a.get("metrics", {}) as Dictionary).get("gt8_pixels", 0)) > int((b.get("metrics", {}) as Dictionary).get("gt8_pixels", 0))
    )

    var eligible: Array[Dictionary] = []
    var review_rows: Array[Dictionary] = []
    for row: Dictionary in rows:
        if bool(row.get("passes_frozen_nomination_gate", false)):
            eligible.append(row)
    if not eligible.is_empty():
        for i: int in range(mini(3, eligible.size())):
            review_rows.append(eligible[i])
    else:
        for row: Dictionary in rows:
            if not bool(row.get("excluded_from_nomination", true)):
                review_rows.append(row)
                if review_rows.size() >= 3:
                    break

    for i: int in range(review_rows.size()):
        var row := review_rows[i]
        var face_id := str(row.get("face_id", ""))
        var face := _find_face(geometry, face_id)
        if face.is_empty():
            continue
        var probe := _probe(face, camera_position, offset, probe_material)
        main.add_child(probe)
        for _wait: int in range(2):
            _freeze_world(main)
            await process_frame
        var image := await _capture()
        probe.queue_free()
        await process_frame
        if not image.is_empty():
            image.save_png("/tmp/grand-place-low-relief-candidate-%d-%s.png" % [i + 1, face_id])

    var nominee: Variant = eligible[0] if not eligible.is_empty() else null
    var output := {
        "schema": "grand-bruxelles-town-hall-low-relief-rerank-evidence-v1",
        "status": "evidence_only",
        "base_main": str(contract.get("base_main", "")),
        "probe_material_family": str(probe_material.get_meta("material_family", "")),
        "probe_offset_m": offset,
        "nomination_gate": gate,
        "nominee": nominee,
        "human_review_candidates": review_rows,
        "ranked_faces": rows,
        "implementation_authorized": false,
        "source_registration_authorized": false,
        "human_full_frame_review_required": true
    }
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/qa"))
    var file := FileAccess.open("res://artifacts/qa/grand_place_town_hall_low_relief_rerank.json", FileAccess.WRITE)
    if file == null:
        _fail("cannot write evidence")
        return
    file.store_string(JSON.stringify(output, "  "))
    file.close()
    var nominee_id := "none" if eligible.is_empty() else str(eligible[0].get("face_id", ""))
    print("GRAND_PLACE_LOW_RELIEF_RERANK_JSON " + JSON.stringify(output))
    print("GRAND_PLACE_LOW_RELIEF_RERANK_OK nominee=%s eligible=%d reviewed=%d" % [nominee_id, eligible.size(), review_rows.size()])
    quit(0)
