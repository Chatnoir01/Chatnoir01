extends SceneTree

const TERRAIN_SCRIPT := preload("res://game/zones/laeken_jette/atomium_dtm_terrain.gd")
const HERO_SCRIPT := preload("res://game/zones/laeken_jette/atomium_hero_core.gd")
const REFLECTION_SCRIPT := preload("res://game/zones/laeken_jette/atomium_hero_reflection_environment.gd")
const MAIN_SCENE := preload("res://game/main.tscn")
const DIRECT_PRESENTATION_SCRIPT := preload("res://game/scripts/direct_spawn_presentation.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ATOMIUM_LANDCOVER_CONTEXT_FAIL: %s" % message)
    quit(1)

func _save_capture(viewport: Viewport, path: String) -> bool:
    for _frame: int in range(8):
        await process_frame
    RenderingServer.force_draw()
    await process_frame
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty():
        return false
    var absolute := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    return image.save_png(absolute) == OK

func _validate_context(context: Node) -> bool:
    return context != null \
        and bool(context.get("context_built")) \
        and str(context.get("source_feature_id")) == "LandCover.1038" \
        and str(context.get("source_code")) == "GB" \
        and str(context.get("source_crs")) == "EPSG:31370" \
        and float(context.get("source_area_m2")) > 54000.0 \
        and int(context.get("triangle_count")) > 100 \
        and not bool(context.get("material_photometry_resolved")) \
        and not bool(context.get("vegetation_geometry_resolved"))

func _run() -> void:
    var hero_viewport := SubViewport.new()
    hero_viewport.size = Vector2i(1280, 960)
    hero_viewport.own_world_3d = true
    hero_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(hero_viewport)
    var hero_world := Node3D.new()
    hero_viewport.add_child(hero_world)
    var terrain := TERRAIN_SCRIPT.new()
    terrain.build_collision = false
    hero_world.add_child(terrain)
    await process_frame
    await process_frame
    if not bool(terrain.get("terrain_loaded")):
        _fail("hero terrain missing")
        return
    var hero := HERO_SCRIPT.new()
    hero_world.add_child(hero)
    if not bool(hero.call("build_on_terrain", terrain)):
        _fail("hero failed")
        return
    var context := hero_world.get_node_or_null("AtomiumLandCoverContext")
    if not _validate_context(context):
        _fail("hero GB context source contract failed")
        return
    var reflection := REFLECTION_SCRIPT.new()
    hero_world.add_child(reflection)
    if not bool(reflection.call("build")):
        _fail("reflection environment failed")
        return
    var hero_camera := Camera3D.new()
    hero_camera.position = hero.anchor_position + Vector3(-185.0, 86.0, 235.0)
    hero_camera.fov = 48.0
    hero_camera.current = true
    hero_world.add_child(hero_camera)
    hero_camera.look_at(hero.anchor_position + Vector3(0.0, 50.0, 0.0), Vector3.UP)
    context.visible = false
    if not await _save_capture(hero_viewport, "res://artifacts/atomium/landcover_hero_before.png"):
        _fail("hero before capture failed")
        return
    context.visible = true
    if not await _save_capture(hero_viewport, "res://artifacts/atomium/landcover_hero_after.png"):
        _fail("hero after capture failed")
        return

    var direct_viewport := SubViewport.new()
    direct_viewport.size = Vector2i(1280, 720)
    direct_viewport.own_world_3d = true
    direct_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(direct_viewport)
    var main := MAIN_SCENE.instantiate()
    direct_viewport.add_child(main)
    await process_frame
    var player := main.get_node_or_null("Player")
    if player == null:
        _fail("direct player missing")
        return
    var presentation := DIRECT_PRESENTATION_SCRIPT.new()
    direct_viewport.add_child(presentation)
    if not bool(presentation.call("apply_to_player", player, PackedStringArray(["spawn=atomium"]))):
        _fail("direct presentation failed")
        return
    player.call("_apply_direct_spawn_from_user_args", PackedStringArray(["spawn=atomium"]))
    for _frame: int in range(12):
        await process_frame
    var direct_context := main.get_node_or_null("AtomiumLandCoverContext")
    if not _validate_context(direct_context):
        _fail("direct-player GB context source contract failed")
        return
    direct_context.visible = false
    if not await _save_capture(direct_viewport, "res://artifacts/atomium/landcover_player_before.png"):
        _fail("player before capture failed")
        return
    direct_context.visible = true
    if not await _save_capture(direct_viewport, "res://artifacts/atomium/landcover_player_after.png"):
        _fail("player after capture failed")
        return

    print("ATOMIUM_LANDCOVER_CONTEXT_OK: feature=LandCover.1038 code=GB area=54537.55 hero=1280x960 player=1280x720")
    quit(0)
