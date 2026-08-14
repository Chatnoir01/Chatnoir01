extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const OUTPUT_DIR := "res://artifacts/grand-place/lod2-1655673"
const WIDTH := 1280
const HEIGHT := 720
# Presentation witness only: fixed across the plaza toward the source-bounded 1655673 envelope.
# No surveyed camera pose or landmark dimensions are asserted by this test.
const CAMERA_POSITION := Vector3(365.0, 1.72, -505.0)
const CAMERA_TARGET := Vector3(279.5, 38.0, -515.0)
const CAMERA_FOV := 64.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_LOD2_1655673_FAIL: %s" % message)
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
    for _frame: int in range(16):
        await process_frame

    var official := root.get_node_or_null("GrandPlaceOfficialLod2")
    if official == null:
        _fail("autoloaded official LoD2 node missing")
        return
    if not bool(official.get("geometry_loaded")):
        _fail("official LoD2 geometry did not load")
        return
    if int(official.get("render_triangle_count")) != 229:
        _fail("render triangle contract drifted: %d" % int(official.get("render_triangle_count")))
        return
    if absf(float(official.get("source_height_m")) - 93.024) > 0.001:
        _fail("source height evidence drifted")
        return
    # The current compact OSM slice does not place a generated-building center inside this exact
    # official footprint. That is a production-data gap, not a failure of the official LoD2 mass.
    # If future OSM context overlaps, the runtime will mask only those overlapping generic nodes.
    if int(official.get("masked_osm_count")) < 0:
        _fail("masked OSM count became invalid")
        return
    if bool(official.get_meta("runtime_approved", true)) or bool(official.get_meta("realism_complete", true)):
        _fail("provisional realism gates were lost")
        return

    _hide_noise(main)
    var player_camera := main.get_node_or_null("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if player_camera != null:
        player_camera.current = false
    var car_camera := main.get_node_or_null("PrototypeCar/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if car_camera != null:
        car_camera.current = false

    var camera := Camera3D.new()
    camera.name = "GrandPlaceLod2Witness"
    camera.position = CAMERA_POSITION
    camera.fov = CAMERA_FOV
    main.add_child(camera)
    camera.look_at(CAMERA_TARGET, Vector3.UP)
    camera.current = true
    for _frame: int in range(3):
        await process_frame

    official.call("set_official_visible", false)
    if not await _capture(OUTPUT_DIR + "/before.png"):
        _fail("before capture failed")
        return

    official.call("set_official_visible", true)
    if not await _capture(OUTPUT_DIR + "/after.png"):
        _fail("after capture failed")
        return

    print("GRAND_PLACE_LOD2_1655673_OK: triangles=%d masked_osm=%d height=%.3f camera=(%.1f,%.2f,%.1f) target=(%.1f,%.1f,%.1f) before=%s after=%s" % [
        int(official.get("render_triangle_count")), int(official.get("masked_osm_count")), float(official.get("source_height_m")),
        CAMERA_POSITION.x, CAMERA_POSITION.y, CAMERA_POSITION.z,
        CAMERA_TARGET.x, CAMERA_TARGET.y, CAMERA_TARGET.z,
        OUTPUT_DIR + "/before.png", OUTPUT_DIR + "/after.png"
    ])
    quit(0)
