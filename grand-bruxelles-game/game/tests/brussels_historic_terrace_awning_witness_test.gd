extends SceneTree

const AWNING_SCRIPT := preload("res://game/scripts/brussels_historic_terrace_awning.gd")
const WIDTH := 1280
const HEIGHT := 720
const WARMUP_FRAMES := 60
const EVIDENCE_PATH := "res://data/qa/photo_match/bourse_2019_geotagged_camera_evidence.json"
const OUTPUT_PATH := "res://artifacts/visual/brussels_historic_terrace_awning_witness.png"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_HISTORIC_TERRACE_AWNING_WITNESS_FAIL: %s" % message)
    quit(1)

func _vector3(raw: Variant) -> Vector3:
    var values := raw as Array
    return Vector3(float(values[0]), float(values[1]), float(values[2]))

func _horizontal_to_vertical_fov(horizontal_degrees: float, aspect: float) -> float:
    return rad_to_deg(2.0 * atan(tan(deg_to_rad(horizontal_degrees) * 0.5) / aspect))

func _hide_noise(scene: Node) -> void:
    for node_path: String in ["LocationLabel", "MissionLabel", "PrototypeLabel", "MiniMap", "MobileControls"]:
        var item := scene.get_node_or_null(node_path) as CanvasItem
        if item != null:
            item.visible = false
    for node_path: String in ["Player", "PrototypeCar", "MidiHeroZone"]:
        var spatial := scene.get_node_or_null(node_path) as Node3D
        if spatial != null:
            spatial.visible = false

func _run() -> void:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EVIDENCE_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("camera evidence invalid")
        return
    var candidate: Dictionary = (parsed as Dictionary).get("candidate_game_camera_transform", {})
    var camera_position := _vector3(candidate.get("position", []))
    var camera_rotation := _vector3(candidate.get("rotation_degrees", []))
    var horizontal_fov := float(candidate.get("horizontal_fov_degrees", 0.0))

    var packed := load("res://game/main.tscn") as PackedScene
    var scene := packed.instantiate()
    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    _hide_noise(scene)
    viewport.add_child(scene)

    var existing_camera := scene.get_viewport().get_camera_3d()
    if existing_camera != null:
        existing_camera.current = false
    var camera := Camera3D.new()
    camera.position = camera_position
    camera.rotation_degrees = camera_rotation
    camera.keep_aspect = Camera3D.KEEP_HEIGHT
    camera.fov = _horizontal_to_vertical_fov(horizontal_fov, float(WIDTH) / float(HEIGHT))
    camera.current = true
    scene.add_child(camera)
    await process_frame

    var awning := AWNING_SCRIPT.new()
    awning.name = "HistoricTerraceAwningWitness"
    scene.add_child(awning)
    await process_frame
    if not bool(awning.get("visual_built")):
        _fail("awning did not build")
        return

    # Presentation-only placement in the real Bourse production scene. The
    # source proves this vocabulary on Rue de la Bourse, but this witness does
    # not assert a surveyed facade mount, yaw or measured historic dimensions.
    var forward := -camera.global_transform.basis.z.normalized()
    var right := camera.global_transform.basis.x.normalized()
    awning.global_position = camera.global_position + forward * 9.0 - right * 1.8 + Vector3(0.0, -1.55, 0.0)
    awning.look_at(camera.global_position + Vector3(0.0, 0.7, 0.0), Vector3.UP)

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
    print("BRUSSELS_HISTORIC_TERRACE_AWNING_WITNESS_OK: %s presentation_only=true source_context=rue_de_la_bourse" % OUTPUT_PATH)
    quit(0)
