extends SceneTree

const TERRAIN_SCRIPT := preload("res://game/zones/laeken_jette/atomium_dtm_terrain.gd")
const HERO_SCRIPT := preload("res://game/zones/laeken_jette/atomium_hero_core.gd")
const OUTPUT_PATH := "res://artifacts/atomium/atomium_hero_ground_oblique.png"
const WIDTH := 1280
const HEIGHT := 960

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ATOMIUM_HERO_GROUND_OBLIQUE_FAIL: %s" % message)
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
    if hero.sphere_count != 9 or hero.tube_count != 20:
        _fail("source counts drifted")
        return
    if absf(hero.source_height_m - 102.0) > 0.001 or absf(hero.source_sphere_diameter_m - 18.0) > 0.001 or absf(hero.source_tube_diameter_m - 3.3) > 0.001:
        _fail("published dimensions drifted")
        return
    if hero.unresolved_support_pillars != 3:
        _fail("support-pillar blocker was lost")
        return
    var extent := hero.measured_vertical_extent()
    if absf(extent.x) > 0.001 or absf(extent.y - 102.0) > 0.001:
        _fail("hero vertical extent is not 0..102 m: %s" % extent)
        return
    var sampled_y := terrain.sample_height(hero.anchor_position.x, hero.anchor_position.z)
    if absf(sampled_y - hero.anchor_position.y) > 0.001:
        _fail("hero is not anchored to official DTM")
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
    camera.position = hero.anchor_position + Vector3(-185.0, 86.0, 235.0)
    camera.fov = 48.0
    camera.current = true
    world.add_child(camera)
    camera.look_at(hero.anchor_position + Vector3(0.0, 50.0, 0.0), Vector3.UP)
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
    print("ATOMIUM_HERO_GROUND_OBLIQUE_OK: spheres=%d tubes=%d extent=%.3f..%.3f anchor_y=%.3f unresolved_pillars=%d capture=%s" % [hero.sphere_count, hero.tube_count, extent.x, extent.y, hero.anchor_position.y, hero.unresolved_support_pillars, OUTPUT_PATH])
    quit(0)
