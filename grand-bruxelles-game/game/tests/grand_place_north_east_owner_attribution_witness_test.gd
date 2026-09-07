extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const SOURCE_DIR := "res://data/urbis/grand_place_lod2"
const WIDTH := 1280
const HEIGHT := 720
const CAMERA_POSITION := Vector3(319.01, 1.72, -535.20)
const CAMERA_FOV := 62.0
const EXPECTED_SOURCE_OWNER_COUNT := 25
const EXPECTED_CONTOUR_OWNER_COUNT := 23
const DEDICATED_OWNER_IDS := ["1655673", "1786758"]

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_NORTH_EAST_OWNER_ATTRIBUTION_FAIL: %s" % message)
    quit(1)

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
        var target := main.get_node_or_null(path)
        if target != null:
            target.process_mode = Node.PROCESS_MODE_DISABLED
            if target is Node3D:
                (target as Node3D).visible = false

func _source_owner_ids() -> Array[String]:
    var dir := DirAccess.open(SOURCE_DIR)
    if dir == null:
        return []
    var ids: Array[String] = []
    for file_name: String in dir.get_files():
        if file_name.ends_with(".game.json"):
            ids.append(file_name.trim_suffix(".game.json"))
    ids.sort()
    return ids

func _expected_neutral_owner_ids() -> Array[String]:
    var ids := _source_owner_ids()
    if ids.size() != EXPECTED_SOURCE_OWNER_COUNT:
        return []
    var neutral: Array[String] = []
    for owner_id: String in ids:
        if owner_id not in DEDICATED_OWNER_IDS:
            neutral.append(owner_id)
    neutral.sort()
    return neutral

func _owner_center(path: String) -> Vector3:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        return Vector3.INF
    var initialized := false
    var lo := Vector3.ZERO
    var hi := Vector3.ZERO
    for raw_face: Variant in parsed.get("faces", []):
        if typeof(raw_face) != TYPE_DICTIONARY:
            continue
        for raw_triangle: Variant in raw_face.get("triangles", []):
            if typeof(raw_triangle) != TYPE_ARRAY:
                continue
            for raw_point: Variant in raw_triangle:
                if typeof(raw_point) != TYPE_ARRAY or raw_point.size() != 3:
                    continue
                var point := Vector3(float(raw_point[0]), float(raw_point[1]), float(raw_point[2]))
                if not point.is_finite():
                    continue
                if not initialized:
                    lo = point
                    hi = point
                    initialized = true
                else:
                    lo.x = minf(lo.x, point.x)
                    lo.y = minf(lo.y, point.y)
                    lo.z = minf(lo.z, point.z)
                    hi.x = maxf(hi.x, point.x)
                    hi.y = maxf(hi.y, point.y)
                    hi.z = maxf(hi.z, point.z)
    return Vector3((lo.x + hi.x) * 0.5, lo.y + (hi.y - lo.y) * 0.46, (lo.z + hi.z) * 0.5) if initialized else Vector3.INF

func _north_east_target() -> Vector3:
    var dir := DirAccess.open(SOURCE_DIR)
    if dir == null:
        return Vector3.INF
    var centers: Array[Vector3] = []
    for file_name: String in dir.get_files():
        if file_name.ends_with(".game.json"):
            var center := _owner_center(SOURCE_DIR.path_join(file_name))
            if not center.is_finite():
                return Vector3.INF
            centers.append(center)
    if centers.size() != EXPECTED_SOURCE_OWNER_COUNT:
        return Vector3.INF
    var min_x := INF
    var max_x := -INF
    var min_z := INF
    var max_z := -INF
    for center: Vector3 in centers:
        min_x = minf(min_x, center.x)
        max_x = maxf(max_x, center.x)
        min_z = minf(min_z, center.z)
        max_z = maxf(max_z, center.z)
    var mid_x := (min_x + max_x) * 0.5
    var mid_z := (min_z + max_z) * 0.5
    var bucket: Array[Vector3] = []
    for center: Vector3 in centers:
        if center.z <= mid_z and center.x > mid_x:
            bucket.append(center)
    if bucket.is_empty():
        return Vector3.INF
    var sum := Vector3.ZERO
    for center: Vector3 in bucket:
        sum += center
    return sum / float(bucket.size())

func _capture(main: Node, camera: Camera3D, target: Vector3, path: String) -> bool:
    camera.look_at(target, Vector3.UP)
    for _frame: int in range(5):
        _freeze_world(main)
        if root.get_viewport().get_camera_3d() != camera or not camera.current:
            return false
        if camera.global_position.distance_to(CAMERA_POSITION) > 0.001 or absf(camera.fov - CAMERA_FOV) > 0.001:
            return false
        RenderingServer.force_draw()
        await process_frame
    var image := root.get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        return false
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        image.resize(WIDTH, HEIGHT, Image.INTERPOLATE_LANCZOS)
    return image.save_png(path) == OK

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 1:
        _fail("usage: <output_dir>")
        return
    var output_dir := str(args[0])
    DirAccess.make_dir_recursive_absolute(output_dir)
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    var contour := root.get_node_or_null("GrandPlaceOfficialLod2Contour")
    for _frame: int in range(180):
        if contour != null and bool(contour.get("geometry_loaded")):
            break
        await process_frame
        contour = root.get_node_or_null("GrandPlaceOfficialLod2Contour")
    if contour == null or not bool(contour.get("geometry_loaded")):
        _fail("official contour did not settle")
        return
    if int(contour.get("loaded_owner_count")) != EXPECTED_CONTOUR_OWNER_COUNT:
        _fail("23-owner contour count drifted")
        return
    if bool(contour.get_meta("visual_acceptance", true)) or bool(contour.get_meta("jouable_authorized", true)):
        _fail("promotion rail opened")
        return
    var expected_neutral_ids := _expected_neutral_owner_ids()
    if expected_neutral_ids.size() != EXPECTED_CONTOUR_OWNER_COUNT:
        _fail("source-backed neutral owner set drifted")
        return
    var owners: Array[Node3D] = []
    for child: Node in contour.get_children():
        if child is Node3D and child.name.begins_with("GrandPlaceOfficial_"):
            owners.append(child as Node3D)
    owners.sort_custom(func(a: Node3D, b: Node3D) -> bool: return str(a.name) < str(b.name))
    if owners.size() != EXPECTED_CONTOUR_OWNER_COUNT:
        _fail("runtime owner-node count drifted: %d" % owners.size())
        return
    var runtime_owner_ids: Array[String] = []
    for owner_root: Node3D in owners:
        runtime_owner_ids.append(str(owner_root.name).trim_prefix("GrandPlaceOfficial_"))
    runtime_owner_ids.sort()
    if runtime_owner_ids != expected_neutral_ids:
        _fail("runtime neutral owner identity set does not exactly match source minus dedicated owners")
        return
    var target := _north_east_target()
    if not target.is_finite():
        _fail("could not derive north-east target from exact source set")
        return
    _freeze_world(main)
    var previous_camera := root.get_viewport().get_camera_3d()
    if previous_camera != null:
        previous_camera.current = false
    var camera := Camera3D.new()
    camera.name = "GrandPlaceNorthEastOwnerAttributionWitness"
    camera.position = CAMERA_POSITION
    camera.fov = CAMERA_FOV
    main.add_child(camera)
    camera.current = true
    if not await _capture(main, camera, target, output_dir.path_join("baseline.png")):
        _fail("baseline capture failed")
        return
    var owner_ids: Array[String] = []
    for owner_root: Node3D in owners:
        var owner_id := str(owner_root.name).trim_prefix("GrandPlaceOfficial_")
        if owner_id in DEDICATED_OWNER_IDS:
            _fail("dedicated owner leaked into neutral contour: %s" % owner_id)
            return
        if not owner_root.visible:
            _fail("neutral owner unexpectedly invisible before attribution: %s" % owner_id)
            return
        owner_ids.append(owner_id)
        owner_root.visible = false
        if not await _capture(main, camera, target, output_dir.path_join("without_%s.png" % owner_id)):
            owner_root.visible = true
            _fail("owner exclusion capture failed: %s" % owner_id)
            return
        owner_root.visible = true
    owner_ids.sort()
    if owner_ids != expected_neutral_ids:
        _fail("captured owner identity set drifted from exact source-backed neutral set")
        return
    var manifest := {
        "schema": "grand-place-north-east-owner-attribution-witness-v2",
        "camera": [CAMERA_POSITION.x, CAMERA_POSITION.y, CAMERA_POSITION.z],
        "fov": CAMERA_FOV,
        "resolution": [WIDTH, HEIGHT],
        "target": [target.x, target.y, target.z],
        "source_owner_count": EXPECTED_SOURCE_OWNER_COUNT,
        "contour_owner_count": EXPECTED_CONTOUR_OWNER_COUNT,
        "dedicated_owner_ids": DEDICATED_OWNER_IDS,
        "owner_ids": owner_ids,
        "source_owner_set_exact": true,
        "dynamic_state_frozen": true,
        "visual_acceptance": false,
        "jouable_authorized": false,
        "human_full_frame_review_required": true
    }
    var file := FileAccess.open(output_dir.path_join("capture_manifest.json"), FileAccess.WRITE)
    if file == null:
        _fail("could not write capture manifest")
        return
    file.store_string(JSON.stringify(manifest, "  "))
    file.close()
    print("GRAND_PLACE_NORTH_EAST_OWNER_ATTRIBUTION_OK owners=23 captures=24 source_owner_set_exact=true camera_locked=true fov=62 source_target=true visual_acceptance=false jouable_authorized=false")
    quit(0)
