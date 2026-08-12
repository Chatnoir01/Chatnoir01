extends SceneTree

const TERRAIN_SCRIPT := preload("res://game/zones/laeken_jette/atomium_dtm_terrain.gd")
const OUTPUT_PATH := "res://artifacts/atomium/atomium_dtm_ground_oblique.png"
const WIDTH := 1280
const HEIGHT := 960

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ATOMIUM_DTM_RUNTIME_FAIL: %s" % message)
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
    terrain.build_collision = true
    world.add_child(terrain)
    await process_frame
    await process_frame

    if not terrain.terrain_loaded:
        _fail("terrain did not load")
        return
    if terrain.width != 257 or terrain.height != 257:
        _fail("unexpected DTM dimensions")
        return
    if terrain.valid_sample_count != 65577 or terrain.invalid_sample_count != 472:
        _fail("sample counts drifted")
        return
    if terrain.triangle_count < 120000:
        _fail("too few valid terrain triangles: %d" % terrain.triangle_count)
        return
    if not terrain.contains_game_point(terrain.atomium_game_position.x, terrain.atomium_game_position.z):
        _fail("Atomium reference is outside valid terrain")
        return
    if absf(terrain.atomium_game_position.y) > 1.0:
        _fail("Atomium relative ground anchor drifted: %.3f m" % terrain.atomium_game_position.y)
        return
    if terrain.get_node_or_null("OfficialAtomiumDTMMesh") == null:
        _fail("runtime mesh missing")
        return
    if terrain.get_node_or_null("OfficialAtomiumDTMCollision") == null:
        _fail("runtime collision missing")
        return

    var environment := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.63, 0.69, 0.76)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.88, 0.9, 0.92)
    env.ambient_light_energy = 0.65
    environment.environment = env
    world.add_child(environment)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
    sun.light_energy = 1.2
    sun.shadow_enabled = true
    world.add_child(sun)

    # QA-only reference marker; not production Atomium geometry.
    var marker := MeshInstance3D.new()
    marker.name = "AtomiumReferenceMarker"
    var marker_mesh := SphereMesh.new()
    marker_mesh.radius = 4.0
    marker_mesh.height = 8.0
    marker.mesh = marker_mesh
    marker.position = terrain.atomium_game_position + Vector3(0.0, 4.0, 0.0)
    world.add_child(marker)

    var camera := Camera3D.new()
    camera.position = terrain.atomium_game_position + Vector3(-210.0, 115.0, 260.0)
    camera.fov = 52.0
    camera.current = true
    world.add_child(camera)
    camera.look_at(terrain.atomium_game_position + Vector3(0.0, 8.0, 0.0), Vector3.UP)

    for _frame: int in range(12):
        await process_frame
    RenderingServer.force_draw()
    await process_frame

    var texture := viewport.get_texture()
    if texture == null:
        _fail("capture texture missing")
        return
    var image := texture.get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        _fail("capture invalid")
        return
    var absolute_output := ProjectSettings.globalize_path(OUTPUT_PATH)
    DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
    var error := image.save_png(absolute_output)
    if error != OK:
        _fail("capture save failed: %s" % error_string(error))
        return

    print("ATOMIUM_DTM_RUNTIME_OK: triangles=%d atomium_relative_y=%.3f capture=%s" % [terrain.triangle_count, terrain.atomium_game_position.y, OUTPUT_PATH])
    quit(0)
