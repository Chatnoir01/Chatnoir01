extends SceneTree

const WIDTH := 1024
const HEIGHT := 720
const OUTPUT_PATH := "res://artifacts/npc/npc_visual_profile.png"
const HUMANOID_VISUAL_SCRIPT := preload("res://game/scripts/humanoid_visual.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("NPC_VISUAL_PROFILE_CAPTURE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var viewport := SubViewport.new()
    viewport.name = "NpcVisualProfileViewport"
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)

    var scene := Node3D.new()
    scene.name = "NpcVisualProfileWitness"
    viewport.add_child(scene)

    var environment := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.72, 0.76, 0.79, 1.0)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.78, 0.81, 0.84, 1.0)
    env.ambient_light_energy = 0.75
    environment.environment = env
    scene.add_child(environment)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
    sun.light_energy = 1.15
    sun.shadow_enabled = true
    scene.add_child(sun)

    for index: int in range(4):
        var agent := NpcAgent.new()
        agent.name = "WitnessCivilian_%d" % index
        agent.role = NpcBehaviorModel.Role.CIVILIAN
        agent.variation_seed = 3100 + index
        agent.position = Vector3(-2.25 + float(index) * 1.5, 0.0, 0.0)
        scene.add_child(agent)

        var visual := HUMANOID_VISUAL_SCRIPT.new() as Node3D
        visual.name = "VisibleHumanoid"
        visual.position.y = 0.90
        agent.add_child(visual)

    var camera := Camera3D.new()
    camera.name = "NpcVisualProfileCamera"
    camera.position = Vector3(0.0, 1.45, 6.2)
    camera.fov = 42.0
    camera.look_at_from_position(camera.position, Vector3(0.0, 1.05, 0.0), Vector3.UP)
    camera.current = true
    scene.add_child(camera)

    for _frame: int in range(24):
        await process_frame
    RenderingServer.force_draw()
    await process_frame

    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty():
        _fail("captured viewport is empty")
        return
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        _fail("unexpected capture size %dx%d" % [image.get_width(), image.get_height()])
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

    print("NPC_VISUAL_PROFILE_CAPTURE_OK: %s (%dx%d)" % [OUTPUT_PATH, WIDTH, HEIGHT])
    viewport.queue_free()
    quit(0)
