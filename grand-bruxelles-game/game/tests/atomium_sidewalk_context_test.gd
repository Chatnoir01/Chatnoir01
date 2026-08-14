extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const DIRECT_PRESENTATION_SCRIPT := preload("res://game/scripts/direct_spawn_presentation.gd")
const SIDEWALK_SCRIPT := preload("res://game/zones/laeken_jette/atomium_sidewalk_context.gd")
const LOCKED_SHA := "a1b962ef218c63925fd219e011c48c8a45faf36d32ec6ab7190833c5734861ca"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ATOMIUM_SIDEWALK_CONTEXT_FAIL: %s" % message)
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

func _run() -> void:
    var viewport := SubViewport.new()
    viewport.size = Vector2i(1280, 720)
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    var main := MAIN_SCENE.instantiate()
    viewport.add_child(main)
    await process_frame
    var player := main.get_node_or_null("Player")
    if player == null:
        _fail("direct player missing")
        return
    var presentation := DIRECT_PRESENTATION_SCRIPT.new()
    viewport.add_child(presentation)
    if not bool(presentation.call("apply_to_player", player, PackedStringArray(["spawn=atomium"]))):
        _fail("direct presentation failed")
        return
    player.call("_apply_direct_spawn_from_user_args", PackedStringArray(["spawn=atomium"]))
    for _frame: int in range(16):
        await process_frame
    var terrain := main.get_node_or_null("AtomiumDirectTerrain")
    if terrain == null or not bool(terrain.get("terrain_loaded")):
        _fail("actual direct-spawn terrain missing")
        return
    var hero := main.get_node_or_null("AtomiumDirectHero")
    if hero == null:
        _fail("actual direct-spawn hero missing")
        return

    var context := SIDEWALK_SCRIPT.new()
    context.name = "AtomiumSidewalkContextAB"
    viewport.add_child(context)
    if not bool(context.call("build_for_world", main, terrain)):
        _fail("sidewalk context failed to build")
        return
    if str(context.get("source_geometry_sha256")) != LOCKED_SHA:
        _fail("source geometry SHA drift")
        return
    if int(context.get("source_feature_count")) != 9 or int(context.get("selector_count")) != 427:
        _fail("locked source/selector contract drift")
        return
    if int(context.get("triangle_count")) <= 0 or int(context.get("triangle_count")) >= 427:
        _fail("valid DTM triangle count outside expected no-data/GreenBlock bounds")
        return
    if int(context.get("excluded_green_triangle_count")) <= 0:
        _fail("#289 Green Block overlap was not excluded")
        return
    if bool(context.get("material_photometry_resolved")) or bool(context.get("curb_geometry_resolved")) or bool(context.get("markings_resolved")) or bool(context.get("paving_subtype_resolved")):
        _fail("runtime claims unsupported sidewalk detail")
        return

    context.call("set_context_visible", false)
    if not await _save_capture(viewport, "res://artifacts/atomium/sidewalk_player_before.png"):
        _fail("player before capture failed")
        return
    context.call("set_context_visible", true)
    if not await _save_capture(viewport, "res://artifacts/atomium/sidewalk_player_after.png"):
        _fail("player after capture failed")
        return
    var camera := player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if camera == null or absf(camera.fov - 48.0) > 0.001:
        _fail("#254 48-degree direct-spawn framing drifted")
        return
    print("ATOMIUM_SIDEWALK_CONTEXT_OK: source_features=9 selectors=427 rendered=%d excluded_green=%d player=1280x720 fov=48" % [int(context.get("triangle_count")), int(context.get("excluded_green_triangle_count"))])
    quit(0)
