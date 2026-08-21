extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const OUTPUT_DIR := "res://artifacts/grand-place/1786758-white-stone"
const IDENTITY_PATH := "res://data/visual/grand_place_1786758_material_identity.json"
const WIDTH := 1280
const HEIGHT := 720
const CAMERA_POSITION := Vector3(365.0, 1.72, -505.0)
const CAMERA_TARGET := Vector3(279.5, 38.0, -515.0)
const CAMERA_FOV := 64.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_1786758_WHITE_STONE_FAIL: %s" % message)
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

func _validate_identity() -> bool:
    if not FileAccess.file_exists(IDENTITY_PATH):
        return false
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(IDENTITY_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        return false
    var data := parsed as Dictionary
    var target := data.get("target", {}) as Dictionary
    var geometry := data.get("geometry_source", {}) as Dictionary
    var contract := data.get("presentation_contract", {}) as Dictionary
    if str(target.get("urbis_building_id", "")) != "https://databrussels.be/id/building/1786758":
        return false
    if str(geometry.get("crs", "")) != "EPSG:31370" or str(geometry.get("package_sha256", "")) != "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2":
        return false
    var bbox := geometry.get("source_bbox_xy", []) as Array
    if bbox.size() != 4:
        return false
    var sources := data.get("identity_sources", []) as Array
    if sources.size() != 3:
        return false
    var city := sources[0] as Dictionary
    var records := city.get("records", []) as Array
    if records.size() != 2:
        return false
    for raw_record: Variant in records:
        var record := raw_record as Dictionary
        var point := record.get("derived_point_epsg31370", []) as Array
        if point.size() != 2:
            return false
        var x := float(point[0]); var y := float(point[1])
        if x < float(bbox[0]) or x > float(bbox[2]) or y < float(bbox[1]) or y > float(bbox[3]):
            return false
    if str(contract.get("applies_to", "")) != "WALLSURFACE only" or not bool(contract.get("roof_unchanged", false)):
        return false
    if bool(contract.get("geometry_changed", true)) or bool(contract.get("openings_authored", true)) or bool(contract.get("exact_rgb_is_photometric_measurement", true)):
        return false
    return true

func _run() -> void:
    if not _validate_identity():
        _fail("material identity/provenance contract invalid")
        return

    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    for _frame: int in range(16):
        await process_frame

    var town_hall := root.get_node_or_null("GrandPlaceOfficialLod2")
    var candidate := root.get_node_or_null("GrandPlaceOfficialLod2Next")
    if town_hall == null or candidate == null:
        _fail("Grand-Place ensemble autoload missing")
        return
    if not bool(town_hall.get("geometry_loaded")) or not bool(candidate.get("geometry_loaded")):
        _fail("official Grand-Place geometry did not load")
        return
    if not candidate.has_method("set_white_stone_presentation"):
        _fail("white-stone WALLSURFACE presentation toggle missing")
        return
    if not candidate.has_method("white_stone_presentation_enabled"):
        _fail("white-stone presentation state probe missing")
        return

    _hide_noise(main)
    var player_camera := main.get_node_or_null("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if player_camera != null:
        player_camera.current = false
    var car_camera := main.get_node_or_null("PrototypeCar/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if car_camera != null:
        car_camera.current = false

    var camera := Camera3D.new()
    camera.name = "GrandPlace1786758WhiteStoneWitness"
    camera.position = CAMERA_POSITION
    camera.fov = CAMERA_FOV
    main.add_child(camera)
    camera.look_at(CAMERA_TARGET, Vector3.UP)
    camera.current = true
    for _frame: int in range(3):
        await process_frame

    town_hall.call("set_official_visible", true)
    candidate.call("set_official_visible", true)
    candidate.call("set_white_stone_presentation", false)
    if bool(candidate.call("white_stone_presentation_enabled")):
        _fail("neutral baseline toggle failed")
        return
    if not await _capture(OUTPUT_DIR + "/before.png"):
        _fail("before capture failed")
        return

    candidate.call("set_white_stone_presentation", true)
    if not bool(candidate.call("white_stone_presentation_enabled")):
        _fail("white-stone candidate toggle failed")
        return
    if str(candidate.get_meta("wall_material_identity_source", "")) != "urban.brussels 31126 + 40020; City of Brussels Grand-Place open data":
        _fail("runtime material provenance metadata missing")
        return
    if not await _capture(OUTPUT_DIR + "/after.png"):
        _fail("after capture failed")
        return

    print("GRAND_PLACE_1786758_WHITE_STONE_OK: height=%.4f camera=(%.1f,%.2f,%.1f) before=%s after=%s" % [
        float(candidate.get("source_height_m")), CAMERA_POSITION.x, CAMERA_POSITION.y, CAMERA_POSITION.z,
        OUTPUT_DIR + "/before.png", OUTPUT_DIR + "/after.png"
    ])
    quit(0)
