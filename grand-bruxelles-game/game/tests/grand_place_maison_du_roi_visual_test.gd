extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const OUTPUT_DIR := "res://artifacts/grand-place/maison-du-roi-1654360"
const WIDTH := 1280
const HEIGHT := 720
const CAMERA_POSITION := Vector3(365.0, 1.72, -505.0)
const CAMERA_TARGET := Vector3(279.5, 38.0, -515.0)
const CAMERA_FOV := 64.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_MAISON_DU_ROI_VISUAL_FAIL: %s" % message)
    quit(1)

func _hide_and_freeze_dynamic_state(main: Node) -> void:
    for name_value: String in ["LocationLabel", "MissionLabel", "SaveStatusLabel", "WalletLabel", "MiniMap", "MobileControls", "PrototypeLabel"]:
        var node := main.get_node_or_null(name_value)
        if node is CanvasItem:
            (node as CanvasItem).visible = false
    for path: String in ["Player", "PrototypeCar", "TrafficManager", "MidiUrbanLife"]:
        var node := main.get_node_or_null(path)
        if node != null:
            node.process_mode = Node.PROCESS_MODE_DISABLED
        if node is Node3D:
            (node as Node3D).visible = false
    var showcase := root.get_node_or_null("LivingCityShowcaseRuntime")
    if showcase != null:
        showcase.process_mode = Node.PROCESS_MODE_DISABLED
    var visible_runtime := root.get_node_or_null("VisibleCityRuntime")
    if visible_runtime != null:
        visible_runtime.process_mode = Node.PROCESS_MODE_DISABLED
        if visible_runtime.has_method("_set_status"):
            visible_runtime.call("_set_status", "")

func _capture(path: String) -> bool:
    for _frame: int in range(5):
        RenderingServer.force_draw()
        await process_frame
    var image := root.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        return false
    var absolute := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    return image.save_png(absolute) == OK

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    for _frame: int in range(24):
        await process_frame

    var town_hall := root.get_node_or_null("GrandPlaceOfficialLod2")
    var ensemble := root.get_node_or_null("GrandPlaceOfficialLod2Next")
    var candidate := root.get_node_or_null("GrandPlaceMaisonDuRoiOfficialLod2")
    if town_hall == null or ensemble == null or candidate == null:
        _fail("Grand-Place official LoD2 ensemble autoload missing")
        return
    if not bool(town_hall.get("geometry_loaded")) or not bool(ensemble.get("geometry_loaded")):
        _fail("shipped Grand-Place architecture must remain loaded")
        return
    if not bool(candidate.get("geometry_loaded")):
        _fail("Maison du Roi official geometry did not load")
        return
    if int(candidate.get("render_triangle_count")) != 213:
        _fail("Maison du Roi render triangle contract drifted")
        return
    if bool(candidate.get_meta("geometry_rescaled", true)):
        _fail("Maison du Roi LoD2 must remain unscaled")
        return

    _hide_and_freeze_dynamic_state(main)
    var player_camera := main.get_node_or_null("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if player_camera != null:
        player_camera.current = false
    var car_camera := main.get_node_or_null("PrototypeCar/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if car_camera != null:
        car_camera.current = false

    var camera := Camera3D.new()
    camera.name = "GrandPlaceMaisonDuRoiWitness"
    camera.position = CAMERA_POSITION
    camera.fov = CAMERA_FOV
    main.add_child(camera)
    camera.look_at(CAMERA_TARGET, Vector3.UP)
    camera.current = true
    for _frame: int in range(3):
        await process_frame

    # Preserve all shipped Grand-Place truth in both frames. Toggle only 1654360.
    town_hall.call("set_official_visible", true)
    ensemble.call("set_official_visible", true)
    candidate.call("set_official_visible", false)
    if not await _capture(OUTPUT_DIR + "/before.png"):
        _fail("before capture failed")
        return

    candidate.call("set_official_visible", true)
    if not await _capture(OUTPUT_DIR + "/after.png"):
        _fail("after capture failed")
        return

    print("GRAND_PLACE_MAISON_DU_ROI_VISUAL_OK: building=1654360 triangles=%d masked_osm=%d camera=(%.1f,%.2f,%.1f) fov=%.1f before=%s after=%s" % [
        int(candidate.get("render_triangle_count")), int(candidate.get("masked_osm_count")),
        CAMERA_POSITION.x, CAMERA_POSITION.y, CAMERA_POSITION.z, CAMERA_FOV,
        OUTPUT_DIR + "/before.png", OUTPUT_DIR + "/after.png"
    ])
    quit(0)
