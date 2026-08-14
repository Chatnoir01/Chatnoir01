extends SceneTree

const SIGN_SCRIPT := preload("res://game/scripts/brussels_bilingual_street_sign.gd")
const WIDTH := 1280
const HEIGHT := 720
const WARMUP_FRAMES := 60
const EVIDENCE_PATH := "res://data/qa/photo_match/bourse_2019_geotagged_camera_evidence.json"
const OUTPUT_PATH := "res://artifacts/visual/brussels_bilingual_street_sign_witness.png"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_BILINGUAL_STREET_SIGN_WITNESS_FAIL: %s" % message)
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

    var sign := SIGN_SCRIPT.new()
    sign.name = "BilingualStreetSignWitness"
    sign.french_name = "RUE DE LA BOURSE"
    sign.dutch_name = "BEURSSTRAAT"
    scene.add_child(sign)
    await process_frame
    if not bool(sign.get("visual_built")):
        _fail("sign did not build")
        return

    # Presentation-only witness placement relative to the production Bourse
    # camera. This does NOT claim a surveyed wall/pole anchor.
    var forward := -camera.global_transform.basis.z.normalized()
    var right := camera.global_transform.basis.x.normalized()
    sign.global_position = camera.global_position + forward * 4.2 - right * 1.25 + Vector3(0.0, 0.10, 0.0)
    sign.look_at(camera.global_position, Vector3.UP)

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
    print("BRUSSELS_BILINGUAL_STREET_SIGN_WITNESS_OK: %s presentation_only=true" % OUTPUT_PATH)
    quit(0)
