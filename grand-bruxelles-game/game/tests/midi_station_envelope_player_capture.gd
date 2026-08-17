extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const WARMUP_FRAMES := 70
const MIDI := Vector3(-668.5, 0.0, 627.84)
const STATION_SIDE := Vector3(-0.779, 0.0, -0.627)
# Production Player node starts at (-652, 1.05, 621). The witness uses the
# same ground position at natural eye height and turns toward the station-side
# frontage rather than centring the carriageway.
const CAMERA_POSITION := Vector3(-652.0, 1.72, 621.0)
const TARGET := MIDI + STATION_SIDE * 12.0 + Vector3(0.0, 5.5, 0.0)

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_STATION_ENVELOPE_CAPTURE_FAIL: %s" % message)
    quit(1)

func _dynamic_name(node_name: String) -> bool:
    var n := node_name.to_lower()
    for token: String in ["player", "npc", "pedestrian", "traffic", "vehicle", "movingcar", "ambient", "police"]:
        if n.contains(token):
            return true
    return false

func _mask_recursive(node: Node) -> void:
    if node is CanvasItem:
        (node as CanvasItem).visible = false
    if node is Node3D and _dynamic_name(str(node.name)):
        (node as Node3D).visible = false
        node.process_mode = Node.PROCESS_MODE_DISABLED
    for child: Node in node.get_children():
        _mask_recursive(child)

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 1:
        _fail("expected one output PNG path")
        return
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene missing")
        return
    var scene := packed.instantiate()
    if scene == null:
        _fail("main scene instantiate failed")
        return
    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    viewport.add_child(scene)
    for _frame: int in range(WARMUP_FRAMES):
        await process_frame
    _mask_recursive(scene)
    var gameplay_camera := viewport.get_camera_3d()
    if gameplay_camera != null:
        gameplay_camera.current = false
    var camera := Camera3D.new()
    camera.name = "MidiStationFrozenPlayerWitness"
    camera.fov = 69.0
    camera.position = CAMERA_POSITION
    scene.add_child(camera)
    camera.look_at(TARGET, Vector3.UP)
    camera.current = true
    _mask_recursive(scene)
    scene.process_mode = Node.PROCESS_MODE_DISABLED
    RenderingServer.force_draw()
    await process_frame
    await RenderingServer.frame_post_draw
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        _fail("invalid 1280x720 render")
        return
    var output := str(args[0])
    var absolute := output if output.begins_with("/") else ProjectSettings.globalize_path(output)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    if image.save_png(absolute) != OK:
        _fail("save failed")
        return
    print("MIDI_STATION_ENVELOPE_CAPTURE_OK path=%s camera=%s target=%s production_spawn_ground=true station_facing=true ui_masked=true dynamics_frozen=true" % [absolute, str(CAMERA_POSITION), str(TARGET)])
    quit(0)
