extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const OUTPUT_PATH := "res://artifacts/qa/ixelles_east_dtm_seam.png"
const SEED_SCRIPT := preload("res://game/zones/ixelles/ixelles_streamed_microslice.gd")
const EAST_SCRIPT := preload("res://game/scripts/brussels_source_dtm_streamed_cell.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("IXELLES_EAST_DTM_SEAM_CAPTURE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var viewport := SubViewport.new()
    viewport.name = "IxellesEastDtmSeamViewport"
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)

    var world := Node3D.new()
    viewport.add_child(world)

    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.55, 0.68, 0.82, 1.0)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.82, 0.86, 0.92, 1.0)
    environment.ambient_light_energy = 0.7
    var world_environment := WorldEnvironment.new()
    world_environment.environment = environment
    world.add_child(world_environment)

    var sunlight := DirectionalLight3D.new()
    sunlight.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
    sunlight.light_energy = 1.15
    sunlight.shadow_enabled = true
    world.add_child(sunlight)

    var seed = SEED_SCRIPT.new()
    seed.name = "SeedIxellesDtm"
    seed.build_collision = false
    world.add_child(seed)

    var east = EAST_SCRIPT.new()
    east.name = "EastIxellesDtm"
    east.manifest_path = "res://data/urbis/remaining_brussels/cells/bxl-e149500-n169000-s500/manifest.json"
    east.runtime_cell_path = "res://data/urbis/remaining_brussels/cells/bxl-e149500-n169000-s500/runtime/cell.game.json"
    east.runtime_network_path = "res://data/urbis/remaining_brussels/cells/bxl-e149500-n169000-s500/runtime/network.game.json"
    east.terrain_path = "res://data/terrain/ixelles/bxl-e149500-n169000-s500_dtm_2m.game.json"
    east.shared_datum_path = "res://data/terrain/ixelles/ixelles_shared_vertical_datum.game.json"
    east.build_collision = false
    world.add_child(east)

    for _frame: int in range(180):
        await process_frame
        if bool(seed.get("runtime_loaded")) and bool(east.get("runtime_loaded")):
            break
    if not bool(seed.get("runtime_loaded")) or not bool(east.get("runtime_loaded")):
        _fail("seed/east streamed terrain did not become ready")
        return

    var seed_buildings := seed.find_child("StrongSourceBackedIxellesBuildings", true, false) as Node3D
    if seed_buildings != null:
        seed_buildings.visible = false

    var seam_target: Vector3 = east.lambert_to_game(149500.0, 169250.0)
    seam_target.y = east.sample_height(seam_target.x, seam_target.z)

    var camera := Camera3D.new()
    camera.name = "IxellesEastDtmSeamCamera"
    camera.position = seam_target + Vector3(-175.0, 95.0, 175.0)
    camera.fov = 58.0
    camera.current = true
    world.add_child(camera)
    camera.look_at(seam_target + Vector3(35.0, 0.0, -25.0), Vector3.UP)

    for _frame: int in range(20):
        await process_frame
    RenderingServer.force_draw()
    await process_frame

    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty():
        _fail("captured viewport is empty")
        return
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        _fail("unexpected capture dimensions")
        return

    var absolute_output := ProjectSettings.globalize_path(OUTPUT_PATH)
    var dir_error := DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
    if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
        _fail("could not create capture directory")
        return
    var save_error := image.save_png(absolute_output)
    if save_error != OK:
        _fail("could not save seam capture: %s" % error_string(save_error))
        return

    print("IXELLES_EAST_DTM_SEAM_CAPTURE_OK: %s seam_y=%.6f east_pieces=%d" % [OUTPUT_PATH, seam_target.y, int(east.get("street_surface_intersection_piece_count"))])
    viewport.queue_free()
    quit(0)
