extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const AUTOLOAD_NAME := "GrandPlaceMaisonDuRoiOfficialLod2"
const ZONE_CATALOG_PATH := "res://data/qa/playable_zone_catalog.json"
const WIDTH := 1280
const HEIGHT := 720
const PLAYER_EYE_HEIGHT := 1.72
const CAMERA_FOV := 64.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_MAISON_DU_ROI_AB_FAIL: %s" % message)
    quit(1)

func _grand_place_player_eye() -> Vector3:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ZONE_CATALOG_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        return Vector3.INF
    for raw_zone: Variant in (parsed as Dictionary).get("zones", []):
        if typeof(raw_zone) != TYPE_DICTIONARY:
            continue
        var zone: Dictionary = raw_zone
        if str(zone.get("id", "")) != "grand_place":
            continue
        var spawn: Array = zone.get("spawn", [])
        if spawn.size() != 3:
            return Vector3.INF
        return Vector3(float(spawn[0]), PLAYER_EYE_HEIGHT, float(spawn[2]))
    return Vector3.INF

func _hide_dynamic(main: Node) -> void:
    for name_value: String in ["LocationLabel", "MissionLabel", "SaveStatusLabel", "WalletLabel", "MiniMap", "MobileControls", "PrototypeLabel"]:
        var ui := main.get_node_or_null(name_value)
        if ui is CanvasItem:
            (ui as CanvasItem).visible = false
    for path: String in ["Player", "PrototypeCar", "PhysicalCar", "TrafficManager", "NpcPopulationDirector", "NpcRuntimeIntegration", "MidiUrbanLife"]:
        var node := main.get_node_or_null(path)
        if node == null:
            continue
        node.process_mode = Node.PROCESS_MODE_DISABLED
        if node is Node3D:
            (node as Node3D).visible = false
    for group_name: String in ["vehicle", "npc"]:
        for node: Node in get_nodes_in_group(group_name):
            node.process_mode = Node.PROCESS_MODE_DISABLED
            if node is Node3D:
                (node as Node3D).visible = false
    for autoload_name: String in ["LivingCityShowcaseRuntime", "VisibleCityRuntime", "MidiAmbientNpcVisualRuntime", "MidiProfiledNpcGaitRuntime"]:
        var runtime := root.get_node_or_null(autoload_name)
        if runtime != null:
            runtime.process_mode = Node.PROCESS_MODE_DISABLED
            if runtime is Node3D:
                (runtime as Node3D).visible = false

func _capture(path: String) -> Image:
    for _frame: int in range(5):
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

func _run() -> void:
    var official := get_root().get_node_or_null(AUTOLOAD_NAME)
    if official == null:
        _fail("Maison du Roi autoload missing")
        return

    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    for _frame: int in range(480):
        await process_frame
        if bool(official.get("geometry_loaded")):
            break
    if not bool(official.get("geometry_loaded")):
        _fail("official geometry did not become ready")
        return

    var town_hall := get_root().get_node_or_null("GrandPlaceOfficialLod2")
    var ensemble := get_root().get_node_or_null("GrandPlaceOfficialLod2Next")
    if town_hall == null or ensemble == null or not bool(town_hall.get("geometry_loaded")) or not bool(ensemble.get("geometry_loaded")):
        _fail("shipped Grand-Place official architecture missing")
        return
    town_hall.call("set_official_visible", true)
    ensemble.call("set_official_visible", true)

    var camera_position := _grand_place_player_eye()
    var bounds: Rect2 = official.get("source_bounds")
    if not camera_position.is_finite() or bounds.size.length_squared() <= 0.001:
        _fail("Grand-Place spawn or official source bounds missing")
        return
    var center := bounds.get_center()
    var lod2_height := float(official.get_meta("lod2_height_m", 0.0))
    var camera_target := Vector3(center.x, lod2_height * 0.5, center.y)

    _hide_dynamic(main)
    var existing_camera := main.get_viewport().get_camera_3d()
    if existing_camera != null:
        existing_camera.current = false
    var camera := Camera3D.new()
    camera.name = "MaisonDuRoiGrandPlaceSpawnWitness"
    camera.position = camera_position
    camera.fov = CAMERA_FOV
    main.add_child(camera)
    camera.look_at(camera_target, Vector3.UP)
    camera.current = true

    for _frame: int in range(12):
        await process_frame

    official.call("set_official_visible", false)
    for _frame: int in range(6):
        await process_frame
    var before := await _capture("/tmp/grand-place-maison-du-roi-before.png")
    if before == null:
        _fail("before capture failed")
        return

    official.call("set_official_visible", true)
    for _frame: int in range(6):
        await process_frame
    var after := await _capture("/tmp/grand-place-maison-du-roi-after.png")
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
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var d := maxf(absf(a.r-b.r), maxf(absf(a.g-b.g), absf(a.b-b.b))) * 255.0
            if d > 3.0:
                changed3 += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
            if d > 8.0:
                changed8 += 1
    var total := WIDTH * HEIGHT
    var p3 := 100.0 * float(changed3) / float(total)
    var p8 := 100.0 * float(changed8) / float(total)
    if p3 < 2.0 or p8 < 0.8:
        _fail("anti-micro gate failed: changed3=%.4f%% changed8=%.4f%%" % [p3, p8])
        return
    print("GRAND_PLACE_MAISON_DU_ROI_AB_OK: changed3=%d %.4f%% changed8=%d %.4f%% bbox=%d,%d..%d,%d camera=(%.2f,%.2f,%.2f) target=(%.2f,%.2f,%.2f) fov=%.1f dynamics_masked=true zone_spawn_witness=true" % [changed3,p3,changed8,p8,min_x,min_y,max_x,max_y,camera_position.x,camera_position.y,camera_position.z,camera_target.x,camera_target.y,camera_target.z,CAMERA_FOV])
    quit(0)
