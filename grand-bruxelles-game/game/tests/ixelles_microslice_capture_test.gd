extends SceneTree

const SLICE_SCRIPT := preload("res://game/zones/ixelles/ixelles_microslice.gd")
const OUTPUT_PATH := "res://artifacts/ixelles/ixelles_place_stephanie_foundation.png"
const WIDTH := 1280
const HEIGHT := 960

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("IXELLES_MICROSLICE_CAPTURE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)

    var world := Node3D.new()
    viewport.add_child(world)
    var slice := SLICE_SCRIPT.new()
    slice.build_collision = false
    world.add_child(slice)
    await process_frame
    await process_frame
    if not slice.runtime_loaded:
        _fail("runtime slice did not load")
        return

    var environment := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.66, 0.72, 0.79)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.86, 0.89, 0.92)
    env.ambient_light_energy = 0.72
    environment.environment = env
    world.add_child(environment)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-48.0, -34.0, 0.0)
    sun.light_energy = 1.15
    sun.shadow_enabled = true
    world.add_child(sun)

    # Official StreetAxes place Place Stephanie around x=735..768 / z=927..942.
    # This is a deterministic presentation camera only, not a surveyed photo pose.
    var camera := Camera3D.new()
    var camera_x := 724.0
    var camera_z := 967.0
    var target_x := 751.0
    var target_z := 930.0
    var camera_ground := slice.sample_height(camera_x, camera_z)
    var target_ground := slice.sample_height(target_x, target_z)
    camera.position = Vector3(camera_x, camera_ground + 4.2, camera_z)
    camera.fov = 52.0
    camera.current = true
    world.add_child(camera)
    camera.look_at(Vector3(target_x, target_ground + 1.4, target_z), Vector3.UP)

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
    print("IXELLES_MICROSLICE_CAPTURE_OK: cell=%s camera=(%.3f,%.3f,%.3f) target=(%.3f,%.3f,%.3f) streets=%d buildings=%d skipped=%d capture=%s" % [slice.cell_id, camera.position.x, camera.position.y, camera.position.z, target_x, target_ground + 1.4, target_z, slice.street_surface_count, slice.building_count, slice.skipped_unapproved_height_buildings, OUTPUT_PATH])
    quit(0)
