extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const OUTPUT_DIR := "res://artifacts/midi/fonsny-roof-continuation"
const WIDTH := 1280
const HEIGHT := 720
# Production Midi spawn, looking naturally along the Fonsny axis toward the
# long official continuation. Position/FOV are not changed between A and B.
const CAMERA_POSITION := Vector3(-652.0, 2.70, 621.0)
const CAMERA_TARGET := Vector3(-809.10, 7.00, 748.30)
const CAMERA_FOV := 69.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_FONSNY_ROOF_CONTINUATION_VISUAL_FAIL: %s" % message)
    quit(1)

func _hide_dynamic_world(main: Node) -> void:
    for name_value: String in ["LocationLabel", "MissionLabel", "SaveStatusLabel", "WalletLabel", "MiniMap", "MobileControls", "PrototypeLabel"]:
        var node := main.get_node_or_null(name_value)
        if node is CanvasItem:
            (node as CanvasItem).visible = false
    for path: String in ["Player", "PrototypeCar", "PhysicalCarB", "TrafficManager", "MidiUrbanLife"]:
        var node := main.get_node_or_null(path)
        if node is Node3D:
            (node as Node3D).visible = false
    for path: String in ["NpcPopulationDirector", "NpcRuntimeIntegration", "RuntimeGameplayState"]:
        var node := main.get_node_or_null(path)
        if node != null:
            node.process_mode = Node.PROCESS_MODE_DISABLED

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
    for _frame: int in range(24):
        await process_frame

    var continuation := root.get_node_or_null("MidiFonsnyOfficialRoofContinuation")
    if continuation == null:
        _fail("autoload missing")
        return
    if not bool(continuation.get("geometry_loaded")):
        _fail("official continuation geometry did not load")
        return
    if int(continuation.get("source_face_count")) != 18 or int(continuation.get("render_triangle_count")) != 105:
        _fail("source/runtime count contract drifted")
        return
    if bool(continuation.get_meta("source_vertices_moved", true)) or bool(continuation.get_meta("source_triangles_replaced", true)) or bool(continuation.get_meta("source_faces_clipped", true)):
        _fail("exact-source invariants lost")
        return
    if bool(continuation.get_meta("hero_zone_replaced", true)):
        _fail("hero Fonsny zone must remain mounted")
        return
    if bool(continuation.get_meta("material_identity_claimed", true)):
        _fail("neutral presentation must not claim a roof material identity")
        return

    _hide_dynamic_world(main)
    for path: String in ["Player/CameraPivot/SpringArm3D/Camera3D", "PrototypeCar/CameraPivot/SpringArm3D/Camera3D", "PhysicalCarB/CameraPivot/SpringArm3D/Camera3D"]:
        var existing := main.get_node_or_null(path) as Camera3D
        if existing != null:
            existing.current = false

    var camera := Camera3D.new()
    camera.name = "MidiFonsnyRoofContinuationWitness"
    camera.position = CAMERA_POSITION
    camera.fov = CAMERA_FOV
    main.add_child(camera)
    camera.look_at(CAMERA_TARGET, Vector3.UP)
    camera.current = true
    for _frame: int in range(4):
        await process_frame

    # Freeze the complete production world before either capture. The only A/B
    # mutation after this point is continuation visibility.
    main.process_mode = Node.PROCESS_MODE_DISABLED

    continuation.call("set_continuation_visible", false)
    if not await _capture(OUTPUT_DIR + "/before.png"):
        _fail("before capture failed")
        return
    continuation.call("set_continuation_visible", true)
    if not await _capture(OUTPUT_DIR + "/after.png"):
        _fail("after capture failed")
        return

    print("MIDI_FONSNY_ROOF_CONTINUATION_VISUAL_OK: faces=18 triangles=105 camera=(%.1f,%.2f,%.1f) target=(%.1f,%.1f,%.1f) fov=%.1f" % [CAMERA_POSITION.x, CAMERA_POSITION.y, CAMERA_POSITION.z, CAMERA_TARGET.x, CAMERA_TARGET.y, CAMERA_TARGET.z, CAMERA_FOV])
    quit(0)
