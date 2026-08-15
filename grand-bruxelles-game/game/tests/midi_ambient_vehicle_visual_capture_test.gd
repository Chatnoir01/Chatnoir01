extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const WARMUP_FRAMES := 100

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_AMBIENT_VEHICLE_CAPTURE_FAIL: %s" % message)
    quit(1)

func _hide_qa_noise(scene: Node) -> void:
    for node_path: String in ["PrototypeLabel", "ABLabel"]:
        var item := scene.get_node_or_null(node_path) as CanvasItem
        if item != null:
            item.visible = false

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
    _hide_qa_noise(scene)
    viewport.add_child(scene)

    for _frame: int in range(WARMUP_FRAMES):
        await process_frame
    _hide_qa_noise(scene)

    var camera := viewport.get_camera_3d()
    if camera == null:
        _fail("normal gameplay camera missing")
        return

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

    print("MIDI_AMBIENT_VEHICLE_CAPTURE_OK: %s camera=%s" % [absolute, str(camera.global_position)])
    viewport.queue_free()
    quit(0)
