extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const WARMUP_FRAMES := 90
const PLAYER_FOV := 69.0
const CAMERA_POSITION := Vector3(101.90921495304792, 1.68, -738.3896080011874)
const CAMERA_ROTATION := Vector3(0.0, -135.21993255901, 0.0)
const OUTPUT_PATH := "res://artifacts/bourse/normal-player-ground/bourse_ground.png"

func _fail(message: String) -> void:
    push_error("BOURSE_NORMAL_PLAYER_GROUND_CAPTURE_FAIL: %s" % message)
    quit(1)

func _initialize() -> void:
    call_deferred("_run")

func _hide_generated_labels(node: Node) -> void:
    if node is Label3D:
        (node as Label3D).visible = false
    for child: Node in node.get_children():
        _hide_generated_labels(child)

func _hide_capture_noise(scene: Node) -> void:
    for node_path: String in ["LocationLabel", "MissionLabel", "PrototypeLabel", "MiniMap", "MobileControls"]:
        var item := scene.get_node_or_null(node_path) as CanvasItem
        if item != null:
            item.visible = false
    for node_path: String in ["Player", "PrototypeCar", "PhysicalCarB", "MidiHeroZone"]:
        var spatial := scene.get_node_or_null(node_path) as Node3D
        if spatial != null:
            spatial.visible = false
    _hide_generated_labels(scene)

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    if scene == null:
        _fail("main scene did not instantiate")
        return

    var capture_viewport := SubViewport.new()
    capture_viewport.name = "BourseNormalPlayerGroundViewport"
    capture_viewport.size = Vector2i(WIDTH, HEIGHT)
    capture_viewport.own_world_3d = true
    capture_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    capture_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(capture_viewport)

    var traffic_manager := scene.get_node_or_null("TrafficManager")
    if traffic_manager != null:
        traffic_manager.set("auto_spawn_runtime", false)
    _hide_capture_noise(scene)
    capture_viewport.add_child(scene)

    var controller := root.get_node_or_null("BourseGroundSurfaceVisibility")
    if controller != null and controller.has_method("apply_to_scene"):
        controller.call("apply_to_scene", scene)

    var existing_camera := scene.get_viewport().get_camera_3d()
    if existing_camera != null:
        existing_camera.current = false

    var camera := Camera3D.new()
    camera.name = "BourseNormalPlayerGroundCamera"
    camera.position = CAMERA_POSITION
    camera.rotation_degrees = CAMERA_ROTATION
    camera.keep_aspect = Camera3D.KEEP_HEIGHT
    camera.fov = PLAYER_FOV
    camera.current = true
    scene.add_child(camera)

    print("BOURSE_NORMAL_PLAYER_CAMERA: pos=%s rot=%s fov=%.1f size=%dx%d" % [str(CAMERA_POSITION), str(CAMERA_ROTATION), PLAYER_FOV, WIDTH, HEIGHT])

    for _frame: int in range(WARMUP_FRAMES):
        await process_frame
    _hide_capture_noise(scene)
    RenderingServer.force_draw()
    await process_frame

    var image := capture_viewport.get_texture().get_image()
    if image == null or image.is_empty():
        _fail("captured viewport is empty")
        return
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        _fail("unexpected capture dimensions")
        return

    var absolute_output := ProjectSettings.globalize_path(OUTPUT_PATH)
    var dir_error := DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
    if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
        _fail("could not create artifact directory")
        return
    var save_error := image.save_png(absolute_output)
    if save_error != OK:
        _fail("could not save capture: %s" % error_string(save_error))
        return

    print("BOURSE_NORMAL_PLAYER_GROUND_CAPTURE_OK: %s" % OUTPUT_PATH)
    capture_viewport.queue_free()
    quit(0)
