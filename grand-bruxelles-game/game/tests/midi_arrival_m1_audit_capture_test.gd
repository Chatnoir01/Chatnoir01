extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const OUT_DIR := "res://artifacts/visual/midi_m1_arrival_audit"
const SPAWN_PATH := OUT_DIR + "/midi_m1_spawn.png"
const PARVIS_PATH := OUT_DIR + "/midi_m1_parvis.png"
const STATION_PATH := OUT_DIR + "/midi_m1_station_face.png"

# Production truths copied from main.tscn / already-validated Midi witnesses.
const PLAYER_SPAWN := Vector3(-652.0, 1.05, 621.0)
const ENTRANCE := Vector3(-672.2905, 0.0, 615.8035)
const ROAD_SIDE := Vector3(0.779, 0.0, 0.627)
const PLAYER_FOV := 69.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_M1_AUDIT_FAIL: %s" % message)
    quit(1)

func _hide_ui(node: Node) -> void:
    if node is CanvasItem:
        (node as CanvasItem).visible = false
    for child in node.get_children():
        _hide_ui(child)

func _freeze_dynamics(scene: Node) -> void:
    var traffic := scene.get_node_or_null("TrafficManager")
    if traffic != null:
        traffic.set("auto_spawn_runtime", false)
        if traffic is Node3D:
            (traffic as Node3D).visible = false
    for path in ["PrototypeCar", "PhysicalCarB", "MidiUrbanLife"]:
        var n := scene.get_node_or_null(path) as Node3D
        if n != null:
            n.visible = false
    var player := scene.get_node_or_null("Player") as Node3D
    if player != null:
        player.visible = false
    for child in scene.get_children():
        if child is CanvasLayer or child is Control:
            _hide_ui(child)

func _capture(viewport: SubViewport, path: String) -> bool:
    RenderingServer.force_draw()
    await process_frame
    await RenderingServer.frame_post_draw
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty():
        return false
    if image.get_size() != Vector2i(WIDTH, HEIGHT):
        return false
    var absolute := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    return image.save_png(absolute) == OK

func _set_view(camera: Camera3D, position: Vector3, target: Vector3) -> void:
    camera.global_position = position
    camera.fov = PLAYER_FOV
    camera.look_at(target, Vector3.UP)
    camera.current = true

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("production main scene missing")
        return
    var scene := packed.instantiate() as Node3D
    if scene == null:
        _fail("production main scene failed to instantiate")
        return

    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    viewport.add_child(scene)

    for _i in range(90):
        await process_frame
    _freeze_dynamics(scene)
    scene.process_mode = Node.PROCESS_MODE_DISABLED
    await process_frame

    var original_camera := viewport.get_camera_3d()
    if original_camera == null:
        _fail("production player camera missing")
        return

    # View 1: exact production player spawn camera, untouched transform/FOV.
    original_camera.current = true
    if not await _capture(viewport, SPAWN_PATH):
        _fail("spawn capture failed")
        return

    # Views 2/3 remain on the real spawn->Fonsny entrance player path and use player FOV.
    var audit_camera := Camera3D.new()
    audit_camera.name = "MidiM1AuditCamera"
    scene.add_child(audit_camera)

    var path_dir := (ENTRANCE - PLAYER_SPAWN)
    path_dir.y = 0.0
    path_dir = path_dir.normalized()
    var parvis_eye := PLAYER_SPAWN + path_dir * 11.0 + Vector3(0.0, 0.60, 0.0)
    _set_view(audit_camera, parvis_eye, ENTRANCE + Vector3(0.0, 2.2, 0.0))
    if not await _capture(viewport, PARVIS_PATH):
        _fail("parvis capture failed")
        return

    var station_eye := ENTRANCE + ROAD_SIDE * 28.0 + Vector3(0.0, 1.65, 0.0)
    _set_view(audit_camera, station_eye, ENTRANCE + Vector3(0.0, 3.2, 0.0))
    if not await _capture(viewport, STATION_PATH):
        _fail("station-face capture failed")
        return

    print("MIDI_M1_AUDIT_OK spawn=%s parvis=%s station=%s spawn_world=%s entrance=%s fov=%.1f" % [SPAWN_PATH, PARVIS_PATH, STATION_PATH, str(PLAYER_SPAWN), str(ENTRANCE), PLAYER_FOV])
    quit(0)
