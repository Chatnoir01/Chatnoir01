extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const CAMERA_CONTRACT := "res://data/qa/grand_place_clean_player_witness.json"
const OFFICIAL_NAME := "GrandPlaceMaisonDuRoiOfficialLod2"
const ARTICULATION_NAME := "GrandPlaceMaisonDuRoiFacadeArticulationRuntime"
const WIDTH := 1280
const HEIGHT := 720
const FOV := 62.0
const MIN_GT3_PERCENT := 8.0
const MIN_GT8_PERCENT := 4.0
const MIN_BBOX_W := 500
const MIN_BBOX_H := 350

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MAISON_DU_ROI_FACADE_AB_FAIL: " + message)
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
    for autoload_name: String in ["LivingCityShowcaseRuntime", "VisibleCityRuntime", "MidiAmbientNpcVisualRuntime", "MidiProfiledNpcGaitRuntime"]:
        var runtime := root.get_node_or_null(autoload_name)
        if runtime != null:
            runtime.process_mode = Node.PROCESS_MODE_DISABLED
            if runtime is Node3D:
                (runtime as Node3D).visible = false

func _capture(path: String, main: Node) -> Image:
    for _frame: int in range(8):
        _freeze_world(main)
        RenderingServer.force_draw()
        await process_frame
    var image := root.get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        return null
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        image.resize(WIDTH, HEIGHT, Image.INTERPOLATE_LANCZOS)
    if image.save_png(path) != OK:
        return null
    return image

func _write_metrics(payload: Dictionary) -> void:
    DirAccess.make_dir_recursive_absolute("/tmp")
    var file := FileAccess.open("/tmp/grand-place-maison-du-roi-facade-metrics.json", FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify(payload, "  "))

func _run() -> void:
    var camera_contract := _json(CAMERA_CONTRACT)
    var camera_position := _v3(camera_contract.get("camera_position", []))
    if not camera_position.is_finite() or absf(float(camera_contract.get("camera_fov_deg", 0.0)) - FOV) > 0.001:
        _fail("canonical player position/FOV contract drifted")
        return
    var official := root.get_node_or_null(OFFICIAL_NAME)
    var articulation := root.get_node_or_null(ARTICULATION_NAME)
    if official == null or articulation == null:
        _fail("Maison du Roi autoloads missing")
        return
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    for _frame: int in range(600):
        if bool(official.get("geometry_loaded")) and bool(articulation.get("built")):
            break
        await process_frame
    if not bool(official.get("geometry_loaded")) or not bool(articulation.get("built")):
        _fail("candidate runtimes did not become ready")
        return
    var town_hall := root.get_node_or_null("GrandPlaceOfficialLod2")
    var ensemble := root.get_node_or_null("GrandPlaceOfficialLod2Next")
    if town_hall == null or ensemble == null or not bool(town_hall.get("geometry_loaded")) or not bool(ensemble.get("geometry_loaded")):
        _fail("shipped Grand-Place architecture missing")
        return
    town_hall.call("set_official_visible", true)
    ensemble.call("set_official_visible", true)
    var bounds: Rect2 = official.get("source_bounds")
    if bounds.size.length_squared() <= 0.001:
        _fail("official Maison du Roi source bounds missing")
        return
    var center := bounds.get_center()
    var camera_target := Vector3(center.x, 15.0, center.y)
    _freeze_world(main)
    var current_camera := main.get_viewport().get_camera_3d()
    if current_camera != null:
        current_camera.current = false
    var camera := Camera3D.new()
    camera.name = "MaisonDuRoiFixedPlayerTurnWitness"
    camera.position = camera_position
    camera.fov = FOV
    main.add_child(camera)
    camera.look_at(camera_target, Vector3.UP)
    camera.current = true
    for _frame: int in range(12):
        _freeze_world(main)
        await process_frame

    articulation.call("set_articulation_visible", false)
    official.call("set_official_visible", false)
    var before := await _capture("/tmp/grand-place-maison-du-roi-facade-before.png", main)
    if before == null:
        _fail("before capture failed")
        return

    official.call("set_official_visible", true)
    articulation.call("set_articulation_visible", true)
    var after := await _capture("/tmp/grand-place-maison-du-roi-facade-after.png", main)
    if after == null:
        _fail("after capture failed")
        return

    var changed3 := 0
    var changed8 := 0
    var min_x := WIDTH
    var min_y := HEIGHT
    var max_x := -1
    var max_y := -1
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a: Color = before.get_pixel(x, y)
            var b: Color = after.get_pixel(x, y)
            var delta: float = maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) * 255.0
            if delta > 3.0:
                changed3 += 1
            if delta > 8.0:
                changed8 += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
    var total := WIDTH * HEIGHT
    var p3 := 100.0 * float(changed3) / float(total)
    var p8 := 100.0 * float(changed8) / float(total)
    var bbox_w := max_x - min_x + 1 if max_x >= min_x else 0
    var bbox_h := max_y - min_y + 1 if max_y >= min_y else 0
    var metrics := {
        "changed_gt3_pixels": changed3,
        "changed_gt3_percent": p3,
        "changed_gt8_pixels": changed8,
        "changed_gt8_percent": p8,
        "bbox_gt8": [min_x, min_y, max_x, max_y],
        "bbox_gt8_width": bbox_w,
        "bbox_gt8_height": bbox_h,
        "camera_position": [camera_position.x, camera_position.y, camera_position.z],
        "camera_target": [camera_target.x, camera_target.y, camera_target.z],
        "fov": FOV,
        "dynamics_masked": true,
        "ui_masked": true,
        "view_kind": "fixed_player_turn_from_canonical_position"
    }
    _write_metrics(metrics)
    if p3 < MIN_GT3_PERCENT or p8 < MIN_GT8_PERCENT or bbox_w < MIN_BBOX_W or bbox_h < MIN_BBOX_H:
        _fail("frozen visual gate failed: >3=%.4f%% >8=%.4f%% bbox=%dx%d" % [p3, p8, bbox_w, bbox_h])
        return
    print("MAISON_DU_ROI_FACADE_AB_OK: >3=%.4f%% >8=%.4f%% bbox=%dx%d camera_fixed=true dynamics_masked=true ui_masked=true" % [p3, p8, bbox_w, bbox_h])
    quit(0)
