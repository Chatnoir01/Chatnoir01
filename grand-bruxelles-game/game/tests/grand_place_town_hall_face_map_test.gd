extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const CONTRACT_PATH := "res://data/qa/grand_place_town_hall_face_map_contract.json"
const OUTPUT_PATH := "res://artifacts/qa/grand_place_town_hall_face_map.json"
const WIDTH := 1280
const HEIGHT := 720
const BUILDING_ROOT_NODE := "GrandPlaceOfficialLod2"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_TOWN_HALL_FACE_MAP_FAIL: " + message)
    quit(1)

func _read_json(path: String) -> Dictionary:
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

func _mask_ui() -> void:
    var nodes: Array[Node] = []
    _walk(root, nodes)
    for node: Node in nodes:
        if node is CanvasLayer:
            (node as CanvasLayer).visible = false
        if node is CanvasItem:
            (node as CanvasItem).visible = false

func _visible_canvas_count() -> int:
    var nodes: Array[Node] = []
    _walk(root, nodes)
    var count := 0
    for node: Node in nodes:
        if node is CanvasItem and (node as CanvasItem).is_visible_in_tree():
            count += 1
    return count

func _freeze_dynamics(main: Node) -> void:
    for group_name: String in ["vehicle", "npc"]:
        for node: Node in get_nodes_in_group(group_name):
            node.process_mode = Node.PROCESS_MODE_DISABLED
            if node is Node3D:
                (node as Node3D).visible = false
    for path: String in ["Player", "PrototypeCar", "PhysicalCar", "PhysicalCarB", "TrafficManager", "NpcPopulationDirector", "NpcRuntimeIntegration", "MidiUrbanLife"]:
        var node := main.get_node_or_null(path)
        if node != null:
            node.process_mode = Node.PROCESS_MODE_DISABLED
            if node is Node3D:
                (node as Node3D).visible = false

func _capture(path: String) -> Image:
    for _frame: int in range(5):
        _mask_ui()
        RenderingServer.force_draw()
        await process_frame
    if _visible_canvas_count() != 0:
        return null
    var image := root.get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        return null
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        image.resize(WIDTH, HEIGHT, Image.INTERPOLATE_LANCZOS)
    if image.save_png(path) != OK:
        return null
    return image

func _face_points(face: Dictionary) -> Array[Vector3]:
    var points: Array[Vector3] = []
    for raw_triangle: Variant in face.get("triangles", []):
        if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
            continue
        for raw_point: Variant in raw_triangle:
            var point := _v3(raw_point)
            if point.is_finite():
                points.append(point)
    return points

func _unique_points(points: Array[Vector3]) -> Array[Vector3]:
    var unique: Array[Vector3] = []
    for point: Vector3 in points:
        var found := false
        for existing: Vector3 in unique:
            if existing.distance_to(point) <= 0.0001:
                found = true
                break
        if not found:
            unique.append(point)
    return unique

func _centroid(points: Array[Vector3]) -> Vector3:
    if points.is_empty():
        return Vector3.INF
    var total := Vector3.ZERO
    for point: Vector3 in points:
        total += point
    return total / float(points.size())

func _building_center(faces: Array) -> Vector3:
    var points: Array[Vector3] = []
    for raw_face: Variant in faces:
        if typeof(raw_face) == TYPE_DICTIONARY:
            points.append_array(_face_points(raw_face as Dictionary))
    return _centroid(points) if not points.is_empty() else Vector3.ZERO

func _face_normal(face: Dictionary, building_center: Vector3) -> Vector3:
    var normal := Vector3.ZERO
    for raw_triangle: Variant in face.get("triangles", []):
        if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
            continue
        var a := _v3(raw_triangle[0])
        var b := _v3(raw_triangle[1])
        var c := _v3(raw_triangle[2])
        if not a.is_finite() or not b.is_finite() or not c.is_finite():
            continue
        normal = (b - a).cross(c - a)
        if normal.length_squared() > 0.000001:
            normal = normal.normalized()
            break
    if normal.length_squared() < 0.5:
        return Vector3.ZERO
    var center := _centroid(_face_points(face))
    var outward := Vector3(center.x - building_center.x, 0.0, center.z - building_center.z)
    var horizontal_normal := Vector3(normal.x, 0.0, normal.z)
    if outward.length_squared() > 0.0001 and horizontal_normal.length_squared() > 0.0001 and horizontal_normal.dot(outward) < 0.0:
        normal = -normal
    return normal

func _horizontal_normal(normal: Vector3) -> Vector3:
    var horizontal := Vector3(normal.x, 0.0, normal.z)
    return horizontal.normalized() if horizontal.length_squared() > 0.000001 else Vector3.ZERO

func _height_bounds(points: Array[Vector3]) -> Vector2:
    if points.is_empty():
        return Vector2.INF
    var low := INF
    var high := -INF
    for point: Vector3 in points:
        low = minf(low, point.y)
        high = maxf(high, point.y)
    return Vector2(low, high)

func _horizontal_span(points: Array[Vector3]) -> float:
    var span := 0.0
    for i: int in range(points.size()):
        for j: int in range(i + 1, points.size()):
            span = maxf(span, Vector2(points[i].x, points[i].z).distance_to(Vector2(points[j].x, points[j].z)))
    return span

func _projected_bbox(camera: Camera3D, points: Array[Vector3]) -> Dictionary:
    var min_x := float(WIDTH)
    var min_y := float(HEIGHT)
    var max_x := 0.0
    var max_y := 0.0
    var projected := 0
    for point: Vector3 in points:
        if camera.is_position_behind(point):
            continue
        var screen := camera.unproject_position(point)
        if not is_finite(screen.x) or not is_finite(screen.y):
            continue
        min_x = minf(min_x, screen.x)
        min_y = minf(min_y, screen.y)
        max_x = maxf(max_x, screen.x)
        max_y = maxf(max_y, screen.y)
        projected += 1
    if projected == 0:
        return {"visible": false, "bbox": null, "width_px": 0.0, "height_px": 0.0, "area_px2": 0.0}
    var x0 := clampf(min_x, 0.0, float(WIDTH - 1))
    var y0 := clampf(min_y, 0.0, float(HEIGHT - 1))
    var x1 := clampf(max_x, 0.0, float(WIDTH - 1))
    var y1 := clampf(max_y, 0.0, float(HEIGHT - 1))
    var width := maxf(0.0, x1 - x0)
    var height := maxf(0.0, y1 - y0)
    return {
        "visible": width > 0.0 and height > 0.0,
        "bbox": [x0, y0, x1, y1],
        "width_px": width,
        "height_px": height,
        "area_px2": width * height
    }

func _diff_metrics(baseline: Image, overlay: Image) -> Dictionary:
    var changed8 := 0
    var changed20 := 0
    var min_x := WIDTH
    var min_y := HEIGHT
    var max_x := -1
    var max_y := -1
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := baseline.get_pixel(x, y)
            var b := overlay.get_pixel(x, y)
            var delta := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) * 255.0
            if delta > 8.0:
                changed8 += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
            if delta > 20.0:
                changed20 += 1
    var bbox: Variant = null
    var bbox_width := 0
    var bbox_height := 0
    if max_x >= min_x and max_y >= min_y:
        bbox = [min_x, min_y, max_x, max_y]
        bbox_width = max_x - min_x + 1
        bbox_height = max_y - min_y + 1
    var total := float(WIDTH * HEIGHT)
    return {
        "changed_gt8_pixels": changed8,
        "changed_gt20_pixels": changed20,
        "changed_gt8_percent": 100.0 * float(changed8) / total,
        "changed_gt20_percent": 100.0 * float(changed20) / total,
        "bbox": bbox,
        "bbox_width_px": bbox_width,
        "bbox_height_px": bbox_height
    }

func _faces_connected(a: Dictionary, b: Dictionary, endpoint_tolerance: float, parallel_dot_min: float) -> bool:
    var normal_a := _horizontal_normal(_v3(a.get("normal", [])))
    var normal_b := _horizontal_normal(_v3(b.get("normal", [])))
    if normal_a.length_squared() < 0.5 or normal_b.length_squared() < 0.5:
        return false
    if normal_a.dot(normal_b) < parallel_dot_min:
        return false
    var points_a: Array[Vector3] = a.get("points", [])
    var points_b: Array[Vector3] = b.get("points", [])
    for point_a: Vector3 in points_a:
        for point_b: Vector3 in points_b:
            if Vector2(point_a.x, point_a.z).distance_to(Vector2(point_b.x, point_b.z)) <= endpoint_tolerance:
                return true
    return false

func _build_groups(rows: Array[Dictionary], endpoint_tolerance: float, parallel_dot_min: float) -> Array[Array]:
    var groups: Array[Array] = []
    var visited: Dictionary = {}
    for start_index: int in range(rows.size()):
        if visited.has(start_index):
            continue
        var group: Array = []
        var queue: Array[int] = [start_index]
        visited[start_index] = true
        while not queue.is_empty():
            var index := queue.pop_front()
            group.append(rows[index])
            for other_index: int in range(rows.size()):
                if visited.has(other_index):
                    continue
                var connects := false
                for member: Variant in group:
                    if _faces_connected(member as Dictionary, rows[other_index], endpoint_tolerance, parallel_dot_min):
                        connects = true
                        break
                if connects:
                    visited[other_index] = true
                    queue.append(other_index)
        groups.append(group)
    return groups

func _group_points(group: Array) -> Array[Vector3]:
    var points: Array[Vector3] = []
    for raw_row: Variant in group:
        var row: Dictionary = raw_row
        var row_points: Array[Vector3] = row.get("points", [])
        points.append_array(row_points)
    return _unique_points(points)

func _group_face_ids(group: Array) -> Array[String]:
    var ids: Array[String] = []
    for raw_row: Variant in group:
        ids.append(str((raw_row as Dictionary).get("face_id", "")))
    ids.sort()
    return ids

func _make_group_overlay(group: Array, face_by_id: Dictionary, offset_m: float, label: String) -> MeshInstance3D:
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(1.0, 0.02, 0.58, 1.0)
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    tool.set_material(material)
    for raw_row: Variant in group:
        var row: Dictionary = raw_row
        var face_id := str(row.get("face_id", ""))
        var face: Dictionary = face_by_id.get(face_id, {})
        var normal := _v3(row.get("normal", []))
        if face.is_empty() or not normal.is_finite():
            continue
        for raw_triangle: Variant in face.get("triangles", []):
            if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
                continue
            for raw_point: Variant in raw_triangle:
                var point := _v3(raw_point)
                if point.is_finite():
                    tool.set_normal(normal)
                    tool.add_vertex(point + normal * offset_m)
    var overlay := MeshInstance3D.new()
    overlay.name = "TownHallFaceGroupOverlay_%s" % label
    overlay.mesh = tool.commit()
    return overlay

func _sort_group_projected_desc(a: Dictionary, b: Dictionary) -> bool:
    return float(a.get("projected_bbox_area_px2", 0.0)) > float(b.get("projected_bbox_area_px2", 0.0))

func _sort_group_visible_desc(a: Dictionary, b: Dictionary) -> bool:
    return int((a.get("visible_metrics", {}) as Dictionary).get("changed_gt8_pixels", 0)) > int((b.get("visible_metrics", {}) as Dictionary).get("changed_gt8_pixels", 0))

func _run() -> void:
    var contract := _read_json(CONTRACT_PATH)
    if contract.is_empty() or str(contract.get("schema", "")) != "grand-bruxelles-town-hall-face-map-contract-v1":
        _fail("contract missing or invalid")
        return
    if str(contract.get("status", "")) != "evidence_only":
        _fail("contract must remain evidence_only")
        return
    var hard_rules: Dictionary = contract.get("hard_rules", {})
    for key: String in ["runtime_changed", "geometry_changed", "source_vertices_changed", "author_openings", "author_arcades", "author_portal_depth", "author_statuary", "visual_candidate_approved", "realism_complete"]:
        if bool(hard_rules.get(key, true)):
            _fail("hard rule drifted: %s" % key)
            return

    var target: Dictionary = contract.get("target", {})
    var geometry := _read_json(str(target.get("geometry_path", "")))
    if geometry.is_empty() or str(geometry.get("schema", "")) != "grand-bruxelles-urbis-context-mesh-v1":
        _fail("official geometry missing or invalid")
        return
    var source: Dictionary = geometry.get("source", {})
    var source_evidence: Dictionary = geometry.get("evidence", {})
    if str(source.get("building_2d_id", "")) != str(target.get("urbis_building_id", "")):
        _fail("building identity drifted")
        return
    if str(source.get("package_sha256", "")) != str(target.get("expected_package_sha256", "")):
        _fail("official package digest drifted")
        return
    if int((source_evidence.get("face_type_counts", {}) as Dictionary).get("WALLSURFACE", 0)) != int(target.get("expected_wall_face_count", 0)):
        _fail("official WALLSURFACE count drifted")
        return

    var camera_path := str(contract.get("camera_contract_path", ""))
    var camera_contract := _read_json(camera_path)
    if camera_contract.is_empty() or int(camera_contract.get("source_pr", 0)) != 711:
        _fail("canonical #753/#711 camera contract missing")
        return
    var camera_position := _v3(camera_contract.get("camera_position", []))
    var camera_target := _v3(camera_contract.get("camera_target", []))
    var camera_fov := float(camera_contract.get("camera_fov_deg", 0.0))
    var resolution: Variant = camera_contract.get("resolution", [])
    if not camera_position.is_finite() or not camera_target.is_finite() or camera_fov <= 1.0:
        _fail("canonical camera values invalid")
        return
    if typeof(resolution) != TYPE_ARRAY or resolution.size() != 2 or int(resolution[0]) != WIDTH or int(resolution[1]) != HEIGHT:
        _fail("canonical camera resolution drifted")
        return

    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    var old_camera := main.get_viewport().get_camera_3d()
    if old_camera != null:
        old_camera.current = false
    var camera := Camera3D.new()
    camera.name = "GrandPlaceTownHallFaceMapCamera"
    camera.position = camera_position
    camera.fov = camera_fov
    main.add_child(camera)
    camera.look_at(camera_target, Vector3.UP)
    camera.current = true

    var official := root.get_node_or_null(BUILDING_ROOT_NODE)
    for _frame: int in range(240):
        _freeze_dynamics(main)
        _mask_ui()
        if official != null and bool(official.get("geometry_loaded")):
            break
        await process_frame
        official = root.get_node_or_null(BUILDING_ROOT_NODE)
    if official == null or not bool(official.get("geometry_loaded")):
        _fail("production official Town Hall runtime did not load")
        return
    if str(official.get_meta("building_id", "")) != str(target.get("urbis_building_id", "")):
        _fail("production official Town Hall identity drifted")
        return

    var baseline := await _capture("/tmp/grand-place-town-hall-face-map-baseline.png")
    if baseline == null:
        _fail("baseline capture failed")
        return

    var policy: Dictionary = contract.get("mapping_policy", {})
    var max_faces := int(policy.get("max_lower_faces_to_render", 20))
    var y_min_max := float(policy.get("lower_face_y_min_max_m", 1.0))
    var y_max_min := float(policy.get("lower_face_y_max_min_m", 15.0))
    var y_max_max := float(policy.get("lower_face_y_max_max_m", 30.0))
    var min_segment_span := float(policy.get("lower_segment_min_horizontal_span_m", 0.25))
    var min_facing := float(policy.get("minimum_camera_facing_dot", 0.02))
    var endpoint_tolerance := float(policy.get("connected_endpoint_tolerance_m", 0.08))
    var parallel_dot_min := float(policy.get("parallel_horizontal_normal_dot_min", 0.985))
    var min_group_span := float(policy.get("dominant_group_min_horizontal_span_m", 12.0))
    var offset_m := float(policy.get("overlay_offset_m", 0.012))
    var min_visible_pixels := int(policy.get("minimum_visible_gt8_pixels", 1))

    var faces: Array = geometry.get("faces", [])
    var building_center := _building_center(faces)
    var rows: Array[Dictionary] = []
    var face_by_id: Dictionary = {}
    for raw_face: Variant in faces:
        if typeof(raw_face) != TYPE_DICTIONARY:
            continue
        var face: Dictionary = raw_face
        if str(face.get("type", "")) != "WALLSURFACE":
            continue
        var face_id := str(face.get("id", ""))
        var points := _unique_points(_face_points(face))
        if face_id == "" or points.size() < 3:
            continue
        var height := _height_bounds(points)
        var span := _horizontal_span(points)
        if height.x > y_min_max or height.y < y_max_min or height.y > y_max_max or span < min_segment_span:
            continue
        var normal := _face_normal(face, building_center)
        if normal.length_squared() < 0.5:
            continue
        var center := _centroid(points)
        var camera_vector := (camera_position - center).normalized()
        var facing_dot := normal.dot(camera_vector)
        if facing_dot < min_facing:
            continue
        var projected := _projected_bbox(camera, points)
        if not bool(projected.get("visible", false)):
            continue
        rows.append({
            "face_id": face_id,
            "points": points,
            "centroid": [center.x, center.y, center.z],
            "normal": [normal.x, normal.y, normal.z],
            "camera_facing_dot": facing_dot,
            "y_min_m": height.x,
            "y_max_m": height.y,
            "horizontal_span_m": span,
            "projected_bbox": projected.get("bbox", null),
            "projected_bbox_width_px": projected.get("width_px", 0.0),
            "projected_bbox_height_px": projected.get("height_px", 0.0),
            "projected_bbox_area_px2": projected.get("area_px2", 0.0)
        })
        face_by_id[face_id] = face

    if rows.is_empty():
        _fail("no camera-facing lower official WALLSURFACE faces found")
        return
    if rows.size() > max_faces:
        _fail("lower camera-facing face set exceeds frozen render cap: %d > %d" % [rows.size(), max_faces])
        return

    var raw_groups := _build_groups(rows, endpoint_tolerance, parallel_dot_min)
    var group_records: Array[Dictionary] = []
    for group_index: int in range(raw_groups.size()):
        var group: Array = raw_groups[group_index]
        var group_points := _group_points(group)
        var group_span := _horizontal_span(group_points)
        var projected := _projected_bbox(camera, group_points)
        var face_ids := _group_face_ids(group)
        group_records.append({
            "group_index": group_index,
            "face_ids": face_ids,
            "face_count": face_ids.size(),
            "horizontal_span_m": group_span,
            "projected_bbox": projected.get("bbox", null),
            "projected_bbox_width_px": projected.get("width_px", 0.0),
            "projected_bbox_height_px": projected.get("height_px", 0.0),
            "projected_bbox_area_px2": projected.get("area_px2", 0.0),
            "raw_group": group
        })
    group_records.sort_custom(_sort_group_projected_desc)

    var rendered_groups: Array[Dictionary] = []
    for display_index: int in range(group_records.size()):
        var record := group_records[display_index]
        var group: Array = record.get("raw_group", [])
        var label := "%02d" % [display_index + 1]
        var overlay := _make_group_overlay(group, face_by_id, offset_m, label)
        main.add_child(overlay)
        for _frame: int in range(3):
            _freeze_dynamics(main)
            _mask_ui()
            RenderingServer.force_draw()
            await process_frame
        var capture_path := "/tmp/grand-place-town-hall-face-group-%s.png" % label
        var image := await _capture(capture_path)
        overlay.queue_free()
        await process_frame
        if image == null:
            _fail("group overlay capture failed: %s" % label)
            return
        var clean_record := record.duplicate(true)
        clean_record.erase("raw_group")
        clean_record["visible_metrics"] = _diff_metrics(baseline, image)
        clean_record["overlay_capture"] = capture_path
        rendered_groups.append(clean_record)

    rendered_groups.sort_custom(_sort_group_visible_desc)
    var dominant: Dictionary = {}
    for record: Dictionary in rendered_groups:
        var metrics: Dictionary = record.get("visible_metrics", {})
        if float(record.get("horizontal_span_m", 0.0)) >= min_group_span and int(metrics.get("changed_gt8_pixels", 0)) >= min_visible_pixels:
            dominant = record
            break
    if dominant.is_empty():
        _fail("no connected official lower-face group meets the frozen 12 m source span plus real pixel visibility requirement")
        return

    var candidate_rows: Array[Dictionary] = []
    for row: Dictionary in rows:
        var clean := row.duplicate(true)
        clean.erase("points")
        candidate_rows.append(clean)

    var visible_group_count := 0
    for record: Dictionary in rendered_groups:
        if int((record.get("visible_metrics", {}) as Dictionary).get("changed_gt8_pixels", 0)) >= min_visible_pixels:
            visible_group_count += 1

    var evidence_out := {
        "schema": "grand-bruxelles-town-hall-face-map-evidence-v1",
        "status": "evidence_only",
        "runtime_changed": false,
        "geometry_changed": false,
        "camera_contract_path": camera_path,
        "camera_source_pr": 711,
        "camera_position": [camera_position.x, camera_position.y, camera_position.z],
        "camera_target": [camera_target.x, camera_target.y, camera_target.z],
        "camera_fov_deg": camera_fov,
        "resolution": [WIDTH, HEIGHT],
        "urbis_building_id": str(target.get("urbis_building_id", "")),
        "official_package_sha256": str(source.get("package_sha256", "")),
        "wall_face_count": int((source_evidence.get("face_type_counts", {}) as Dictionary).get("WALLSURFACE", 0)),
        "camera_facing_lower_face_count": rows.size(),
        "connected_group_count": rendered_groups.size(),
        "visible_connected_group_count": visible_group_count,
        "camera_facing_lower_faces": candidate_rows,
        "connected_groups_ranked_by_visible_pixels": rendered_groups,
        "decision": {
            "dominant_connected_face_ids": dominant.get("face_ids", []),
            "dominant_group_horizontal_span_m": dominant.get("horizontal_span_m", 0.0),
            "dominant_group_visible_metrics": dominant.get("visible_metrics", {}),
            "heritage_two_wing_identity_proven_by_this_camera": false,
            "heritage_motif_nominated_for_later_only": "ground_floor_gallery_portico",
            "heritage_left_gallery_bays": 11,
            "heritage_right_gallery_bays": 6,
            "visual_candidate_approved": false,
            "reason": "The canonical camera proves exact connected official lower facade coverage. It does not by itself prove east/west heritage wing identity or authorize arcade/opening placement.",
            "next_step": "Human-review the dominant exact-face overlay and IDs. If legitimate, close this evidence PR and create a separate current-main visual proposal limited to one heritage-backed motif on the proven source plane."
        },
        "heritage_source": contract.get("heritage_source", {}),
        "first_run_finding": contract.get("first_run_finding", {}),
        "hard_rules": hard_rules
    }
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/qa"))
    var output := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
    if output == null:
        _fail("cannot write face-map evidence")
        return
    output.store_string(JSON.stringify(evidence_out, "  "))
    output.close()
    print("GRAND_PLACE_TOWN_HALL_FACE_MAP_JSON " + JSON.stringify(evidence_out))
    print("GRAND_PLACE_TOWN_HALL_FACE_MAP_OK dominant=%s span=%.3f visible_gt8=%d groups=%d" % [
        ",".join(dominant.get("face_ids", [])),
        float(dominant.get("horizontal_span_m", 0.0)),
        int((dominant.get("visible_metrics", {}) as Dictionary).get("changed_gt8_pixels", 0)),
        rendered_groups.size()
    ])
    quit(0)
