extends SceneTree

const TERRAIN_SCRIPT := preload("res://game/zones/laeken_jette/atomium_dtm_terrain.gd")
const HERO_SCRIPT := preload("res://game/zones/laeken_jette/atomium_hero_core.gd")
const REFLECTION_SCRIPT := preload("res://game/zones/laeken_jette/atomium_hero_reflection_environment.gd")
const CONTEXT_SCRIPT := preload("res://game/zones/laeken_jette/atomium_street_surface_context.gd")
const OUTPUT_PATH := "res://artifacts/atomium/atomium_street_surface_context.png"
const WIDTH := 1280
const HEIGHT := 960

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ATOMIUM_STREETSURFACE_CONTEXT_FAIL: %s" % message)
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
    if not bool(terrain.get("terrain_loaded")):
        _fail("official DTM did not load")
        return

    var hero := HERO_SCRIPT.new()
    world.add_child(hero)
    if not bool(hero.call("build_on_terrain", terrain)):
        _fail("hero did not build")
        return

    var reflection := REFLECTION_SCRIPT.new()
    world.add_child(reflection)
    if not bool(reflection.call("build")):
        _fail("reflection environment did not build")
        return

    var context := CONTEXT_SCRIPT.new()
    world.add_child(context)
    if not bool(context.call("build_on_terrain", terrain)):
        _fail("StreetSurface context did not build")
        return
    if int(context.get("source_feature_count")) != 84:
        _fail("extracted source feature count drifted")
        return
    if int(context.get("rendered_feature_count")) < 20 or int(context.get("triangle_count")) < 50:
        _fail("insufficient source-backed public-realm geometry survived DTM clipping")
        return
    if not bool(context.get("presentation_material_only")) or bool(context.get("collision_authored")):
        _fail("presentation/source boundary drifted")
        return

    var camera := Camera3D.new()
    var anchor: Vector3 = terrain.get("atomium_game_position")
    camera.position = anchor + Vector3(-185.0, 86.0, 235.0)
    camera.fov = 48.0
    camera.current = true
    world.add_child(camera)
    camera.look_at(anchor + Vector3(0.0, 50.0, 0.0), Vector3.UP)

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

    print("ATOMIUM_STREETSURFACE_CONTEXT_OK: source=%d rendered=%d triangles=%d clipped=%d capture=%s size=%dx%d" % [int(context.get("source_feature_count")), int(context.get("rendered_feature_count")), int(context.get("triangle_count")), int(context.get("skipped_outside_dtm_triangles")), OUTPUT_PATH, WIDTH, HEIGHT])
    quit(0)
