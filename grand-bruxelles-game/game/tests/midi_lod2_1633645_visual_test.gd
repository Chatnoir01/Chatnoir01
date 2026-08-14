extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const OUTPUT_DIR := "res://artifacts/midi/lod2-1633645"
const WIDTH := 1280
const HEIGHT := 720
# Fixed normal street/player framing derived from the production Midi spawn, not a rescue camera.
const CAMERA_POSITION := Vector3(-652.0, 2.70, 621.0)
const CAMERA_TARGET := Vector3(-696.2, 6.80, 605.0)
const CAMERA_FOV := 69.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_LOD2_1633645_VISUAL_FAIL: %s" % message)
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

    var official := root.get_node_or_null("MidiOfficialLod21633645")
    if official == null:
        _fail("autoloaded official Midi LoD2 node missing")
        return
    if not bool(official.get("geometry_loaded")):
        _fail("official Midi LoD2 geometry did not load")
        return
    if int(official.get("render_triangle_count")) != 3051:
        _fail("render triangle contract drifted: %d" % int(official.get("render_triangle_count")))
        return
    if absf(float(official.get("source_height_m")) - 13.6076) > 0.0001:
        _fail("source height drifted")
        return
    if bool(official.get_meta("source_vertices_moved", true)) or bool(official.get_meta("source_triangles_replaced", true)):
        _fail("exact-source geometry invariants lost")
        return

    _hide_noise(main)
    var player_camera := main.get_node_or_null("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if player_camera != null:
        player_camera.current = false
    var car_camera := main.get_node_or_null("PrototypeCar/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if car_camera != null:
        car_camera.current = false

    var camera := Camera3D.new()
    camera.name = "Midi1633645PlayerWitness"
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

    print("MIDI_LOD2_1633645_VISUAL_OK: triangles=%d height=%.4f bounds=(%.1f,%.1f) camera=(%.1f,%.2f,%.1f) target=(%.1f,%.1f,%.1f)" % [
        int(official.get("render_triangle_count")), float(official.get("source_height_m")),
        (official.get("source_bounds") as Rect2).size.x, (official.get("source_bounds") as Rect2).size.y,
        CAMERA_POSITION.x, CAMERA_POSITION.y, CAMERA_POSITION.z,
        CAMERA_TARGET.x, CAMERA_TARGET.y, CAMERA_TARGET.z
    ])
    quit(0)
