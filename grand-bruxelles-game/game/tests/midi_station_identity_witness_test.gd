extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const WARMUP_FRAMES := 60
const OUTPUT_PATH := "res://artifacts/visual/midi_station_identity_witness.png"


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("MIDI_STATION_IDENTITY_WITNESS_FAIL: %s" % message)
    quit(1)


func _hide_noise(scene: Node) -> void:
    for node_path: String in ["LocationLabel", "MissionLabel", "PrototypeLabel", "MiniMap", "MobileControls", "SaveStatusLabel", "WalletLabel"]:
        var item := scene.get_node_or_null(node_path) as CanvasItem
        if item != null:
            item.visible = false
    for node_path: String in ["Player", "PrototypeCar"]:
        var spatial := scene.get_node_or_null(node_path) as Node3D
        if spatial != null:
            spatial.visible = false


func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    var scene := packed.instantiate()
    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    _hide_noise(scene)
    viewport.add_child(scene)

    for _frame: int in range(8):
        await process_frame
    var entrance := scene.get_node_or_null("MidiHeroZone/MidiMainEntranceFonsny") as Node3D
    if entrance == null:
        _fail("production Fonsny entrance missing")
        return
    var panel := entrance.get_node_or_null("StationIdentityPanel") as MeshInstance3D
    if panel == null:
        _fail("production identity panel missing")
        return

    var existing_camera := scene.get_viewport().get_camera_3d()
    if existing_camera != null:
        existing_camera.current = false
    var camera := Camera3D.new()
    camera.global_position = entrance.to_global(Vector3(-31.0, 4.65, -11.5))
    camera.look_at(entrance.to_global(Vector3(-15.25, 3.55, -1.0)), Vector3.UP)
    camera.fov = 48.0
    camera.current = true
    scene.add_child(camera)

    for _frame: int in range(WARMUP_FRAMES):
        await process_frame
    _hide_noise(scene)
    RenderingServer.force_draw()
    await process_frame

    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        _fail("capture invalid")
        return
    var absolute_output := ProjectSettings.globalize_path(OUTPUT_PATH)
    DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
    if image.save_png(absolute_output) != OK:
        _fail("capture save failed")
        return
    print("MIDI_STATION_IDENTITY_WITNESS_OK: %s production_scene=true" % OUTPUT_PATH)
    quit(0)
