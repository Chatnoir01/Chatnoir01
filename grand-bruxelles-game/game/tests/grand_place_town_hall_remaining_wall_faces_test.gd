extends SceneTree

const MAIN_SCENE = preload("res://game/main.tscn")
const CONTRACT_PATH := "res://data/qa/grand_place_town_hall_remaining_wall_faces.json"
const OUTPUT_PATH := "res://artifacts/qa/grand_place_town_hall_remaining_wall_faces.json"
const BASELINE_PATH := "res://artifacts/qa/grand_place_town_hall_remaining_wall_baseline.png"
const WINNER_PATH := "res://artifacts/qa/grand_place_town_hall_remaining_wall_winner.png"
const RUNNER_UP_PATH := "res://artifacts/qa/grand_place_town_hall_remaining_wall_runner_up.png"
const WIDTH := 1280
const HEIGHT := 720

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_REMAINING_WALL_FACES_FAIL: " + message)
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

func _points(face: Dictionary) -> Array[Vector3]:
    var out: Array[Vector3] = []
    for raw_triangle: Variant in face.get("triangles", []):
        if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
            continue
        for raw_point: Variant in raw_triangle:
            var point := _v3(raw_point)
            if not point.is_finite():
                continue
            var duplicate := false
            for existing: Vector3 in out:
                if existing.distance_to(point) <= 0.0001:
                    duplicate = true
                    break
            if not duplicate:
                out.append(point)
    return out

func _centroid(points: Array[Vector3]) -> Vector3:
    if points.is_empty():
        return Vector3.ZERO
    var total := Vector3.ZERO
    for point: Vector3 in points:
        total += point
    return total / float(points.size())

func _building_center(faces: Array) -> Vector3:
    var total := Vector3.ZERO
    var count := 0
    for raw_face: Variant in faces:
        if typeof(raw_face) != TYPE_DICTIONARY:
            continue
        for point: Vector3 in _points(raw_face as Dictionary):
            total += point
            count += 1
    return total / float(count) if count > 0 else Vector3.ZERO

func _normal(face: Dictionary, building_center: Vector3) -> Vector3:
    var result := Vector3.ZERO
    for raw_triangle: Variant in face.get("triangles", []):
        if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
            continue
        var a := _v3(raw_triangle[0])
        var b := _v3(raw_triangle[1])
        var c := _v3(raw_triangle[2])
        result = (b - a).cross(c - a)
        if result.length_squared() > 0.000001:
            result = result.normalized()
            break
    if result.length_squared() < 0.5:
        return Vector3.ZERO
    var center := _centroid(_points(face))
    var outward := Vector3(center.x - building_center.x, 0.0, center.z - building_center.z)
    var horizontal := Vector3(result.x, 0.0, result.z)
    if outward.length_squared() > 0.0001 and horizontal.length_squared() > 0.0001 and horizontal.dot(outward) < 0.0:
        result = -result
    return result

func _horizontal(normal: Vector3) -> Vector3:
    var value := Vector3(normal.x, 0.0, normal.z)
    return value.normalized() if value.length_squared() > 0.000001 else Vector3.ZERO

func _span(points: Array[Vector3]) -> float:
    var result := 0.0
    for i: int in range(points.size()):
        for j: int in range(i + 1, points.size()):
            result = maxf(result, Vector2(points[i].x, points[i].z).distance_to(Vector2(points[j].x, points[j].z)))
    return result

func _y_bounds(points: Array[Vector3]) -> Vector2:
    var low := INF
    var high := -INF
    for point: Vector3 in points:
        low = minf(low, point.y)
        high = maxf(high, point.y)
    return Vector2(low, high)

func _screen_bbox(camera: Camera3D, points: Array[Vector3]) -> Dictionary:
    var x0 := float(WIDTH)
    var y0 := float(HEIGHT)
    var x1 := 0.0
    var y1 := 0.0
    var count := 0
    for point: Vector3 in points:
        if camera.is_position_behind(point):
            continue
        var screen := camera.unproject_position(point)
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
    return {
        "visible": x1 > x0 and y1 > y0,
        "area": maxf(0.0, x1 - x0) * maxf(0.0, y1 - y0),
        "bbox": [x0, y0, x1, y1]
    }

func _connected(a: Dictionary, b: Dictionary, tolerance: float, parallel_min: float) -> bool:
    var na := _horizontal(_v3(a.get("normal", [])))
    var nb := _horizontal(_v3(b.get("normal", [])))
    if na.length_squared() < 0.5 or nb.length_squared() < 0.5 or na.dot(nb) < parallel_min:
        return false
    var pa: Array[Vector3] = a.get("points", [])
    var pb: Array[Vector3] = b.get("points", [])
    for point_a: Vector3 in pa:
        for point_b: Vector3 in pb:
            if point_a.distance_to(point_b) <= tolerance:
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
            var index := int(queue.pop_front())
            group.append(rows[index])
            for other: int in range(rows.size()):
                if seen.has(other):
                    continue
                var joins := false
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
        for point: Vector3 in (raw_row as Dictionary).get("points", []):
            var duplicate := false
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
        ids.append(str((raw_row as Dictionary).get("short_id", "")))
    ids.sort()
    return ids

func _triangle_count(group: Array) -> int:
    var total := 0
    for raw_row: Variant in group:
        total += int((raw_row as Dictionary).get("triangle_count", 0))
    return total

func _overlay(group: Array, face_lookup: Dictionary, offset: float) -> MeshInstance3D:
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(1.0, 0.02, 0.58, 1.0)
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    tool.set_material(material)
    for raw_row: Variant in group:
        var row := raw_row as Dictionary
        var face: Dictionary = face_lookup.get(str(row.get("full_id", "")), {})
        var normal := _v3(row.get("normal", []))
        for raw_triangle: Variant in face.get("triangles", []):
            if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
                continue
            for raw_point: Variant in raw_triangle:
                tool.set_normal(normal)
                tool.add_vertex(_v3(raw_point) + normal * offset)
    var mesh := MeshInstance3D.new()
    mesh.mesh = tool.commit()
    mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    return mesh

func _capture(path: String) -> Image:
    for _frame: int in range(5):
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
    var bbox: Variant = null
    var bbox_width := 0
    var bbox_height := 0
    if pixels > 0:
        bbox = [x0, y0, x1, y1]
        bbox_width = x1 - x0 + 1
        bbox_height = y1 - y0 + 1
    return {
        "changed_gt8_pixels": pixels,
        "changed_gt8_percent": 100.0 * float(pixels) / float(WIDTH * HEIGHT),
        "bbox": bbox,
        "bbox_width": bbox_width,
        "bbox_height": bbox_height
    }

func _run() -> void:
    var contract := _json(CONTRACT_PATH)
    if str(contract.get("schema", "")) != "grand-bruxelles-town-hall-remaining-wall-face-audit-v1":
        _fail("contract missing or schema drift")
        return
    var hard: Dictionary = contract.get("hard_rules", {})
    for key: String in ["runtime_changed", "geometry_changed", "source_vertices_changed", "camera_changed", "excluded_faces_reintroduced", "author_openings", "author_portal_depth", "author_tower_detail", "author_statuary", "reuse_783_dimensions", "implementation_authorized", "visual_candidate_approved", "realism_complete"]:
        if bool(hard.get(key, true)):
            _fail("hard rule drift: " + key)
            return

    var target: Dictionary = contract.get("target", {})
    var geometry := _json(str(target.get("geometry_path", "")))
    var source: Dictionary = geometry.get("source", {})
    var evidence: Dictionary = geometry.get("evidence", {})
    var counts: Dictionary = evidence.get("face_type_counts", {})
    if str(source.get("building_2d_id", "")) != str(target.get("urbis_building_id", "")):
        _fail("official building identity drift")
        return
    if str(source.get("package_sha256", "")) != str(target.get("expected_package_sha256", "")) or str(source.get("license", "")) != "CC0-1.0":
        _fail("official source provenance drift")
        return
    if int(counts.get("WALLSURFACE", 0)) != int(target.get("expected_wall_face_count", 0)):
        _fail("official WALLSURFACE count drift")
        return

    var excluded: Dictionary = {}
    for raw_exclusion: Variant in contract.get("excluded_from_winner", []):
        if typeof(raw_exclusion) != TYPE_DICTIONARY:
            continue
        var exclusion := raw_exclusion as Dictionary
        excluded[str(exclusion.get("face_id", ""))] = str(exclusion.get("reason", ""))
    for required_id: String in ["10792525", "10798452", "10792523"]:
        if not excluded.has(required_id):
            _fail("required exclusion missing: " + required_id)
            return

    var camera_contract := _json(str(contract.get("camera_contract_path", "")))
    var resolution: Array = camera_contract.get("resolution", [])
    if int(camera_contract.get("source_pr", 0)) != 711 or resolution.size() != 2 or int(resolution[0]) != WIDTH or int(resolution[1]) != HEIGHT:
        _fail("canonical #711/#753 camera contract drift")
        return
    var camera_position := _v3(camera_contract.get("camera_position", []))
    var camera_target := _v3(camera_contract.get("camera_target", []))
    var camera_fov := float(camera_contract.get("camera_fov_deg", 0.0))
    if camera_position.distance_to(Vector3(319.01, 1.72, -535.20)) > 0.0001 or camera_target.distance_to(Vector3(321.91, 11.8, -485.66)) > 0.0001 or absf(camera_fov - 62.0) > 0.0001:
        _fail("canonical #711/#753 camera values drift")
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

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/qa"))
    var baseline := await _capture(ProjectSettings.globalize_path(BASELINE_PATH))
    var policy: Dictionary = contract.get("grouping_policy", {})
    var faces: Array = geometry.get("faces", [])
    var building_center := _building_center(faces)
    var rows: Array[Dictionary] = []
    var lookup: Dictionary = {}
    var excluded_rows: Array = []

    for raw_face: Variant in faces:
        if typeof(raw_face) != TYPE_DICTIONARY:
            continue
        var face := raw_face as Dictionary
        if str(face.get("type", "")) != str(policy.get("wall_face_type", "WALLSURFACE")):
            continue
        var full_id := str(face.get("id", ""))
        var short_id := _short_id(full_id)
        if excluded.has(short_id):
            excluded_rows.append({"face_id": short_id, "reason": excluded[short_id]})
            continue
        var points := _points(face)
        if points.size() < 3:
            continue
        var normal := _normal(face, building_center)
        if normal.length_squared() < 0.5:
            continue
        var center := _centroid(points)
        var facing := normal.dot((camera_position - center).normalized())
        if facing < float(policy.get("minimum_camera_facing_dot", 0.02)):
            continue
        var projected := _screen_bbox(camera, points)
        if not bool(projected.get("visible", false)):
            continue
        var y_bounds := _y_bounds(points)
        rows.append({
            "full_id": full_id,
            "short_id": short_id,
            "points": points,
            "normal": [normal.x, normal.y, normal.z],
            "facing_dot": facing,
            "horizontal_span_m": _span(points),
            "y_min_m": y_bounds.x,
            "y_max_m": y_bounds.y,
            "triangle_count": (face.get("triangles", []) as Array).size(),
            "projected_bbox": projected.get("bbox", null),
            "projected_bbox_area_px": float(projected.get("area", 0.0))
        })
        lookup[full_id] = face

    if rows.is_empty():
        _fail("no remaining camera-facing official wall faces")
        return

    var raw_groups := _groups(rows, float(policy.get("connected_endpoint_tolerance_m", 0.08)), float(policy.get("parallel_horizontal_normal_dot_min", 0.985)))
    if raw_groups.is_empty() or raw_groups.size() > int(policy.get("max_candidate_groups", 32)):
        _fail("candidate group count outside frozen bound: %d" % raw_groups.size())
        return

    var candidates: Array[Dictionary] = []
    for group_index: int in range(raw_groups.size()):
        var group: Array = raw_groups[group_index]
        var group_points := _group_points(group)
        var projected := _screen_bbox(camera, group_points)
        var y_bounds := _y_bounds(group_points)
        candidates.append({
            "group_index": group_index,
            "group": group,
            "face_ids": _face_ids(group),
            "face_count": group.size(),
            "triangle_count": _triangle_count(group),
            "horizontal_span_m": _span(group_points),
            "y_min_m": y_bounds.x,
            "y_max_m": y_bounds.y,
            "projected_bbox": projected.get("bbox", null),
            "projected_bbox_area_px": float(projected.get("area", 0.0))
        })
    candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("projected_bbox_area_px", 0.0)) > float(b.get("projected_bbox_area_px", 0.0)))

    var rendered: Array[Dictionary] = []
    for order: int in range(candidates.size()):
        var candidate := candidates[order]
        var group: Array = candidate.get("group", [])
        var overlay := _overlay(group, lookup, float(policy.get("overlay_offset_m", 0.012)))
        main.add_child(overlay)
        var temp_path := "/tmp/grand-place-remaining-wall-group-%02d.png" % (order + 1)
        var image := await _capture(temp_path)
        overlay.queue_free()
        await process_frame
        var clean := candidate.duplicate(true) as Dictionary
        clean.erase("group")
        clean["visible_metrics"] = _diff(baseline, image)
        clean["temp_capture_path"] = temp_path
        rendered.append(clean)

    rendered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return int((a.get("visible_metrics", {}) as Dictionary).get("changed_gt8_pixels", 0)) > int((b.get("visible_metrics", {}) as Dictionary).get("changed_gt8_pixels", 0))
    )
    if rendered.is_empty():
        _fail("no rendered remaining wall groups")
        return
    var winner := rendered[0]
    var winner_metrics: Dictionary = winner.get("visible_metrics", {})
    if int(winner_metrics.get("changed_gt8_pixels", 0)) < int(policy.get("minimum_visible_gt8_pixels", 1)):
        _fail("remaining official walls exist but none are naturally visible")
        return

    var winner_image := Image.load_from_file(str(winner.get("temp_capture_path", "")))
    if winner_image.is_empty():
        _fail("winner evidence image missing")
        return
    winner_image.save_png(ProjectSettings.globalize_path(WINNER_PATH))
    if rendered.size() > 1:
        var runner_image := Image.load_from_file(str(rendered[1].get("temp_capture_path", "")))
        if not runner_image.is_empty():
            runner_image.save_png(ProjectSettings.globalize_path(RUNNER_UP_PATH))

    for row: Dictionary in rendered:
        row.erase("temp_capture_path")

    var output_data := {
        "schema": "grand-bruxelles-town-hall-remaining-wall-face-evidence-v1",
        "status": "evidence_only",
        "runtime_changed": false,
        "geometry_changed": false,
        "camera_source_pr": 711,
        "urbis_building_id": str(target.get("urbis_building_id", "")),
        "official_package_sha256": str(source.get("package_sha256", "")),
        "official_wall_face_count": int(counts.get("WALLSURFACE", 0)),
        "excluded_faces": excluded_rows,
        "remaining_camera_facing_face_count": rows.size(),
        "candidate_group_count": rendered.size(),
        "ranked_groups": rendered,
        "decision": {
            "winner_face_ids": winner.get("face_ids", []),
            "winner_visible_metrics": winner_metrics,
            "winner_horizontal_span_m": winner.get("horizontal_span_m", 0.0),
            "winner_y_min_m": winner.get("y_min_m", 0.0),
            "winner_y_max_m": winner.get("y_max_m", 0.0),
            "next_step": "source_and_metric_evidence_only",
            "implementation_authorized": false,
            "reuse_783_dimensions": false
        },
        "hard_rules": hard
    }
    var output := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
    if output == null:
        _fail("cannot write evidence JSON")
        return
    output.store_string(JSON.stringify(output_data, "  "))
    output.close()
    print("GRAND_PLACE_REMAINING_WALL_FACES_JSON " + JSON.stringify(output_data))
    print("GRAND_PLACE_REMAINING_WALL_FACES_OK winner=%s pixels=%d groups=%d" % [",".join(winner.get("face_ids", [])), int(winner_metrics.get("changed_gt8_pixels", 0)), rendered.size()])
    quit(0)
