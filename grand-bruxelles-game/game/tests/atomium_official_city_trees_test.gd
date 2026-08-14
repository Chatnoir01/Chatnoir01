extends SceneTree

const TERRAIN_SCRIPT := preload("res://game/zones/laeken_jette/atomium_dtm_terrain.gd")
const HERO_SCRIPT := preload("res://game/zones/laeken_jette/atomium_hero_core.gd")
const TREES_SCRIPT := preload("res://game/zones/laeken_jette/atomium_official_city_trees.gd")
const OUTPUT_PATH := "res://artifacts/atomium/atomium_official_city_trees_ground_oblique.png"
const WIDTH := 1280
const HEIGHT := 960

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ATOMIUM_OFFICIAL_TREES_FAIL: %s" % message)
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

    var trees := TREES_SCRIPT.new()
    world.add_child(trees)

    # Regression: public-tree GeoJSON is absolute EPSG:31370, while the DTM
    # runtime is local metres about game_origin_e/game_origin_n. Prove that the
    # same conversion maps the Atomium's reconstructed Lambert coordinate back
    # to the already-validated local anchor before consuming any tree feature.
    var reconstructed_atomium_e := float(terrain.origin_e) + hero.anchor_position.x
    var reconstructed_atomium_n := float(terrain.origin_n) - hero.anchor_position.z
    var converted_anchor := trees.source_to_game_horizontal(terrain, reconstructed_atomium_e, reconstructed_atomium_n)
    if absf(converted_anchor.x - hero.anchor_position.x) > 0.001 or absf(converted_anchor.y - hero.anchor_position.z) > 0.001:
        _fail("Lambert-to-local conversion drifted: %s vs hero %s" % [converted_anchor, Vector2(hero.anchor_position.x, hero.anchor_position.z)])
        return

    if not trees.build_on_terrain(terrain):
        _fail("official tree context did not build")
        return
    if not trees.source_coordinate_conversion_verified:
        _fail("source coordinates were not converted from EPSG:31370")
        return
    if trees.source_feature_count != 8236:
        _fail("official source count drifted: %d" % trees.source_feature_count)
        return
    if trees.rendered_tree_count < 50:
        _fail("hero context selected too few trees: %d" % trees.rendered_tree_count)
        return
    if trees.source_dimensions_claimed or trees.collision_created:
        _fail("presentation-only trees acquired unsupported physical semantics")
        return
    for i: int in range(trees.rendered_tree_count):
        var p := trees.instance_position(i)
        if not terrain.contains_game_point(p.x, p.z):
            _fail("tree %d left official terrain" % i)
            return
        var sampled := terrain.sample_height(p.x, p.z)
        if absf(sampled - p.y) > 0.01:
            _fail("tree %d is not terrain anchored" % i)
            return
        if Vector2(p.x - hero.anchor_position.x, p.z - hero.anchor_position.z).length() > trees.hero_radius_m + 0.01:
            _fail("tree %d escaped hero radius" % i)
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

    for _frame: int in range(16):
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
    print("ATOMIUM_OFFICIAL_TREES_OK: source=%d rendered=%d radius_rejected=%d terrain_rejected=%d capture=%s" % [trees.source_feature_count, trees.rendered_tree_count, trees.radius_rejected_count, trees.terrain_rejected_count, OUTPUT_PATH])
    quit(0)
