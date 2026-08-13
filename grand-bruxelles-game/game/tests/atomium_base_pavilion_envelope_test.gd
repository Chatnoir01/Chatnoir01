extends SceneTree

const TERRAIN_SCRIPT := preload("res://game/zones/laeken_jette/atomium_dtm_terrain.gd")
const HERO_SCRIPT := preload("res://game/zones/laeken_jette/atomium_hero_core.gd")
const ENVELOPE_SCRIPT := preload("res://game/zones/laeken_jette/atomium_base_pavilion_envelope.gd")
const OUTPUT_PATH := "res://artifacts/atomium/atomium_base_pavilion_envelope.png"
const WIDTH := 1280
const HEIGHT := 960

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ATOMIUM_BASE_PAVILION_ENVELOPE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    var world := Node3D.new()
    viewport.add_child(world)

    var terrain := TERRAIN_SCRIPT.new()
    terrain.build_collision = false
    world.add_child(terrain)
    await process_frame
    await process_frame
    if not terrain.terrain_loaded:
        _fail("terrain did not load")
        return

    var hero := HERO_SCRIPT.new()
    world.add_child(hero)
    if not hero.build_on_terrain(terrain):
        _fail("hero core did not build")
        return

    var envelope := ENVELOPE_SCRIPT.new()
    world.add_child(envelope)
    if not envelope.build_on_terrain(terrain):
        _fail("pavilion envelope did not build")
        return
    if not envelope.plan_only:
        _fail("QA envelope was promoted to pavilion volume")
        return
    if absf(envelope.source_diameter_m - 26.0) > 0.001:
        _fail("official pavilion diameter drifted")
        return
    var measured := envelope.measured_plan_diameter()
    if absf(measured - 26.0) > 0.02:
        _fail("measured plan diameter is not 26 m: %.4f" % measured)
        return
    if envelope.sampled_points.size() < 24:
        _fail("plan envelope is under-sampled")
        return
    if envelope.get_child_count() != 1:
        _fail("QA envelope created unexpected geometry")
        return
    var outline := envelope.get_child(0)
    if not outline is MeshInstance3D or not outline.name.ends_with("QAOnly"):
        _fail("plan-only marker lost")
        return

    var environment := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.62, 0.69, 0.78)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.88, 0.90, 0.93)
    env.ambient_light_energy = 0.62
    environment.environment = env
    world.add_child(environment)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-46.0, -28.0, 0.0)
    sun.light_energy = 1.25
    sun.shadow_enabled = true
    world.add_child(sun)

    var camera := Camera3D.new()
    camera.position = hero.anchor_position + Vector3(-125.0, 58.0, 150.0)
    camera.fov = 44.0
    camera.current = true
    world.add_child(camera)
    camera.look_at(hero.anchor_position + Vector3(0.0, 24.0, 0.0), Vector3.UP)

    for _frame: int in range(12):
        await process_frame
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

    print("ATOMIUM_BASE_PAVILION_ENVELOPE_OK: source_diameter=%.3f measured_diameter=%.3f points=%d plan_only=true capture=%s" % [envelope.source_diameter_m, measured, envelope.sampled_points.size(), OUTPUT_PATH])
    quit(0)
