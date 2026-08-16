extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const OUTPUT_DIR := "res://artifacts/grand-place/townhall-white-stone"
const MATERIAL_IDENTITY_PATH := "res://data/visual/grand_place_1655673_material_identity.json"
const WIDTH := 1280
const HEIGHT := 720
const CAMERA_POSITION := Vector3(365.0, 1.72, -505.0)
const CAMERA_TARGET := Vector3(279.5, 38.0, -515.0)
const CAMERA_FOV := 64.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_TOWNHALL_WHITE_STONE_FAIL: %s" % message)
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
    var showcase := root.get_node_or_null("LivingCityShowcaseRuntime")
    if showcase != null:
        showcase.process_mode = Node.PROCESS_MODE_DISABLED
    var visible_runtime := root.get_node_or_null("VisibleCityRuntime")
    if visible_runtime != null and visible_runtime.has_method("_set_status"):
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

func _read_material_identity() -> Dictionary:
    if not FileAccess.file_exists(MATERIAL_IDENTITY_PATH):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MATERIAL_IDENTITY_PATH))
    return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}

func _run() -> void:
    var identity := _read_material_identity()
    if identity.is_empty():
        _fail("material identity evidence missing")
        return
    var target: Dictionary = identity.get("target", {})
    var source: Dictionary = identity.get("material_identity_source", {})
    var contract: Dictionary = identity.get("presentation_contract", {})
    if str(target.get("urbis_building_id", "")) != "https://databrussels.be/id/building/1655673":
        _fail("material identity building contract drifted")
        return
    if str(source.get("provider", "")) != "urban.brussels / Inventaire du patrimoine architectural":
        _fail("material identity source drifted")
        return
    if str(source.get("record", "")) != "Hotel de ville, Grand-Place 8, Urban 31125":
        _fail("heritage record drifted")
        return
    if bool(contract.get("exact_rgb_is_photometric_measurement", true)) or bool(contract.get("geometry_changed", true)):
        _fail("presentation/source boundary drifted")
        return
    if bool(contract.get("runtime_approved", true)) or bool(contract.get("realism_complete", true)):
        _fail("provisional realism gates were lost")
        return

    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    for _frame: int in range(16):
        await process_frame

    var townhall := root.get_node_or_null("GrandPlaceOfficialLod2")
    var ensemble := root.get_node_or_null("GrandPlaceOfficialLod2Next")
    if townhall == null or ensemble == null:
        _fail("Grand-Place LoD2 ensemble autoload missing")
        return
    if not bool(townhall.get("geometry_loaded")) or not bool(ensemble.get("geometry_loaded")):
        _fail("shipped Grand-Place geometry did not load")
        return
    if int(townhall.get("render_triangle_count")) <= 0 or int(ensemble.get("render_triangle_count")) <= 0:
        _fail("shipped triangle contracts were lost")
        return
    if absf(float(townhall.get("source_height_m")) - 93.024) > 0.001:
        _fail("town hall source height evidence drifted")
        return

    _hide_noise(main)
    # The reusable mineral presentation is a downstream wall override. Disable
    # it here so this legacy witness continues to test the original sourced
    # white-stone identity toggle rather than comparing the same override twice.
    var surface_runtime := root.get_node_or_null("GrandPlaceWhiteStoneSurfaceRuntime")
    if surface_runtime != null:
        surface_runtime.call("set_enabled", false)

    var player_camera := main.get_node_or_null("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if player_camera != null:
        player_camera.current = false
    var car_camera := main.get_node_or_null("PrototypeCar/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if car_camera != null:
        car_camera.current = false

    var camera := Camera3D.new()
    camera.name = "GrandPlaceTownHallMaterialWitness"
    camera.position = CAMERA_POSITION
    camera.fov = CAMERA_FOV
    main.add_child(camera)
    camera.look_at(CAMERA_TARGET, Vector3.UP)
    camera.current = true
    townhall.call("set_official_visible", true)
    ensemble.call("set_official_visible", true)
    for _frame: int in range(3):
        await process_frame

    townhall.call("set_sourced_wall_material", false)
    if bool(townhall.call("sourced_wall_material_enabled")):
        _fail("neutral baseline toggle failed")
        return
    if not await _capture(OUTPUT_DIR + "/before.png"):
        _fail("before capture failed")
        return

    townhall.call("set_sourced_wall_material", true)
    if not bool(townhall.call("sourced_wall_material_enabled")):
        _fail("sourced white-stone toggle failed")
        return
    if not await _capture(OUTPUT_DIR + "/after.png"):
        _fail("after capture failed")
        return

    print("GRAND_PLACE_TOWNHALL_WHITE_STONE_OK: townhall_triangles=%d ensemble_triangles=%d camera=(%.1f,%.2f,%.1f) before=%s after=%s" % [
        int(townhall.get("render_triangle_count")), int(ensemble.get("render_triangle_count")),
        CAMERA_POSITION.x, CAMERA_POSITION.y, CAMERA_POSITION.z,
        OUTPUT_DIR + "/before.png", OUTPUT_DIR + "/after.png"
    ])
    quit(0)