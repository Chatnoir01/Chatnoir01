extends SceneTree

const VISUAL_SCRIPT := preload("res://game/scripts/rgsdev_vehicle_visual.gd")
const DRIVABLE_SCRIPT := preload("res://game/scripts/drivable_traffic_vehicle.gd")
const EXPECTED_ENGINE_VERSION := "4.7.1"
const ALL_MODEL_IDS := [
    "ambulance", "bus", "firetruck", "hatchback", "limousine", "monster_truck", "muscle",
    "muscle_2", "pickup", "police_muscle", "police_sedan", "police_sports", "police_suv", "roadster",
    "sedan", "sports", "suv", "taxi", "truck", "truck_with_trailer", "van",
]
const MOTION_MODELS := ["sedan", "hatchback", "suv"]
const CAR_COLLISION_SIZE := Vector3(1.82, 1.16, 4.15)
const ROAD_TOP_Y := -CAR_COLLISION_SIZE.y * 0.5


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


func _material(color: Color, roughness: float = 0.9) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    return material


func _mesh_box(parent: Node3D, size: Vector3, position: Vector3, color: Color) -> MeshInstance3D:
    var mesh_instance := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh.material = _material(color)
    mesh_instance.mesh = mesh
    mesh_instance.position = position
    parent.add_child(mesh_instance)
    return mesh_instance


func _make_road(stage: Node3D) -> void:
    var road_center_y := ROAD_TOP_Y - 0.10
    _mesh_box(stage, Vector3(28.0, 0.20, 42.0), Vector3(0.0, road_center_y, -4.0), Color(0.11, 0.12, 0.13))
    for x: float in [-3.5, 3.5]:
        _mesh_box(stage, Vector3(0.10, 0.025, 40.0), Vector3(x, ROAD_TOP_Y + 0.02, -4.0), Color(0.84, 0.84, 0.80))
    var ground := StaticBody3D.new()
    ground.name = "RoadCollision"
    ground.collision_layer = 1
    ground.collision_mask = 1
    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(28.0, 0.20, 42.0)
    collision.shape = shape
    collision.position = Vector3(0.0, road_center_y, -4.0)
    ground.add_child(collision)
    stage.add_child(ground)


func _validate_all_models_grounded(stage: Node3D) -> int:
    var grounded := 0
    for model_id: String in ALL_MODEL_IDS:
        var visual := VISUAL_SCRIPT.new()
        visual.name = "GroundCheck_%s" % model_id
        visual.model_id = model_id
        visual.animate_wheels = false
        visual.position = Vector3(1000.0, 0.0, 1000.0)
        stage.add_child(visual)
        await process_frame
        var contract: Dictionary = visual.get_visual_contract()
        var contact_y := float(contract.get("ground_contact_y", INF))
        var target_y := float(contract.get("target_ground_y", 0.015))
        var wheel_count := int(contract.get("wheel_count", 0))
        if not is_finite(contact_y) or absf(contact_y - target_y) > 0.025 or wheel_count < 4:
            push_error("RGSDEV_GROUND_MOTION_FAIL model=%s contact=%.4f target=%.4f wheels=%d" % [model_id, contact_y, target_y, wheel_count])
            visual.queue_free()
            await process_frame
            return grounded
        grounded += 1
        visual.queue_free()
        await process_frame
    return grounded


func _spawn_drivable(stage: Node3D, model_id: String, x: float) -> Dictionary:
    var body := DRIVABLE_SCRIPT.new()
    body.name = "Motion_%s" % model_id
    body.collision_layer = 1
    body.collision_mask = 1
    body.position = Vector3(x, 0.0, 10.0)

    var collision := CollisionShape3D.new()
    collision.name = "CollisionShape3D"
    var shape := BoxShape3D.new()
    shape.size = CAR_COLLISION_SIZE
    collision.shape = shape
    body.add_child(collision)

    var visual := VISUAL_SCRIPT.new()
    visual.name = "RgsdevVisual"
    visual.model_id = model_id
    visual.animate_wheels = true
    body.add_child(visual)
    body.configure_archetype("car")
    stage.add_child(body)

    var controller := Node.new()
    controller.name = "ExternalDriver_%s" % model_id
    stage.add_child(controller)

    return {
        "body": body,
        "visual": visual,
        "controller": controller,
        "start": body.global_position,
        "model_id": model_id,
    }


func _run() -> void:
    var output_path := _arg("--output=", "/tmp/rgsdev_ground_motion_proof.png")
    var result_path := _arg("--result=", "/tmp/rgsdev_ground_motion_result.json")
    var engine_version := _engine_version()
    if engine_version != EXPECTED_ENGINE_VERSION:
        push_error("RGSDEV_GROUND_MOTION_FAIL engine=%s expected=%s" % [engine_version, EXPECTED_ENGINE_VERSION])
        quit(1)
        return

    root.size = Vector2i(1280, 720)
    root.content_scale_size = Vector2i(1280, 720)

    var stage := Node3D.new()
    stage.name = "RgsdevGroundMotionStage"
    root.add_child(stage)

    var world_environment := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.56, 0.67, 0.77)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.96, 0.98, 1.0)
    environment.ambient_light_energy = 0.78
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    world_environment.environment = environment
    stage.add_child(world_environment)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-48.0, -25.0, 0.0)
    sun.light_energy = 1.25
    sun.shadow_enabled = true
    stage.add_child(sun)

    _make_road(stage)

    var grounded_count := await _validate_all_models_grounded(stage)
    if grounded_count != ALL_MODEL_IDS.size():
        push_error("RGSDEV_GROUND_MOTION_FAIL grounded=%d expected=%d" % [grounded_count, ALL_MODEL_IDS.size()])
        quit(1)
        return

    var rows: Array[Dictionary] = []
    var lane_x := [-7.0, 0.0, 7.0]
    for index: int in range(MOTION_MODELS.size()):
        rows.append(_spawn_drivable(stage, MOTION_MODELS[index], lane_x[index]))

    for _frame: int in range(12):
        await physics_frame

    for row: Dictionary in rows:
        var visual: Node = row["visual"]
        var contract: Dictionary = visual.call("get_visual_contract")
        var contact_y := float(contract.get("ground_contact_y", INF))
        var target_y := float(contract.get("target_ground_y", ROAD_TOP_Y + 0.015))
        if not is_finite(contact_y) or absf(contact_y - target_y) > 0.025:
            push_error("RGSDEV_GROUND_MOTION_FAIL moving_model=%s contact=%.4f target=%.4f" % [str(row["model_id"]), contact_y, target_y])
            quit(1)
            return
        var body: Node = row["body"]
        var controller: Node = row["controller"]
        if not bool(body.call("assign_external_driver", controller)):
            push_error("RGSDEV_GROUND_MOTION_FAIL external_driver=%s" % str(row["model_id"]))
            quit(1)
            return
        body.call("set_external_drive_input", 0.72, 0.0, 0.0)

    for _frame: int in range(90):
        await physics_frame

    var result_rows: Array[Dictionary] = []
    for row: Dictionary in rows:
        var body := row["body"] as Node3D
        var visual: Node = row["visual"]
        body.call("set_external_drive_input", 0.0, 0.0, 1.0)
        var start: Vector3 = row["start"]
        var finish := body.global_position
        var distance := start.distance_to(finish)
        var forward_delta := start.z - finish.z
        var wheel_spin := absf(float(visual.get("_spin_angle")))
        if distance < 4.0 or forward_delta < 4.0 or wheel_spin < 0.15:
            push_error("RGSDEV_GROUND_MOTION_FAIL model=%s distance=%.3f forward=%.3f wheel_spin=%.3f" % [str(row["model_id"]), distance, forward_delta, wheel_spin])
            quit(1)
            return
        result_rows.append({
            "model_id": str(row["model_id"]),
            "distance_m": distance,
            "forward_delta_m": forward_delta,
            "wheel_spin_rad": wheel_spin,
        })
        _mesh_box(stage, Vector3(1.8, 0.03, 0.16), Vector3(start.x, ROAD_TOP_Y + 0.035, start.z), Color(0.95, 0.70, 0.12))
        var label := Label3D.new()
        label.text = "%s  %.1f m" % [str(row["model_id"]).to_upper(), distance]
        label.position = finish + Vector3(0.0, 2.25, 0.0)
        label.font_size = 34
        label.outline_size = 8
        label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        stage.add_child(label)

    for _frame: int in range(8):
        await process_frame

    var camera := Camera3D.new()
    camera.position = Vector3(18.0, 15.0, 24.0)
    camera.fov = 58.0
    stage.add_child(camera)
    camera.look_at(Vector3(0.0, 0.0, 1.0), Vector3.UP)
    camera.current = true

    for _frame: int in range(8):
        await process_frame
    await RenderingServer.frame_post_draw

    var image := root.get_texture().get_image()
    if image == null or image.is_empty():
        push_error("RGSDEV_GROUND_MOTION_FAIL empty_capture")
        quit(1)
        return
    var save_error := image.save_png(output_path)
    if save_error != OK:
        push_error("RGSDEV_GROUND_MOTION_FAIL save_error=%s" % error_string(save_error))
        quit(1)
        return

    var result := {
        "format": "grand-bruxelles-rgsdev-ground-motion-proof-v1",
        "engine_version": engine_version,
        "renderer": "gl_compatibility",
        "grounded_models": grounded_count,
        "grounded_expected": ALL_MODEL_IDS.size(),
        "moving_models": result_rows,
        "road_top_y": ROAD_TOP_Y,
        "capture": output_path,
    }
    var result_file := FileAccess.open(result_path, FileAccess.WRITE)
    if result_file == null:
        push_error("RGSDEV_GROUND_MOTION_FAIL cannot_write_result")
        quit(1)
        return
    result_file.store_string(JSON.stringify(result, "\t", true) + "\n")
    result_file.close()

    print("RGSDEV_GROUND_MOTION_OK grounded=%d moving=%d engine=%s output=%s" % [grounded_count, result_rows.size(), engine_version, output_path])
    quit(0)
