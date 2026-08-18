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

func _building_center(faces: Array) -> Vector3:
    var total := Vector3.ZERO
    var count := 0
    for raw_face: Variant in faces:
        if typeof(raw_face) != TYPE_DICTIONARY:
            continue
        for point: Vector3 in _face_points(raw_face as Dictionary):
            total += point
            count += 1
    return total / float(count) if count > 0 else Vector3.ZERO

func _centroid(points: Array[Vector3]) -> Vector3:
    if points.is_empty():
        return Vector3.INF
    var total := Vector3.ZERO
    for point: Vector3 in points:
        total += point
    return total / float(points.size())

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
    var points := _face_points(face)
    var center := _centroid(points)
    var outward := Vector3(center.x - building_center.x, 0.0, center.z - building_center.z)
    var horizontal_normal := Vector3(normal.x, 0.0, normal.z)
    if outward.length_squared() > 0.0001 and horizontal_normal.length_squared() > 0.0001 and horizontal_normal.dot(outward) < 0.0:
        normal = -normal
    return normal

func _horizontal_span(points: Array[Vector3]) -> float:
    var span := 0.0
    for i: int in range(points.size()):
        for j: int in range(i + 1, points.size()):
            var a := Vector2(points[i].x, points[i].z)
            var b := Vector2(points[j].x, points[j].z)
            span = maxf(span, a.distance_to(b))
    return span

func _height_bounds(points: Array[Vector3]) -> Vector2:
    if points.is_empty():
        return Vector2.INF
    var lo := INF
    var hi := -INF
    for point: Vector3 in points:
        lo = minf(lo, point.y)
        hi = maxf(hi, point.y)
    return Vector2(lo, hi)

func _projected_bbox(camera: Camera3D, points: Array[Vector3]) -> Dictionary:
    var min_x := float(WIDTH)
    var min_y := float(HEIGHT)
    var max_x := 0.0
    var max_y := 0.0
    var projected_count := 0
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
        projected_count += 1
    if projected_count == 0:
        return {"visible": false, "bbox": null, "area_px2": 0.0}
    var clip_min_x := clampf(min_x, 0.0, float(WIDTH - 1))
    var clip_min_y := clampf(min_y, 0.0, float(HEIGHT - 1))
    var clip_max_x := clampf(max_x, 0.0, float(WIDTH - 1))
    var clip_max_y := clampf(max_y, 0.0, float(HEIGHT - 1))
    var width := maxf(0.0, clip_max_x - clip_min_x)
    var height := maxf(0.0, clip_max_y - clip_min_y)
    return {
        "visible": width > 0.0 and height > 0.0,
        "bbox": [clip_min_x, clip_min_y, clip_max_x, clip_max_y],
        "area_px2": width * height,
        "width_px": width,
        "height_px": height
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

func _make_overlay(face: Dictionary, normal: Vector3, offset_m: float, label: String) -> MeshInstance3D:
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
            if not point.is_finite():
                continue
            tool.set_normal(normal)
            tool.add_vertex(point + normal * offset_m)
    var overlay := MeshInstance3D.new()
    overlay.name = "TownHallFaceOverlay_%s" % label
    overlay.mesh = tool.commit()
    return overlay

func _sort_projected_desc(a: Dictionary, b: Dictionary) -> bool:
    return float(a.get("projected_bbox_area_px2", 0.0)) > float(b.get("projected_bbox_area_px2", 0.0))

func _best_visible(rows: Array[Dictionary], side: String, building_center_x: float) -> Dictionary:
    var best: Dictionary = {}
    var best_pixels := -1
    for row: Dictionary in rows:
        var centroid_raw: Variant = row.get("centroid", [])
        if typeof(centroid_raw) != TYPE_ARRAY or centroid_raw.size() != 3:
            continue
        var x := float(centroid_raw[0])
        if side == "east" and x <= building_center_x:
            continue
        if side == "west" and x >= building_center_x:
            continue
        var metrics: Dictionary = row.get("visible_metrics", {})
        var pixels := int(metrics.get("changed_gt8_pixels", 0))
        if pixels > best_pixels:
            best_pixels = pixels
            best = row
    return best

func _run() -> void:
    var contract := _read_json(CONTRACT_PATH)
    if contract.is_empty() or str(contract.get("schema", "")) != "grand-bruxelles-town-hall-face-map-contract-v1":
        _fail("contract missing or invalid")
        return
    if str(contract.get("status", "")) != "evidence_only":
        _fail("contract must remain evidence_only")
        return
    var hard_rules: Dictionary = contract.get("hard_rules", {})
    for forbidden_true: String in ["runtime_changed", "geometry_changed", "source_vertices_changed", "author_openings", "author_arcades", "author_portal_depth", "author_statuary", "visual_candidate_approved", "realism_complete"]:
        if bool(hard_rules.get(forbidden_true, true)):
            _fail("hard rule drifted: %s" % forbidden_true)
            return

    var target: Dictionary = contract.get("target", {})
    var geometry_path := str(target.get("geometry_path", ""))
    var geometry := _read_json(geometry_path)
    if geometry.is_empty() or str(geometry.get("schema", "")) != "grand-bruxelles-urbis-context-mesh-v1":
        _fail("official geometry missing or invalid")
        return
    var source: Dictionary = geometry.get("source", {})
    var evidence: Dictionary = geometry.get("evidence", {})
    if str(source.get("building_2d_id", "")) != str(target.get("urbis_building_id", "")):
        _fail("building identity drifted")
        return
    if str(source.get("package_sha256", "")) != str(target.get("expected_package_sha256", "")):
        _fail("official package digest drifted")
        return
    if int(evidence.get("face_type_counts", {}).get("WALLSURFACE", 0)) != int(target.get("expected_wall_face_count", 0)):
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
        _fail("camera values invalid")
        return
    if typeof(resolution) != TYPE_ARRAY or resolution.size() != 2 or int(resolution[0]) != WIDTH or int(resolution[1]) != HEIGHT:
        _fail("camera resolution drifted")
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
        _fail("production official Town Hall runtime identity drifted")
        return

    var baseline := await _capture("/tmp/grand-place-town-hall-face-map-baseline.png")
    if baseline == null:
        _fail("baseline capture failed")
        return

    var faces: Array = geometry.get("faces", [])
    var building_center := _building_center(faces)
    var policy: Dictionary = contract.get("mapping_policy", {})
    var minimum_facing := float(policy.get("minimum_camera_facing_dot", 0.02))
    var y_min_max := float(policy.get("gallery_plane_y_min_max_m", 1.0))
    var y_max_min := float(policy.get("gallery_plane_y_max_min_m", 18.0))
    var y_max_max := float(policy.get("gallery_plane_y_max_max_m", 30.0))
    var min_span := float(policy.get("gallery_plane_min_horizontal_span_m", 12.0))
    var max_render := int(policy.get("max_prefilter_faces_to_render", 14))
    var offset_m := float(policy.get("overlay_offset_m", 0.012))
    var min_visible_pixels := int(policy.get("minimum_visible_gt8_pixels", 1))

    var rows: Array[Dictionary] = []
    var face_by_id: Dictionary = {}
    for raw_face: Variant in faces:
        if typeof(raw_face) != TYPE_DICTIONARY:
            continue
        var face: Dictionary = raw_face
        if str(face.get("type", "")) != "WALLSURFACE":
            continue
        var face_id := str(face.get("id", ""))
        var points := _face_points(face)
        if face_id == "" or points.is_empty():
            continue
        var centroid := _centroid(points)
        var normal := _face_normal(face, building_center)
        if normal.length_squared() < 0.5:
            continue
        var camera_vector := (camera_position - centroid).normalized()
        var facing_dot := normal.dot(camera_vector)
        if facing_dot < minimum_facing:
            continue
        var projected := _projected_bbox(camera, points)
        if not bool(projected.get("visible", false)):
            continue
        var height_bounds := _height_bounds(points)
        var span := _horizontal_span(points)
        var lower_gallery_candidate := height_bounds.x <= y_min_max and height_bounds.y >= y_max_min and height_bounds.y <= y_max_max and span >= min_span
        var row: Dictionary = {
            "face_id": face_id,
            "centroid": [centroid.x, centroid.y, centroid.z],
            "normal": [normal.x, normal.y, normal.z],
            "camera_facing_dot": facing_dot,
            "y_min_m": height_bounds.x,
            "y_max_m": height_bounds.y,
            "horizontal_span_m": span,
            "projected_bbox": projected.get("bbox", null),
            "projected_bbox_width_px": projected.get("width_px", 0.0),
            "projected_bbox_height_px": projected.get("height_px", 0.0),
            "projected_bbox_area_px2": projected.get("area_px2", 0.0),
            "lower_gallery_plane_candidate": lower_gallery_candidate
        }
        rows.append(row)
        face_by_id[face_id] = face

    if rows.is_empty():
        _fail("no camera-facing official WALLSURFACE faces found")
        return
    rows.sort_custom(_sort_projected_desc)

    var render_rows: Array[Dictionary] = []
    var selected_ids: Dictionary = {}
    for row: Dictionary in rows:
        if bool(row.get("lower_gallery_plane_candidate", false)):
            render_rows.append(row)
            selected_ids[str(row.get("face_id", ""))] = true
    for row: Dictionary in rows:
        if render_rows.size() >= max_render:
            break
        var face_id := str(row.get("face_id", ""))
        if selected_ids.has(face_id):
            continue
        render_rows.append(row)
        selected_ids[face_id] = true

    var rendered: Array[Dictionary] = []
    for row: Dictionary in render_rows:
        var face_id := str(row.get("face_id", ""))
        var face: Dictionary = face_by_id.get(face_id, {})
        if face.is_empty():
            _fail("face lookup failed for %s" % face_id)
            return
        var normal_raw: Variant = row.get("normal", [])
        var normal := _v3(normal_raw)
        var label := face_id.replace("https://databrussels.be/id/buildingface/", "")
        var overlay := _make_overlay(face, normal, offset_m, label)
        main.add_child(overlay)
        for _frame: int in range(3):
            _freeze_dynamics(main)
            _mask_ui()
            RenderingServer.force_draw()
            await process_frame
        var capture_path := "/tmp/grand-place-town-hall-face-%s.png" % label
        var image := await _capture(capture_path)
        overlay.queue_free()
        await process_frame
        if image == null:
            _fail("overlay capture failed for %s" % face_id)
            return
        var measured := row.duplicate(true)
        measured["visible_metrics"] = _diff_metrics(baseline, image)
        measured["overlay_capture"] = capture_path
        rendered.append(measured)

    var gallery_visible: Array[Dictionary] = []
    for row: Dictionary in rendered:
        if not bool(row.get("lower_gallery_plane_candidate", false)):
            continue
        var metrics: Dictionary = row.get("visible_metrics", {})
        if int(metrics.get("changed_gt8_pixels", 0)) >= min_visible_pixels:
            gallery_visible.append(row)
    if gallery_visible.size() < 2:
        _fail("fewer than two visible lower Grand-Place-facing wing-plane candidates")
        return

    var east := _best_visible(gallery_visible, "east", building_center.x)
    var west := _best_visible(gallery_visible, "west", building_center.x)
    if east.is_empty() or west.is_empty():
        _fail("could not map distinct east/west lower wing planes around the tower")
        return
    if str(east.get("face_id", "")) == str(west.get("face_id", "")):
        _fail("east/west wing mapping collapsed to one face")
        return

    var evidence_out := {
        "schema": "grand-bruxelles-town-hall-face-map-evidence-v1",
        "status": "evidence_only",
        "runtime_changed": false,
        "geometry_changed": false,
        "camera_contract_path": camera_path,
        "camera_source_pr": 711,
        "resolution": [WIDTH, HEIGHT],
        "urbis_building_id": str(target.get("urbis_building_id", "")),
        "official_package_sha256": str(source.get("package_sha256", "")),
        "wall_face_count": int(evidence.get("face_type_counts", {}).get("WALLSURFACE", 0)),
        "building_center": [building_center.x, building_center.y, building_center.z],
        "camera_facing_faces_ranked": rows,
        "rendered_prefilter_faces": rendered,
        "visible_lower_gallery_plane_candidates": gallery_visible,
        "decision": {
            "east_wing_face_id": str(east.get("face_id", "")),
            "west_wing_face_id": str(west.get("face_id", "")),
            "east_visible_metrics": east.get("visible_metrics", {}),
            "west_visible_metrics": west.get("visible_metrics", {}),
            "heritage_motif_nominated_for_later_only": "ground_floor_gallery_portico",
            "heritage_left_gallery_bays": 11,
            "heritage_right_gallery_bays": 6,
            "visual_candidate_approved": false,
            "next_step": "Review exact mapped face IDs and their full-frame overlays; only a separate current-main implementation PR may attempt one bounded gallery/portico motif."
        },
        "heritage_source": contract.get("heritage_source", {}),
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
    print("GRAND_PLACE_TOWN_HALL_FACE_MAP_OK east=%s west=%s gallery_candidates=%d" % [str(east.get("face_id", "")), str(west.get("face_id", "")), gallery_visible.size()])
    quit(0)
