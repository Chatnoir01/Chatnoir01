extends SceneTree

const SCENE_PATH := "res://game/zones/laeken_jette/laeken_jette.tscn"
const OUTPUT_PATH := "res://palais5_facade_qa.png"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("LAEKEN_PALAIS5_CAPTURE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var packed := load(SCENE_PATH) as PackedScene
    if packed == null:
        _fail("Laeken/Jette scene failed to load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    root.size = Vector2i(1280, 720)
    for _i in range(50):
        await process_frame

    var pass_node := scene.get_node_or_null("Palais5HeroPass")
    if pass_node == null or not bool(pass_node.get("hero_ready")):
        _fail("Palais 5 hero geometry is not ready")
        return
    var hero := pass_node.get_node_or_null("Palais5HeroGeometry") as Node3D
    if hero == null:
        _fail("Palais5HeroGeometry root missing")
        return
    var terrain = scene.get_node_or_null("LaekenTerrain")
    if terrain == null or not bool(terrain.get("terrain_loaded")):
        _fail("Laeken terrain unavailable")
        return

    # Diagnostic QA camera only. It is derived from the built facade transform and
    # is not claimed to reproduce any historical or contemporary source photo.
    var outward := -hero.global_transform.basis.z.normalized()
    var camera_ground_point := hero.global_position + outward * 92.0
    var camera_ground_y := float(terrain.call("sample_height", camera_ground_point.x, camera_ground_point.z))
    var camera_position := Vector3(camera_ground_point.x, maxf(camera_ground_y + 8.0, hero.global_position.y + 18.0), camera_ground_point.z)
    var target_position := hero.global_position + hero.global_transform.basis.z.normalized() * 9.0 + Vector3.UP * 14.0

    # Neutral QA-only illumination so dark back-facing materials are inspectable.
    # This does not modify the runtime zone lighting or material values.
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.55, 0.58, 0.62, 1.0)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.88, 0.90, 0.94, 1.0)
    environment.ambient_light_energy = 1.35
    var world_environment := WorldEnvironment.new()
    world_environment.name = "Palais5QAEnvironment"
    world_environment.environment = environment
    scene.add_child(world_environment)

    var key_light := DirectionalLight3D.new()
    key_light.name = "Palais5QAKeyLight"
    key_light.light_energy = 1.8
    key_light.shadow_enabled = true
    key_light.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
    scene.add_child(key_light)

    var fill_light := DirectionalLight3D.new()
    fill_light.name = "Palais5QAFillLight"
    fill_light.light_energy = 0.85
    fill_light.shadow_enabled = false
    fill_light.rotation_degrees = Vector3(-30.0, 145.0, 0.0)
    scene.add_child(fill_light)

    var camera := Camera3D.new()
    camera.name = "Palais5FacadeQACamera"
    camera.fov = 54.0
    camera.near = 0.05
    camera.far = 6000.0
    scene.add_child(camera)
    camera.global_position = camera_position
    camera.look_at(target_position, Vector3.UP)
    camera.current = true

    for _i in range(12):
        await process_frame
    RenderingServer.force_draw()
    await process_frame
    await process_frame

    var image := root.get_texture().get_image()
    if image == null or image.is_empty():
        _fail("empty viewport image")
        return
    if image.get_width() != 1280 or image.get_height() != 720:
        _fail("unexpected capture resolution")
        return
    var error := image.save_png(OUTPUT_PATH)
    if error != OK:
        _fail("save_png failed: %s" % error)
        return

    print("LAEKEN_PALAIS5_CAPTURE_OK: output=%s camera=%s camera_ground=%.3f target=%s fov=%.1f" % [OUTPUT_PATH, camera_position, camera_ground_y, target_position, camera.fov])
    scene.queue_free()
    await process_frame
    quit(0)
