extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const OUTPUT_DIR := "res://artifacts/grand-place/lod2-1786758"
const DATA_PATH := "res://data/urbis/grand_place_lod2/1786758.game.json"
const WIDTH := 1280
const HEIGHT := 720
const CAMERA_POSITION := Vector3(365.0, 1.72, -505.0)
const CAMERA_TARGET := Vector3(279.5, 38.0, -515.0)
const CAMERA_FOV := 64.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_LOD2_1786758_FAIL: %s" % message)
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

func _expected_render_triangles() -> int:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        return -1
    var total := 0
    for raw_face: Variant in (parsed as Dictionary).get("faces", []):
        if typeof(raw_face) != TYPE_DICTIONARY:
            continue
        var face_type := str(raw_face.get("type", ""))
        if face_type == "WALLSURFACE" or face_type == "ROOFSURFACE":
            total += (raw_face.get("triangles", []) as Array).size()
    return total

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    for _frame: int in range(16):
        await process_frame

    var shipped := root.get_node_or_null("GrandPlaceOfficialLod2")
    var candidate := root.get_node_or_null("GrandPlaceOfficialLod2Next")
    if shipped == null or candidate == null:
        _fail("Grand-Place ensemble autoload missing")
        return
    if not bool(shipped.get("geometry_loaded")):
        _fail("shipped 1655673 geometry must remain loaded")
        return
    if not bool(candidate.get("geometry_loaded")):
        _fail("candidate 1786758 geometry did not load")
        return
    var expected := _expected_render_triangles()
    if expected <= 0 or int(candidate.get("render_triangle_count")) != expected:
        _fail("candidate render triangle contract drifted: runtime=%d expected=%d" % [int(candidate.get("render_triangle_count")), expected])
        return
    if absf(float(candidate.get("source_height_m")) - 29.2844) > 0.001:
        _fail("candidate source height evidence drifted")
        return
    if bool(candidate.get_meta("runtime_approved", true)) or bool(candidate.get_meta("realism_complete", true)):
        _fail("candidate provisional realism gates were lost")
        return

    _hide_noise(main)
    var player_camera := main.get_node_or_null("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if player_camera != null:
        player_camera.current = false
    var car_camera := main.get_node_or_null("PrototypeCar/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if car_camera != null:
        car_camera.current = false

    var camera := Camera3D.new()
    camera.name = "GrandPlaceLod2EnsembleWitness"
    camera.position = CAMERA_POSITION
    camera.fov = CAMERA_FOV
    main.add_child(camera)
    camera.look_at(CAMERA_TARGET, Vector3.UP)
    camera.current = true
    for _frame: int in range(3):
        await process_frame

    # Baseline always preserves shipped #257; only candidate 1786758 is toggled.
    shipped.call("set_official_visible", true)
    candidate.call("set_official_visible", false)
    if not await _capture(OUTPUT_DIR + "/before.png"):
        _fail("before capture failed")
        return

    candidate.call("set_official_visible", true)
    if not await _capture(OUTPUT_DIR + "/after.png"):
        _fail("after capture failed")
        return

    print("GRAND_PLACE_LOD2_1786758_OK: triangles=%d masked_osm=%d height=%.4f camera=(%.1f,%.2f,%.1f) before=%s after=%s" % [
        int(candidate.get("render_triangle_count")), int(candidate.get("masked_osm_count")), float(candidate.get("source_height_m")),
        CAMERA_POSITION.x, CAMERA_POSITION.y, CAMERA_POSITION.z,
        OUTPUT_DIR + "/before.png", OUTPUT_DIR + "/after.png"
    ])
    quit(0)
