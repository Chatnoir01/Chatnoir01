extends SceneTree

const TERRAIN_SCRIPT := preload("res://game/zones/laeken_jette/atomium_dtm_terrain.gd")
const BASIN_SCRIPT := preload("res://game/zones/laeken_jette/atomium_current_basin_footprint.gd")
const EXPECTED_TRIANGLES := 704

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ATOMIUM_CURRENT_BASIN_FOOTPRINT_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var world := Node3D.new()
    root.add_child(world)
    var terrain := TERRAIN_SCRIPT.new()
    terrain.build_collision = false
    world.add_child(terrain)
    await process_frame
    await process_frame
    if not terrain.terrain_loaded:
        _fail("official DTM did not load")
        return

    var basin := BASIN_SCRIPT.new()
    world.add_child(basin)
    if not basin.build_on_terrain(terrain):
        _fail("current basin footprint did not build")
        return
    if basin.source_crs != "EPSG:31370":
        _fail("source CRS drifted")
        return
    if basin.center_epsg.distance_to(Vector2(148118.780004, 176213.619996)) > 0.001:
        _fail("orthophoto circle centre drifted")
        return
    if absf(basin.radius_m - 26.944) > 0.001 or absf(basin.radius_uncertainty_m - 0.8) > 0.001:
        _fail("orthophoto circle radius/uncertainty drifted")
        return
    if basin.triangle_count != EXPECTED_TRIANGLES:
        _fail("smooth circular tessellation drifted: %d" % basin.triangle_count)
        return
    if not basin.presentation_only_surface:
        _fail("presentation-only disclaimer was lost")
        return
    if basin.water_level_resolved or basin.jet_geometry_resolved or basin.historical_photo_match_alignment_resolved:
        _fail("unresolved geometry/history was accidentally promoted")
        return
    if basin.historical_axis_offset_m < 80.0:
        _fail("historical camera-axis blocker was lost")
        return
    if basin.get_child_count() != 1 or not basin.get_child(0) is MeshInstance3D:
        _fail("footprint mesh missing")
        return
    var instance := basin.get_child(0) as MeshInstance3D
    if instance.name != "OfficialCurrentAtomiumBasinFootprint" or instance.mesh == null:
        _fail("footprint mesh identity invalid")
        return
    var expected_game := Vector2(250.485776, -6674.995847)
    var transformed_game := Vector2(
        basin.center_epsg.x - float(terrain.origin_e),
        -(basin.center_epsg.y - float(terrain.origin_n))
    )
    if transformed_game.distance_to(expected_game) > 0.01:
        _fail("EPSG31370 -> project X/Z transform drifted: %s" % transformed_game)
        return
    var centre_y := terrain.sample_height(transformed_game.x, transformed_game.y)
    if centre_y < -20.0 or centre_y > 30.0:
        _fail("basin footprint is outside valid Atomium DTM elevation range")
        return

    print("ATOMIUM_CURRENT_BASIN_FOOTPRINT_OK: center_epsg=(%.3f,%.3f) radius=%.3f uncertainty=%.3f triangles=%d game_xz=(%.3f,%.3f) centre_y=%.3f historical_axis_offset=%.3f" % [basin.center_epsg.x, basin.center_epsg.y, basin.radius_m, basin.radius_uncertainty_m, basin.triangle_count, transformed_game.x, transformed_game.y, centre_y, basin.historical_axis_offset_m])
    quit(0)
