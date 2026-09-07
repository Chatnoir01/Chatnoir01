extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const SOURCE_DIR := "res://data/urbis/grand_place_lod2"
const WIDTH := 1280
const HEIGHT := 720
const CAMERA_POSITION := Vector3(319.01, 1.72, -535.20)
const CANONICAL_TARGET := Vector3(321.91, 11.8, -485.66)
const CAMERA_FOV := 62.0
const EXPECTED_SOURCE_OWNER_COUNT := 25
const EXPECTED_CONTOUR_OWNER_COUNT := 23

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_OFFICIAL_FULL_SQUARE_MULTIVIEW_FAIL: %s" % message)
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

func _owner_center(path: String) -> Vector3:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        return Vector3.INF
    var data: Dictionary = parsed
    var initialized := false
    var lo := Vector3.ZERO
    var hi := Vector3.ZERO
    for raw_face: Variant in data.get("faces", []):
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
    if not initialized:
        return Vector3.INF
    return Vector3((lo.x + hi.x) * 0.5, lo.y + (hi.y - lo.y) * 0.46, (lo.z + hi.z) * 0.5)

func _source_quadrant_targets() -> Dictionary:
    var dir := DirAccess.open(SOURCE_DIR)
    if dir == null:
        return {}
    var centers: Array[Vector3] = []
    for file_name: String in dir.get_files():
        if not file_name.ends_with(".game.json"):
            continue
        var center := _owner_center(SOURCE_DIR.path_join(file_name))
        if not center.is_finite():
            return {}
        centers.append(center)
    if centers.size() != EXPECTED_SOURCE_OWNER_COUNT:
        return {}
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
    var buckets := {"north_west": [], "north_east": [], "south_west": [], "south_east": []}
    for center: Vector3 in centers:
        var north := center.z <= mid_z
        var west := center.x <= mid_x
        var key := "north_west" if north and west else "north_east" if north else "south_west" if west else "south_east"
        buckets[key].append(center)
    var targets := {}
    for key: String in buckets.keys():
        var bucket: Array = buckets[key]
        if bucket.is_empty():
            return {}
        var sum := Vector3.ZERO
        for center: Vector3 in bucket:
            sum += center
        targets[key] = sum / float(bucket.size())
    return targets

func _capture(main: Node, camera: Camera3D, target: Vector3, path: String) -> bool:
    camera.look_at(target, Vector3.UP)
    for _frame: int in range(8):
        _freeze_world(main)
        if root.get_viewport().get_camera_3d() != camera or not camera.current:
            return false
        if camera.global_position.distance_to(CAMERA_POSITION) > 0.001 or absf(camera.fov - CAMERA_FOV) > 0.001:
            return false
        RenderingServer.force_draw()
        await process_frame
    var texture := root.get_viewport().get_texture()
    if texture == null:
        return false
    var image := texture.get_image()
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
    if bool(contour.get_meta("runtime_approved", true)) or bool(contour.get_meta("visual_acceptance", true)) or bool(contour.get_meta("jouable_authorized", true)):
        _fail("promotion rail opened")
        return

    var targets := _source_quadrant_targets()
    if targets.size() != 4:
        _fail("could not derive four non-empty source quadrants from 25 official owners")
        return

    _freeze_world(main)
    var previous_camera := root.get_viewport().get_camera_3d()
    if previous_camera != null:
        previous_camera.current = false
    var camera := Camera3D.new()
    camera.name = "GrandPlaceOfficialFullSquareFrozenPlayerWitness"
    camera.position = CAMERA_POSITION
    camera.fov = CAMERA_FOV
    main.add_child(camera)
    camera.current = true

    var views := {"canonical": CANONICAL_TARGET}
    for key: String in ["north_west", "north_east", "south_west", "south_east"]:
        views[key] = targets[key]
    for view_id: String in views.keys():
        var target: Vector3 = views[view_id]
        var path := output_dir.path_join("%s.png" % view_id)
        if not await _capture(main, camera, target, path):
            _fail("capture failed or frozen camera drifted: %s" % view_id)
            return
        print("GRAND_PLACE_OFFICIAL_MULTIVIEW_VIEW id=%s target=[%.3f,%.3f,%.3f]" % [view_id, target.x, target.y, target.z])

    print("GRAND_PLACE_OFFICIAL_FULL_SQUARE_MULTIVIEW_OK views=5 source_owners=25 contour_owners=23 camera_position_locked=true fov=62 source_quadrants=true human_full_frame_review_required=true visual_acceptance=false jouable_authorized=false")
    quit(0)
