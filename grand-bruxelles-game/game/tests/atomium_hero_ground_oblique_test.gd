extends SceneTree

const TERRAIN_SCRIPT := preload("res://game/zones/laeken_jette/atomium_dtm_terrain.gd")
const HERO_SCRIPT := preload("res://game/zones/laeken_jette/atomium_hero_core.gd")
const REFLECTION_ENVIRONMENT_SCRIPT := preload("res://game/zones/laeken_jette/atomium_hero_reflection_environment.gd")
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

    var first_sphere: MeshInstance3D = null
    var first_tube: MeshInstance3D = null
    for child: Node in hero.get_children():
        if child is MeshInstance3D and child.name.begins_with("Sphere_") and first_sphere == null:
            first_sphere = child as MeshInstance3D
        elif child is MeshInstance3D and child.name.begins_with("Tube_") and first_tube == null:
            first_tube = child as MeshInstance3D
    if first_sphere == null or not first_sphere.mesh is SphereMesh:
        _fail("sphere presentation mesh missing")
        return
    if first_tube == null or not first_tube.mesh is CylinderMesh:
        _fail("tube presentation mesh missing")
        return
    var sphere_mesh := first_sphere.mesh as SphereMesh
    var tube_mesh := first_tube.mesh as CylinderMesh
    if sphere_mesh.radial_segments < 48 or sphere_mesh.rings < 24:
        _fail("sphere tessellation below rendering contract")
        return
    if tube_mesh.radial_segments < 32:
        _fail("tube tessellation below rendering contract")
        return
    if not sphere_mesh.material is StandardMaterial3D:
        _fail("sphere stainless material missing")
        return
    var sphere_material := sphere_mesh.material as StandardMaterial3D
    if sphere_material.metallic < 0.9 or sphere_material.roughness > 0.2:
        _fail("sphere material no longer reads as bright stainless presentation")
        return
    if sphere_material.albedo_color.r < 0.78 or sphere_material.albedo_color.g < 0.78 or sphere_material.albedo_color.b < 0.78:
        _fail("sphere stainless presentation is too dark")
        return

    var extent := hero.measured_vertical_extent()
    if absf(extent.x) > 0.001 or absf(extent.y - 102.0) > 0.001:
        _fail("hero vertical extent is not 0..102 m: %s" % extent)
        return
    var sampled_y := terrain.sample_height(hero.anchor_position.x, hero.anchor_position.z)
    if absf(sampled_y - hero.anchor_position.y) > 0.001:
        _fail("hero is not anchored to official DTM")
        return

    var reflection_environment := REFLECTION_ENVIRONMENT_SCRIPT.new()
    world.add_child(reflection_environment)
    if not reflection_environment.build():
        _fail("deterministic reflection environment did not build")
        return
    if not reflection_environment.reflection_source_is_sky:
        _fail("stainless hero reflections are not sourced from the sky")
        return
    if not reflection_environment.authored_non_photometric:
        _fail("reflection environment lost non-photometric presentation disclaimer")
        return
    if reflection_environment.world_environment == null or reflection_environment.sun == null:
        _fail("reflection environment nodes missing")
        return
    var env: Environment = reflection_environment.world_environment.environment
    if env == null or env.background_mode != Environment.BG_SKY:
        _fail("hero environment no longer uses sky background")
        return
    if env.ambient_light_source != Environment.AMBIENT_SOURCE_SKY:
        _fail("hero ambient light is not sourced from sky")
        return
    if env.reflected_light_source != Environment.REFLECTION_SOURCE_SKY:
        _fail("hero reflected light is not sourced from sky")
        return

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
    print("ATOMIUM_HERO_GROUND_OBLIQUE_OK: spheres=%d tubes=%d extent=%.3f..%.3f anchor_y=%.3f sphere_segments=%d sphere_rings=%d tube_segments=%d metallic=%.2f roughness=%.2f sky_reflection=%s authored_non_photometric=%s unresolved_pillars=%d capture=%s" % [hero.sphere_count, hero.tube_count, extent.x, extent.y, hero.anchor_position.y, sphere_mesh.radial_segments, sphere_mesh.rings, tube_mesh.radial_segments, sphere_material.metallic, sphere_material.roughness, str(reflection_environment.reflection_source_is_sky), str(reflection_environment.authored_non_photometric), hero.unresolved_support_pillars, OUTPUT_PATH])
    quit(0)
