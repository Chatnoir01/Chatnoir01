extends SceneTree

const MAIN_SCENE = preload("res://game/main.tscn")
const CONTRACT_PATH = "res://data/qa/grand_place_town_hall_face_map_contract.json"
const OUTPUT_PATH = "res://artifacts/qa/grand_place_town_hall_face_map.json"
const WIDTH = 1280
const HEIGHT = 720

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_TOWN_HALL_FACE_MAP_FAIL: " + message)
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

func _points(face: Dictionary) -> Array[Vector3]:
    var out: Array[Vector3] = []
    for raw_triangle: Variant in face.get("triangles", []):
        if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
            continue
        for raw_point: Variant in raw_triangle:
            var point: Vector3 = _v3(raw_point)
            if not point.is_finite():
                continue
            var duplicate: bool = false
            for existing: Vector3 in out:
                if existing.distance_to(point) <= 0.0001:
                    duplicate = true
                    break
            if not duplicate:
                out.append(point)
    return out

func _centroid(points: Array[Vector3]) -> Vector3:
    var total: Vector3 = Vector3.ZERO
    for point: Vector3 in points:
        total += point
    return total / float(points.size()) if not points.is_empty() else Vector3.ZERO

func _building_center(faces: Array) -> Vector3:
    var total: Vector3 = Vector3.ZERO
    var count: int = 0
    for raw_face: Variant in faces:
        if typeof(raw_face) != TYPE_DICTIONARY:
            continue
        for point: Vector3 in _points(raw_face as Dictionary):
            total += point
            count += 1
    return total / float(count) if count > 0 else Vector3.ZERO

func _normal(face: Dictionary, building_center: Vector3) -> Vector3:
    var result: Vector3 = Vector3.ZERO
    for raw_triangle: Variant in face.get("triangles", []):
        if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
            continue
        var a: Vector3 = _v3(raw_triangle[0])
        var b: Vector3 = _v3(raw_triangle[1])
        var c: Vector3 = _v3(raw_triangle[2])
        result = (b - a).cross(c - a)
        if result.length_squared() > 0.000001:
            result = result.normalized()
            break
    if result.length_squared() < 0.5:
        return Vector3.ZERO
    var center: Vector3 = _centroid(_points(face))
    var outward: Vector3 = Vector3(center.x - building_center.x, 0.0, center.z - building_center.z)
    var horizontal: Vector3 = Vector3(result.x, 0.0, result.z)
    if outward.length_squared() > 0.0001 and horizontal.length_squared() > 0.0001 and horizontal.dot(outward) < 0.0:
        result = -result
    return result

func _horizontal(normal: Vector3) -> Vector3:
    var value: Vector3 = Vector3(normal.x, 0.0, normal.z)
    return value.normalized() if value.length_squared() > 0.000001 else Vector3.ZERO

func _bounds(points: Array[Vector3]) -> Vector2:
    var low: float = INF
    var high: float = -INF
    for point: Vector3 in points:
        low = minf(low, point.y)
        high = maxf(high, point.y)
    return Vector2(low, high)

func _span(points: Array[Vector3]) -> float:
    var result: float = 0.0
    for i: int in range(points.size()):
        for j: int in range(i + 1, points.size()):
            result = maxf(result, Vector2(points[i].x, points[i].z).distance_to(Vector2(points[j].x, points[j].z)))
    return result

func _screen_bbox(camera: Camera3D, points: Array[Vector3]) -> Dictionary:
    var x0: float = float(WIDTH)
    var y0: float = float(HEIGHT)
    var x1: float = 0.0
    var y1: float = 0.0
    var count: int = 0
    for point: Vector3 in points:
        if camera.is_position_behind(point):
            continue
        var screen: Vector2 = camera.unproject_position(point)
        if not is_finite(screen.x) or not is_finite(screen.y):
            continue
        x0 = minf(x0, screen.x)
        y0 = minf(y0, screen.y)
        x1 = maxf(x1, screen.x)
        y1 = maxf(y1, screen.y)
        count += 1
    if count == 0:
        return {"visible": false, "area": 0.0, "bbox": null}
    x0 = clampf(x0, 0.0, float(WIDTH - 1))
    y0 = clampf(y0, 0.0, float(HEIGHT - 1))
    x1 = clampf(x1, 0.0, float(WIDTH - 1))
    y1 = clampf(y1, 0.0, float(HEIGHT - 1))
    return {"visible": x1 > x0 and y1 > y0, "area": maxf(0.0, x1 - x0) * maxf(0.0, y1 - y0), "bbox": [x0, y0, x1, y1]}

func _connected(a: Dictionary, b: Dictionary, tolerance: float, parallel_min: float) -> bool:
    var na: Vector3 = _horizontal(_v3(a.get("normal", [])))
    var nb: Vector3 = _horizontal(_v3(b.get("normal", [])))
    if na.length_squared() < 0.5 or nb.length_squared() < 0.5 or na.dot(nb) < parallel_min:
        return false
    var pa: Array[Vector3] = a.get("points", [])
    var pb: Array[Vector3] = b.get("points", [])
    for point_a: Vector3 in pa:
        for point_b: Vector3 in pb:
            if Vector2(point_a.x, point_a.z).distance_to(Vector2(point_b.x, point_b.z)) <= tolerance:
                return true
    return false

func _groups(rows: Array[Dictionary], tolerance: float, parallel_min: float) -> Array:
    var result: Array = []
    var seen: Dictionary = {}
    for start: int in range(rows.size()):
        if seen.has(start):
            continue
        var group: Array = []
        var queue: Array[int] = [start]
        seen[start] = true
        while not queue.is_empty():
            var index: int = int(queue.pop_front())
            group.append(rows[index])
            for other: int in range(rows.size()):
                if seen.has(other):
                    continue
                var joins: bool = false
                for raw_member: Variant in group:
                    if _connected(raw_member as Dictionary, rows[other], tolerance, parallel_min):
                        joins = true
                        break
                if joins:
                    seen[other] = true
                    queue.append(other)
        result.append(group)
    return result

func _group_points(group: Array) -> Array[Vector3]:
    var result: Array[Vector3] = []
    for raw_row: Variant in group:
        var row: Dictionary = raw_row as Dictionary
        for point: Vector3 in row.get("points", []):
            var duplicate: bool = false
            for existing: Vector3 in result:
                if existing.distance_to(point) <= 0.0001:
                    duplicate = true
                    break
            if not duplicate:
                result.append(point)
    return result

func _face_ids(group: Array) -> Array[String]:
    var ids: Array[String] = []
    for raw_row: Variant in group:
        ids.append(str((raw_row as Dictionary).get("face_id", "")))
    ids.sort()
    return ids

func _overlay(group: Array, face_lookup: Dictionary, offset: float) -> MeshInstance3D:
    var tool: SurfaceTool = SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = Color(1.0, 0.02, 0.58, 1.0)
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    tool.set_material(material)
    for raw_row: Variant in group:
        var row: Dictionary = raw_row as Dictionary
        var face: Dictionary = face_lookup.get(str(row.get("face_id", "")), {})
        var normal: Vector3 = _v3(row.get("normal", []))
        for raw_triangle: Variant in face.get("triangles", []):
            for raw_point: Variant in raw_triangle:
                var point: Vector3 = _v3(raw_point)
                tool.set_normal(normal)
                tool.add_vertex(point + normal * offset)
    var mesh: MeshInstance3D = MeshInstance3D.new()
    mesh.mesh = tool.commit()
    return mesh

func _capture(path: String) -> Image:
    for _frame: int in range(5):
        RenderingServer.force_draw()
        await process_frame
    var image: Image = root.get_viewport().get_texture().get_image()
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        image.resize(WIDTH, HEIGHT, Image.INTERPOLATE_LANCZOS)
    image.save_png(path)
    return image

func _diff(a: Image, b: Image) -> Dictionary:
    var pixels: int = 0
    var x0: int = WIDTH
    var y0: int = HEIGHT
    var x1: int = -1
    var y1: int = -1
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var ca: Color = a.get_pixel(x, y)
            var cb: Color = b.get_pixel(x, y)
            var delta: float = maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), absf(ca.b - cb.b))) * 255.0
            if delta > 8.0:
                pixels += 1
                x0 = mini(x0, x)
                y0 = mini(y0, y)
                x1 = maxi(x1, x)
                y1 = maxi(y1, y)
    return {"changed_gt8_pixels": pixels, "changed_gt8_percent": 100.0 * float(pixels) / float(WIDTH * HEIGHT), "bbox": [x0, y0, x1, y1] if pixels > 0 else null}

func _run() -> void:
    var contract: Dictionary = _json(CONTRACT_PATH)
    var hard: Dictionary = contract.get("hard_rules", {})
    for key: String in ["runtime_changed", "geometry_changed", "source_vertices_changed", "author_openings", "author_arcades", "author_portal_depth", "author_statuary", "visual_candidate_approved", "realism_complete"]:
        if bool(hard.get(key, true)):
            _fail("hard rule drift: " + key)
            return
    var target: Dictionary = contract.get("target", {})
    var geometry: Dictionary = _json(str(target.get("geometry_path", "")))
    var source: Dictionary = geometry.get("source", {})
    var evidence: Dictionary = geometry.get("evidence", {})
    var counts: Dictionary = evidence.get("face_type_counts", {})
    if str(source.get("building_2d_id", "")) != str(target.get("urbis_building_id", "")) or str(source.get("package_sha256", "")) != str(target.get("expected_package_sha256", "")) or int(counts.get("WALLSURFACE", 0)) != int(target.get("expected_wall_face_count", 0)):
        _fail("official source contract drift")
        return
    var camera_contract: Dictionary = _json(str(contract.get("camera_contract_path", "")))
    var camera_position: Vector3 = _v3(camera_contract.get("camera_position", []))
    var camera_target: Vector3 = _v3(camera_contract.get("camera_target", []))
    var camera_fov: float = float(camera_contract.get("camera_fov_deg", 0.0))
    if int(camera_contract.get("source_pr", 0)) != 711:
        _fail("canonical camera drift")
        return

    var main: Node = MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    var old_camera: Camera3D = main.get_viewport().get_camera_3d()
    if old_camera != null:
        old_camera.current = false
    var camera: Camera3D = Camera3D.new()
    camera.position = camera_position
    camera.fov = camera_fov
    main.add_child(camera)
    camera.look_at(camera_target, Vector3.UP)
    camera.current = true
    for node: Node in get_nodes_in_group("vehicle") + get_nodes_in_group("npc"):
        node.process_mode = Node.PROCESS_MODE_DISABLED
        if node is Node3D:
            (node as Node3D).visible = false
    for child: Node in main.get_children():
        if child is CanvasLayer:
            (child as CanvasLayer).visible = false

    var official: Node = root.get_node_or_null("GrandPlaceOfficialLod2")
    for _frame: int in range(240):
        if official != null and bool(official.get("geometry_loaded")):
            break
        await process_frame
        official = root.get_node_or_null("GrandPlaceOfficialLod2")
    if official == null or not bool(official.get("geometry_loaded")):
        _fail("production official Town Hall did not load")
        return

    var baseline: Image = await _capture("/tmp/grand-place-town-hall-face-map-baseline.png")
    var policy: Dictionary = contract.get("mapping_policy", {})
    var faces: Array = geometry.get("faces", [])
    var building_center: Vector3 = _building_center(faces)
    var rows: Array[Dictionary] = []
    var lookup: Dictionary = {}
    for raw_face: Variant in faces:
        if typeof(raw_face) != TYPE_DICTIONARY:
            continue
        var face: Dictionary = raw_face as Dictionary
        if str(face.get("type", "")) != "WALLSURFACE":
            continue
        var points: Array[Vector3] = _points(face)
        var bounds: Vector2 = _bounds(points)
        var span: float = _span(points)
        if bounds.x > float(policy.get("lower_face_y_min_max_m", 1.0)) or bounds.y < float(policy.get("lower_face_y_max_min_m", 15.0)) or bounds.y > float(policy.get("lower_face_y_max_max_m", 30.0)) or span < float(policy.get("lower_segment_min_horizontal_span_m", 0.25)):
            continue
        var normal: Vector3 = _normal(face, building_center)
        var center: Vector3 = _centroid(points)
        var facing: float = normal.dot((camera_position - center).normalized())
        if facing < float(policy.get("minimum_camera_facing_dot", 0.02)):
            continue
        var projected: Dictionary = _screen_bbox(camera, points)
        if not bool(projected.get("visible", false)):
            continue
        var face_id: String = str(face.get("id", ""))
        rows.append({"face_id": face_id, "points": points, "normal": [normal.x, normal.y, normal.z], "span_m": span, "facing": facing, "projected_bbox": projected.get("bbox", null)})
        lookup[face_id] = face
    if rows.is_empty() or rows.size() > int(policy.get("max_lower_faces_to_render", 20)):
        _fail("lower-face prefilter invalid")
        return

    var raw_groups: Array = _groups(rows, float(policy.get("connected_endpoint_tolerance_m", 0.08)), float(policy.get("parallel_horizontal_normal_dot_min", 0.985)))
    var candidates: Array[Dictionary] = []
    for group_index: int in range(raw_groups.size()):
        var group: Array = raw_groups[group_index] as Array
        var group_points: Array[Vector3] = _group_points(group)
        var group_span: float = _span(group_points)
        if group_span < float(policy.get("dominant_group_min_horizontal_span_m", 12.0)):
            continue
        var projected: Dictionary = _screen_bbox(camera, group_points)
        candidates.append({"index": group_index, "group": group, "face_ids": _face_ids(group), "span_m": group_span, "projected_area": float(projected.get("area", 0.0)), "projected_bbox": projected.get("bbox", null)})
    if candidates.is_empty():
        _fail("no connected official lower-face chain reaches frozen 12 m span")
        return
    candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("projected_area", 0.0)) > float(b.get("projected_area", 0.0)))

    var dominant: Dictionary = {}
    var rendered: Array[Dictionary] = []
    for order: int in range(candidates.size()):
        var candidate: Dictionary = candidates[order]
        var group: Array = candidate.get("group", [])
        var overlay: MeshInstance3D = _overlay(group, lookup, float(policy.get("overlay_offset_m", 0.012)))
        main.add_child(overlay)
        var image: Image = await _capture("/tmp/grand-place-town-hall-face-group-%02d.png" % [order + 1])
        overlay.queue_free()
        await process_frame
        var metrics: Dictionary = _diff(baseline, image)
        var clean: Dictionary = candidate.duplicate(true) as Dictionary
        clean.erase("group")
        clean["visible_metrics"] = metrics
        rendered.append(clean)
        if dominant.is_empty() and int(metrics.get("changed_gt8_pixels", 0)) >= int(policy.get("minimum_visible_gt8_pixels", 1)):
            dominant = clean
    if dominant.is_empty():
        _fail("12 m official face chains exist but none are actually visible")
        return

    var output_data: Dictionary = {
        "schema": "grand-bruxelles-town-hall-face-map-evidence-v1",
        "status": "evidence_only",
        "runtime_changed": false,
        "geometry_changed": false,
        "urbis_building_id": str(target.get("urbis_building_id", "")),
        "official_package_sha256": str(source.get("package_sha256", "")),
        "wall_face_count": int(counts.get("WALLSURFACE", 0)),
        "camera_source_pr": 711,
        "camera_facing_lower_face_count": rows.size(),
        "eligible_connected_chains": rendered,
        "decision": {
            "dominant_connected_face_ids": dominant.get("face_ids", []),
            "dominant_group_horizontal_span_m": dominant.get("span_m", 0.0),
            "dominant_group_visible_metrics": dominant.get("visible_metrics", {}),
            "heritage_two_wing_identity_proven_by_this_camera": false,
            "heritage_motif_nominated_for_later_only": "ground_floor_gallery_portico",
            "visual_candidate_approved": false
        },
        "first_run_finding": contract.get("first_run_finding", {}),
        "heritage_source": contract.get("heritage_source", {}),
        "hard_rules": hard
    }
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/qa"))
    var output: FileAccess = FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
    output.store_string(JSON.stringify(output_data, "  "))
    output.close()
    var ids: Array = dominant.get("face_ids", [])
    print("GRAND_PLACE_TOWN_HALL_FACE_MAP_JSON " + JSON.stringify(output_data))
    print("GRAND_PLACE_TOWN_HALL_FACE_MAP_OK dominant=%s span=%.3f visible_gt8=%d" % [",".join(ids), float(dominant.get("span_m", 0.0)), int((dominant.get("visible_metrics", {}) as Dictionary).get("changed_gt8_pixels", 0))])
    quit(0)
