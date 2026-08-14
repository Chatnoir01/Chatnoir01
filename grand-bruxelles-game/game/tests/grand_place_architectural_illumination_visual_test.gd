extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const OUTPUT_DIR := "res://artifacts/grand-place/architectural-illumination"
const WIDTH := 1280
const HEIGHT := 720
const CAMERA_POSITION := Vector3(365.0, 1.72, -505.0)
const CAMERA_TARGET := Vector3(279.5, 38.0, -515.0)
const CAMERA_FOV := 64.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_ARCHITECTURAL_ILLUMINATION_FAIL: %s" % message)
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
    for _frame: int in range(6):
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
    for _frame: int in range(20):
        await process_frame

    var lighting := root.get_node_or_null("GrandPlaceArchitecturalIllumination")
    if lighting == null:
        _fail("architectural illumination autoload missing")
        return
    if not lighting.has_method("set_presentation_enabled") or not lighting.has_method("presentation_enabled"):
        _fail("architectural illumination deterministic toggle missing")
        return
    if int(lighting.get("wash_light_count")) < 4:
        _fail("architectural wash did not install enough facade lights")
        return
    if str(lighting.get_meta("source_provider", "")) != "Beliris":
        _fail("source provenance metadata missing")
        return
    if bool(lighting.get_meta("fixture_positions_measured", true)):
        _fail("authored fixture placement must not be claimed as measured")
        return

    var town_hall := root.get_node_or_null("GrandPlaceOfficialLod2")
    var ensemble := root.get_node_or_null("GrandPlaceOfficialLod2Next")
    if town_hall == null or ensemble == null:
        _fail("official Grand-Place production masses missing")
        return

    _hide_noise(main)
    var player_camera := main.get_node_or_null("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if player_camera != null:
        player_camera.current = false
    var car_camera := main.get_node_or_null("PrototypeCar/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if car_camera != null:
        car_camera.current = false

    var camera := Camera3D.new()
    camera.name = "GrandPlaceArchitecturalIlluminationWitness"
    camera.position = CAMERA_POSITION
    camera.fov = CAMERA_FOV
    main.add_child(camera)
    camera.look_at(CAMERA_TARGET, Vector3.UP)
    camera.current = true
    for _frame: int in range(3):
        await process_frame

    lighting.call("set_presentation_enabled", false)
    if bool(lighting.call("presentation_enabled")):
        _fail("baseline lighting toggle failed")
        return
    if not await _capture(OUTPUT_DIR + "/before.png"):
        _fail("before capture failed")
        return

    lighting.call("set_presentation_enabled", true)
    if not bool(lighting.call("presentation_enabled")):
        _fail("illumination toggle failed")
        return
    if not await _capture(OUTPUT_DIR + "/after.png"):
        _fail("after capture failed")
        return

    print("GRAND_PLACE_ARCHITECTURAL_ILLUMINATION_OK: lights=%d before=%s after=%s" % [
        int(lighting.get("wash_light_count")), OUTPUT_DIR + "/before.png", OUTPUT_DIR + "/after.png"
    ])
    quit(0)
