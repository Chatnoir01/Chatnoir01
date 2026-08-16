extends SceneTree

const TERRAIN_SCRIPT := preload("res://game/zones/laeken_jette/atomium_dtm_terrain.gd")
const HERO_SCRIPT := preload("res://game/zones/laeken_jette/atomium_hero_core.gd")
const REFLECTION_SCRIPT := preload("res://game/zones/laeken_jette/atomium_hero_reflection_environment.gd")
const WIDTH := 1280
const HEIGHT := 720

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ATOMIUM_SPHERE_SKIN_CAPTURE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    var output_path := "/tmp/atomium-sphere-skin.png"
    if not args.is_empty() and not args[0].strip_edges().is_empty():
        output_path = args[0]

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
        _fail("terrain did not load")
        return

    var hero := HERO_SCRIPT.new()
    world.add_child(hero)
    if not bool(hero.call("build_on_terrain", terrain)):
        _fail("hero did not build")
        return
    if int(hero.get("sphere_count")) != 9 or int(hero.get("tube_count")) != 20:
        _fail("hero topology drifted")
        return

    var reflection := REFLECTION_SCRIPT.new()
    world.add_child(reflection)
    if not bool(reflection.call("build")):
        _fail("reflection environment did not build")
        return

    var camera := Camera3D.new()
    camera.position = hero.get("anchor_position") + Vector3(-118.0, 42.0, 152.0)
    camera.fov = 43.0
    camera.current = true
    world.add_child(camera)
    camera.look_at(hero.get("anchor_position") + Vector3(0.0, 50.0, 0.0), Vector3.UP)

    for _frame: int in range(20):
        await process_frame
    RenderingServer.force_draw()
    await process_frame

    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty():
        _fail("capture image missing")
        return
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        _fail("capture dimensions drifted")
        return

    var absolute_output := output_path
    if output_path.begins_with("res://") or output_path.begins_with("user://"):
        absolute_output = ProjectSettings.globalize_path(output_path)
    DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
    if image.save_png(absolute_output) != OK:
        _fail("could not save capture")
        return

    print("ATOMIUM_SPHERE_SKIN_CAPTURE_OK: %s camera=(%.3f,%.3f,%.3f) fov=%.1f resolution=%dx%d" % [absolute_output, camera.position.x, camera.position.y, camera.position.z, camera.fov, WIDTH, HEIGHT])
    quit(0)
