extends SceneTree

const TERRAIN_SCRIPT := preload("res://game/zones/laeken_jette/atomium_dtm_terrain.gd")
const HERO_SCRIPT := preload("res://game/zones/laeken_jette/atomium_hero_core.gd")
const REFLECTION_ENVIRONMENT_SCRIPT := preload("res://game/zones/laeken_jette/atomium_hero_reflection_environment.gd")
const WIDTH := 1280
const HEIGHT := 720

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ATOMIUM_CURRENT_BASIN_CAPTURE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    var output := "/tmp/atomium-current-basin.png"
    if not args.is_empty():
        output = str(args[0])

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
        _fail("Atomium hero did not build")
        return

    var environment := REFLECTION_ENVIRONMENT_SCRIPT.new()
    world.add_child(environment)
    if not environment.build():
        _fail("reflection environment did not build")
        return

    # Current-site QA camera, not the historical Commons benchmark camera.
    # It deliberately sees the 2024 basin footprint and Atomium in one frame.
    var basin_game := Vector3(250.485776, terrain.sample_height(250.485776, -6674.995847), -6674.995847)
    var camera := Camera3D.new()
    camera.position = basin_game + Vector3(-95.0, 42.0, -125.0)
    camera.fov = 52.0
    camera.current = true
    world.add_child(camera)
    camera.look_at(Vector3(238.0, 18.0, -6607.0), Vector3.UP)

    for _frame: int in range(16):
        await process_frame
    RenderingServer.force_draw()
    await process_frame
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        _fail("capture invalid")
        return
    if image.save_png(output) != OK:
        _fail("capture save failed")
        return
    print("ATOMIUM_CURRENT_BASIN_CAPTURE_OK: output=%s camera=(%.3f,%.3f,%.3f) fov=52.0 current_site_only=true historical_match=false" % [output, camera.position.x, camera.position.y, camera.position.z])
    quit(0)
