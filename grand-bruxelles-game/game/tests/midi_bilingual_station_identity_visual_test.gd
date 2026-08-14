extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const SOURCE_PATH := "res://data/visual/midi_station_identity.json"
const OUTPUT_DIR := "res://artifacts/midi/bilingual-station-identity"
const WIDTH := 1280
const HEIGHT := 720
const CAMERA_POSITION := Vector3(-650.4785, 1.70, 633.3595)
const CAMERA_TARGET := Vector3(-672.2905, 2.70, 615.8035)
const CAMERA_FOV := 61.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_BILINGUAL_STATION_IDENTITY_FAIL: %s" % message)
    quit(1)

func _read_source() -> Dictionary:
    if not FileAccess.file_exists(SOURCE_PATH):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
    return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}

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
    var source := _read_source()
    if source.is_empty():
        _fail("station identity source missing")
        return
    var facts: Dictionary = source.get("source", {}).get("facts", {})
    var contract: Dictionary = source.get("presentation_contract", {})
    if str(facts.get("official_french_name", "")) != "Bruxelles-Midi" or str(facts.get("official_dutch_name", "")) != "Brussel-Zuid":
        _fail("official bilingual naming drifted")
        return
    if str(facts.get("fonsny_address", "")) != "Avenue Fonsny 47 / Fonsnylaan 47":
        _fail("Fonsny source anchor drifted")
        return
    if bool(contract.get("new_landmark_geometry", true)) or bool(contract.get("new_openings", true)) or bool(contract.get("new_measured_dimensions", true)):
        _fail("source/presentation boundary drifted")
        return
    if bool(contract.get("new_material_identity_claim", true)):
        _fail("identity lot must not claim a new measured station-sign material")
        return

    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    for _frame: int in range(16):
        await process_frame

    var hero := main.get_node_or_null("MidiHeroZone")
    if hero == null:
        _fail("MidiHeroZone missing")
        return
    var entrance := hero.get_node_or_null("MidiMainEntranceFonsny")
    if entrance == null:
        _fail("existing Fonsny entrance missing")
        return
    var identity := root.get_node_or_null("MidiStationIdentity")
    if identity == null or not bool(identity.call("station_identity_attached")):
        _fail("station identity autoload did not attach")
        return
    if entrance.get_node_or_null("StationNameFR") == null or entrance.get_node_or_null("StationNameNL") == null:
        _fail("source-backed bilingual identity labels missing")
        return

    _hide_noise(main)
    var player_camera := main.get_node_or_null("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if player_camera != null:
        player_camera.current = false
    var car_camera := main.get_node_or_null("PrototypeCar/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if car_camera != null:
        car_camera.current = false

    var camera := Camera3D.new()
    camera.name = "MidiBilingualIdentityWitness"
    camera.position = CAMERA_POSITION
    camera.fov = CAMERA_FOV
    main.add_child(camera)
    camera.look_at(CAMERA_TARGET, Vector3.UP)
    camera.current = true
    for _frame: int in range(3):
        await process_frame

    identity.call("set_station_identity_visible", false)
    if bool(identity.call("station_identity_visible")):
        _fail("baseline identity toggle failed")
        return
    if not await _capture(OUTPUT_DIR + "/before.png"):
        _fail("before capture failed")
        return

    identity.call("set_station_identity_visible", true)
    if not bool(identity.call("station_identity_visible")):
        _fail("sourced identity toggle failed")
        return
    if not await _capture(OUTPUT_DIR + "/after.png"):
        _fail("after capture failed")
        return

    print("MIDI_BILINGUAL_STATION_IDENTITY_OK: camera=(%.3f,%.2f,%.3f) before=%s after=%s" % [
        CAMERA_POSITION.x, CAMERA_POSITION.y, CAMERA_POSITION.z,
        OUTPUT_DIR + "/before.png", OUTPUT_DIR + "/after.png"
    ])
    quit(0)
