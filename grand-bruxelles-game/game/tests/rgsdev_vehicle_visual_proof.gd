extends SceneTree

const VISUAL_SCRIPT := preload("res://game/scripts/rgsdev_vehicle_visual.gd")
const EXPECTED_ENGINE_VERSION := "4.7.1"
const MODEL_IDS := [
    "ambulance", "bus", "firetruck", "hatchback", "limousine", "monster_truck", "muscle",
    "muscle_2", "pickup", "police_muscle", "police_sedan", "police_sports", "police_suv", "roadster",
    "sedan", "sports", "suv", "taxi", "truck", "truck_with_trailer", "van",
]


func _initialize() -> void:
    call_deferred("_run")


func _arg(prefix: String, fallback: String) -> String:
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with(prefix):
            return arg.substr(prefix.length())
    return fallback


func _engine_version() -> String:
    var info := Engine.get_version_info()
    return "%d.%d.%d" % [int(info.get("major", 0)), int(info.get("minor", 0)), int(info.get("patch", 0))]


func _make_box(parent: Node3D, size: Vector3, position: Vector3, color: Color) -> void:
    var mesh_instance := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.92
    mesh.material = material
    mesh_instance.mesh = mesh
    mesh_instance.position = position
    parent.add_child(mesh_instance)


func _run() -> void:
    var output_path := _arg("--output=", "/tmp/rgsdev_vehicle_visual_proof.png")
    var engine_version := _engine_version()
    if engine_version != EXPECTED_ENGINE_VERSION:
        push_error("RGSDEV_VISUAL_PROOF_FAIL engine=%s expected=%s" % [engine_version, EXPECTED_ENGINE_VERSION])
        quit(1)
        return

    root.size = Vector2i(1280, 720)
    root.content_scale_size = Vector2i(1280, 720)

    var stage := Node3D.new()
    stage.name = "RgsdevVisualProofStage"
    root.add_child(stage)

    var world_environment := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.55, 0.66, 0.76)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.95, 0.97, 1.0)
    environment.ambient_light_energy = 0.72
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    world_environment.environment = environment
    stage.add_child(world_environment)

    var sun := DirectionalLight3D.new()
    sun.name = "Sun"
    sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
    sun.light_energy = 1.35
    sun.shadow_enabled = true
    stage.add_child(sun)

    _make_box(stage, Vector3(42.0, 0.18, 23.0), Vector3(0.0, -0.12, 0.0), Color(0.12, 0.14, 0.16))
    for row: int in range(3):
        var z := -6.0 + float(row) * 6.0
        _make_box(stage, Vector3(40.0, 0.025, 0.10), Vector3(0.0, 0.01, z - 2.55), Color(0.74, 0.74, 0.70))
        _make_box(stage, Vector3(40.0, 0.025, 0.10), Vector3(0.0, 0.01, z + 2.55), Color(0.74, 0.74, 0.70))

    var visuals: Array[Node] = []
    for index: int in range(MODEL_IDS.size()):
        var column := index % 7
        var row := index / 7
        var model_id: String = MODEL_IDS[index]
        var visual := VISUAL_SCRIPT.new()
        visual.name = "Vehicle_%02d_%s" % [index + 1, model_id]
        visual.model_id = model_id
        visual.animate_wheels = false
        visual.position = Vector3(-15.0 + float(column) * 5.0, 0.02, -6.0 + float(row) * 6.0)
        visual.rotation_degrees = Vector3(0.0, 24.0, 0.0)
        stage.add_child(visual)
        visuals.append(visual)

        var label := Label3D.new()
        label.text = model_id.replace("_", " ").to_upper()
        label.position = visual.position + Vector3(0.0, 2.45, 0.0)
        label.font_size = 27
        label.outline_size = 8
        label.modulate = Color(1.0, 1.0, 1.0)
        label.outline_modulate = Color(0.03, 0.03, 0.04, 0.95)
        label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        stage.add_child(label)

    var camera := Camera3D.new()
    camera.name = "ProofCamera"
    camera.position = Vector3(0.0, 24.0, 26.0)
    camera.fov = 54.0
    stage.add_child(camera)
    camera.look_at(Vector3(0.0, 0.7, 0.0), Vector3.UP)
    camera.current = true

    for _frame: int in range(24):
        await process_frame
    await RenderingServer.frame_post_draw

    var loaded_count := 0
    for visual: Node in visuals:
        if visual.has_meta("rgsdev_model_id") and str(visual.get_meta("rgsdev_model_id")) != "":
            loaded_count += 1
    if loaded_count != MODEL_IDS.size():
        push_error("RGSDEV_VISUAL_PROOF_FAIL loaded=%d expected=%d" % [loaded_count, MODEL_IDS.size()])
        quit(1)
        return

    var image := root.get_texture().get_image()
    if image == null or image.is_empty():
        push_error("RGSDEV_VISUAL_PROOF_FAIL empty_capture")
        quit(1)
        return
    var save_error := image.save_png(output_path)
    if save_error != OK:
        push_error("RGSDEV_VISUAL_PROOF_FAIL save_error=%s output=%s" % [error_string(save_error), output_path])
        quit(1)
        return

    print("RGSDEV_VISUAL_PROOF_OK vehicles=%d engine=%s renderer=gl_compatibility output=%s" % [loaded_count, engine_version, output_path])
    quit(0)
