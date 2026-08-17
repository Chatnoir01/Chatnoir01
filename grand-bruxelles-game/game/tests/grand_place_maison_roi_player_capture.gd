extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const WARMUP_FRAMES := 100
const TARGET := Vector3(346.6, 10.5, -565.5)
const SQUARE_DIRECTION := Vector3(-1.0, 0.0, 1.0).normalized()
const CAMERA_POSITION := TARGET + SQUARE_DIRECTION * 38.0 + Vector3(0.0, -8.8, 0.0)

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_MAISON_ROI_CAPTURE_FAIL: " + message)
    quit(1)

func _is_dynamic_name(node_name: String) -> bool:
    var n := node_name.to_lower()
    for token: String in ["npc", "pedestrian", "trafficvehicle", "traffic_vehicle", "movingcar", "moving_car", "playercharacter", "player_character", "ambientvehicle", "ambient_vehicle"]:
        if n.contains(token):
            return true
    return false

func _mask_noise(node: Node) -> void:
    if node is CanvasLayer:
        (node as CanvasLayer).visible = false
    elif node is Control:
        (node as Control).visible = false
    elif node is Node3D and _is_dynamic_name(str(node.name)):
        (node as Node3D).visible = false
    for child: Node in node.get_children():
        _mask_noise(child)

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 1:
        _fail("expected output PNG path")
        return
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene missing")
        return
    var scene := packed.instantiate()
    if scene == null:
        _fail("main scene instantiate failed")
        return
    var traffic_manager := scene.get_node_or_null("TrafficManager")
    if traffic_manager != null:
        traffic_manager.set("auto_spawn_runtime", false)
    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    viewport.add_child(scene)
    for _frame: int in range(WARMUP_FRAMES):
        await process_frame
    _mask_noise(scene)
    var gameplay_camera := viewport.get_camera_3d()
    if gameplay_camera != null:
        gameplay_camera.current = false
    var camera := Camera3D.new()
    camera.name = "MaisonDuRoiFrozenPlayerCamera"
    camera.fov = 66.0
    camera.position = CAMERA_POSITION
    scene.add_child(camera)
    camera.look_at(TARGET, Vector3.UP)
    camera.current = true
    scene.process_mode = Node.PROCESS_MODE_DISABLED
    _mask_noise(scene)
    RenderingServer.force_draw()
    await process_frame
    await RenderingServer.frame_post_draw
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        _fail("invalid capture")
        return
    var output := str(args[0])
    var absolute := output if output.begins_with("/") else ProjectSettings.globalize_path(output)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    if image.save_png(absolute) != OK:
        _fail("save failed")
        return
    print("GRAND_PLACE_MAISON_ROI_CAPTURE_OK path=%s camera=%s target=%s" % [absolute, str(camera.global_position), str(TARGET)])
    quit(0)
