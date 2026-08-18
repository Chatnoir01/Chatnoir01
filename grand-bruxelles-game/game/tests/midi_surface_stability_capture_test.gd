extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const WARMUP_FRAMES := 100
const FIXED_CAMERA_Y := 1.60
const DYNAMIC_ROOTS := [
    "Player",
    "PrototypeCar",
    "MidiUrbanLife",
    "TrafficManager",
    "NpcPopulationDirector",
    "NpcRuntimeIntegration",
]

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_SURFACE_STABILITY_CAPTURE_FAIL: %s" % message)
    quit(1)

func _hide_recursive(node: Node) -> void:
    if node is VisualInstance3D:
        (node as VisualInstance3D).visible = false
    elif node is CanvasItem:
        (node as CanvasItem).visible = false
    for child: Node in node.get_children():
        _hide_recursive(child)

func _hide_dynamic_and_ui(scene: Node) -> int:
    var hidden_roots := 0
    for root_name: String in DYNAMIC_ROOTS:
        var dynamic_root := scene.get_node_or_null(root_name)
        if dynamic_root != null:
            _hide_recursive(dynamic_root)
            hidden_roots += 1
    # This collision-only A/B is a world-geometry stability witness. UI is not
    # part of the collision contract and must not introduce timing noise.
    for child: Node in scene.get_children():
        if child is CanvasLayer:
            _hide_recursive(child)
    return hidden_roots

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 1:
        _fail("expected exactly one output PNG path")
        return
    var output_path := args[0]

    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    if scene == null:
        _fail("main scene did not instantiate")
        return

    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)

    var traffic_manager := scene.get_node_or_null("TrafficManager")
    if traffic_manager != null:
        traffic_manager.set("auto_spawn_runtime", false)
    viewport.add_child(scene)

    # Let all source-backed world builders finish before freezing the scene.
    for _frame: int in range(WARMUP_FRAMES):
        await process_frame

    var gameplay_camera := viewport.get_camera_3d()
    if gameplay_camera == null:
        _fail("normal gameplay camera missing")
        return

    # Detach the witness from Player physics. We keep the real gameplay camera
    # X/Z, basis and FOV, but normalize Y so the intentional 10.5 cm player-foot
    # lift cannot masquerade as a geometry change.
    var qa_camera := Camera3D.new()
    qa_camera.name = "MidiSurfaceStabilityQACamera"
    qa_camera.global_transform = gameplay_camera.global_transform
    var qa_position := qa_camera.global_position
    qa_position.y = FIXED_CAMERA_Y
    qa_camera.global_position = qa_position
    qa_camera.fov = gameplay_camera.fov
    scene.add_child(qa_camera)
    gameplay_camera.current = false
    qa_camera.current = true

    var hidden_dynamic_roots := _hide_dynamic_and_ui(scene)
    scene.process_mode = Node.PROCESS_MODE_DISABLED

    RenderingServer.force_draw()
    await process_frame
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty():
        _fail("capture image is empty")
        return

    var absolute := output_path
    if not output_path.begins_with("/"):
        absolute = ProjectSettings.globalize_path(output_path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    if image.save_png(absolute) != OK:
        _fail("could not save PNG to %s" % absolute)
        return

    print("MIDI_SURFACE_STABILITY_CAPTURE_OK: %s camera=%s fixed_y=%.2f dynamic_roots_hidden=%d" % [absolute, str(qa_camera.global_position), FIXED_CAMERA_Y, hidden_dynamic_roots])
    viewport.queue_free()
    quit(0)
