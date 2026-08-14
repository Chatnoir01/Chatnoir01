extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const OUTPUT_DIR := "res://artifacts/midi/official-forecourt"
const WIDTH := 1280
const HEIGHT := 720
const CAMERA_POSITION := Vector3(-659.0, 5.2, 638.5)
const CAMERA_TARGET := Vector3(-681.8, 0.35, 619.7)
const CAMERA_FOV := 64.0
const EXPECTED_AUTHORED_SIZE := Vector3(18.0, 0.10, 174.0)

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_OFFICIAL_FORECOURT_FAIL: %s" % message)
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
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    for _frame: int in range(20):
        await process_frame

    var mask := root.get_node_or_null("MidiOfficialForecourtMask")
    if mask == null:
        _fail("MidiOfficialForecourtMask autoload missing")
        return
    var forecourt := main.find_child("FonsnyStationForecourt", true, false) as MeshInstance3D
    if forecourt == null:
        _fail("legacy Fonsny forecourt witness node missing")
        return
    if not (forecourt.mesh is BoxMesh):
        _fail("legacy forecourt is no longer a BoxMesh; source-truth contract needs review")
        return
    var box := forecourt.mesh as BoxMesh
    if not box.size.is_equal_approx(EXPECTED_AUTHORED_SIZE):
        _fail("legacy authored forecourt dimensions drifted: %s" % [box.size])
        return
    var official_surfaces := main.get_node_or_null("UrbISMidiExact/UrbISStreetSurfaces")
    if official_surfaces == null or official_surfaces.get_child_count() < 1:
        _fail("authoritative UrbIS StreetSurface runtime is not mounted")
        return
    if not bool(mask.call("is_mask_applied")):
        _fail("production source-truth mask was not applied")
        return

    _hide_noise(main)
    var player_camera := main.get_node_or_null("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if player_camera != null:
        player_camera.current = false
    var car_camera := main.get_node_or_null("PrototypeCar/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if car_camera != null:
        car_camera.current = false

    var camera := Camera3D.new()
    camera.name = "MidiOfficialForecourtWitness"
    camera.position = CAMERA_POSITION
    camera.fov = CAMERA_FOV
    main.add_child(camera)
    camera.look_at(CAMERA_TARGET, Vector3.UP)
    camera.current = true
    for _frame: int in range(3):
        await process_frame

    if not bool(mask.call("set_legacy_forecourt_visible", true)):
        _fail("could not restore legacy forecourt for baseline")
        return
    if not await _capture(OUTPUT_DIR + "/before.png"):
        _fail("before capture failed")
        return

    if not bool(mask.call("set_legacy_forecourt_visible", false)):
        _fail("could not apply official forecourt view")
        return
    if not await _capture(OUTPUT_DIR + "/after.png"):
        _fail("after capture failed")
        return

    print("MIDI_OFFICIAL_FORECOURT_OK: authored_size=(%.1f,%.2f,%.1f) authored_area=3132.0 official_surface_batches=%d camera=(%.1f,%.1f,%.1f) before=%s after=%s" % [
        box.size.x, box.size.y, box.size.z, official_surfaces.get_child_count(),
        CAMERA_POSITION.x, CAMERA_POSITION.y, CAMERA_POSITION.z,
        OUTPUT_DIR + "/before.png", OUTPUT_DIR + "/after.png"
    ])
    quit(0)
