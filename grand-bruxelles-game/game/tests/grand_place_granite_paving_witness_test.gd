extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const OUTPUT_DIR := "res://artifacts/grand-place/granite-paving"
const WIDTH := 1280
const HEIGHT := 720
const CAMERA_POSITION := Vector3(330.0, 1.72, -550.0)
const CAMERA_TARGET := Vector3(310.0, 8.0, -485.0)
const CAMERA_FOV := 64.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_GRANITE_PAVING_WITNESS_FAIL: %s" % message)
    quit(1)

func _hide_noise(main: Node) -> void:
    for name_value: String in ["LocationLabel", "MissionLabel", "SaveStatusLabel", "WalletLabel", "MiniMap", "MobileControls", "PrototypeLabel"]:
        var node := main.get_node_or_null(name_value)
        if node is CanvasItem:
            (node as CanvasItem).visible = false
    for path: String in ["Player", "PrototypeCar", "TrafficManager", "MidiUrbanLife"]:
        var node := main.get_node_or_null(path)
        if node is Node3D:
            (node as Node3D).visible = false

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
    var paving := root.get_node_or_null("GrandPlaceGranitePaving")
    if paving == null or not paving.has_method("set_presentation_enabled"):
        _fail("granite paving production autoload missing")
        return
    if not bool(paving.call("geometry_loaded")):
        _fail("official paving geometry not loaded")
        return

    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    for _frame: int in range(16):
        await process_frame
    _hide_noise(main)

    var town_hall := root.get_node_or_null("GrandPlaceOfficialLod2")
    var ensemble := root.get_node_or_null("GrandPlaceOfficialLod2Next")
    if town_hall == null or ensemble == null:
        _fail("Grand-Place production ensemble missing")
        return
    town_hall.call("set_official_visible", true)
    ensemble.call("set_official_visible", true)

    var player_camera := main.get_node_or_null("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if player_camera != null:
        player_camera.current = false
    var car_camera := main.get_node_or_null("PrototypeCar/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if car_camera != null:
        car_camera.current = false

    var camera := Camera3D.new()
    camera.name = "GrandPlaceGranitePavingWitness"
    camera.position = CAMERA_POSITION
    camera.fov = CAMERA_FOV
    main.add_child(camera)
    camera.look_at(CAMERA_TARGET, Vector3.UP)
    camera.current = true
    for _frame: int in range(3):
        await process_frame

    paving.call("set_presentation_enabled", false)
    if not await _capture(OUTPUT_DIR + "/before.png"):
        _fail("before capture failed")
        return

    paving.call("set_presentation_enabled", true)
    if not await _capture(OUTPUT_DIR + "/after.png"):
        _fail("after capture failed")
        return

    print("GRAND_PLACE_GRANITE_PAVING_WITNESS_OK: feature=%s camera=(%.1f,%.2f,%.1f) before=%s after=%s" % [
        paving.call("source_feature_id"), CAMERA_POSITION.x, CAMERA_POSITION.y, CAMERA_POSITION.z,
        OUTPUT_DIR + "/before.png", OUTPUT_DIR + "/after.png"
    ])
    quit(0)
