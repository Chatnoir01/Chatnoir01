extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const OUT_DIR := "res://artifacts/qa/atomium_base_sphere_window_band"
const WIDTH := 1280
const HEIGHT := 720
const EXPECTED_LOCATION := "ATOMIUM · HEYSEL / HEIZEL"
const EXPECTED_FOV := 69.0
const EXPECTED_PITCH_DEGREES := 20.0
const EXPECTED_SPRING_LENGTH := 4.9
const EXPECTED_SPAWN_OFFSET := Vector3(120.0, 0.0, 0.0)

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ATOMIUM_BASE_SPHERE_WINDOW_BAND_WITNESS_FAIL: %s" % message)
    quit(1)

func _mask_canvas(node: Node) -> void:
    if node is CanvasLayer:
        (node as CanvasLayer).visible = false
    if node is CanvasItem:
        (node as CanvasItem).visible = false
    for child: Node in node.get_children():
        _mask_canvas(child)

func _freeze_dynamic_groups() -> void:
    for group_name: StringName in [&"vehicle", &"npc", &"ambient", &"traffic"]:
        for node: Node in get_nodes_in_group(group_name):
            node.set_process(false)
            node.set_physics_process(false)

func _hide_player_visuals(player: Node) -> void:
    var base_visual := player.get_node_or_null("MeshInstance3D") as Node3D
    if base_visual != null:
        base_visual.visible = false
    var upgrade_visual := player.get_node_or_null("VisualUpgrade") as Node3D
    if upgrade_visual != null:
        upgrade_visual.visible = false

func _location_text(node: Node) -> String:
    if node == null:
        return ""
    if node.has_method("get_current_location_text"):
        return str(node.call("get_current_location_text"))
    if node is Label:
        return (node as Label).text
    return ""

func _capture(path: String) -> bool:
    for _frame: int in range(8):
        _mask_canvas(root)
        await process_frame
    RenderingServer.force_draw()
    await process_frame
    _mask_canvas(root)
    RenderingServer.force_draw()
    await process_frame
    var image := root.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        return false
    return image.save_png(ProjectSettings.globalize_path(path)) == OK

func _run() -> void:
    var error := change_scene_to_file(MAIN_SCENE)
    if error != OK:
        _fail("main scene load failed: %s" % error)
        return

    var main: Node = null
    var player: CharacterBody3D = null
    for _attempt: int in range(180):
        await process_frame
        main = current_scene
        if main != null:
            player = main.get_node_or_null("Player") as CharacterBody3D
            if player != null:
                break
    if main == null or player == null:
        _fail("main/player unavailable")
        return

    player.call_deferred("_activate_atomium_direct_spawn")
    var spawn_complete := false
    for _attempt: int in range(480):
        await process_frame
        main = current_scene
        if main == null:
            continue
        var location_label := main.get_node_or_null("LocationLabel")
        if _location_text(location_label) != EXPECTED_LOCATION:
            continue
        player.velocity = Vector3.ZERO
        player.set_process(false)
        player.set_physics_process(false)
        spawn_complete = true
        break
    if not spawn_complete:
        _fail("production Atomium spawn completion signal was not observed")
        return

    var terrain := main.get_node_or_null("AtomiumDirectTerrain")
    var hero := main.get_node_or_null("AtomiumDirectHero")
    var reflection := main.get_node_or_null("AtomiumDirectReflectionEnvironment")
    if terrain == null or hero == null or reflection == null:
        _fail("production Atomium context incomplete")
        return
    if not bool(terrain.get("terrain_loaded")) or not bool(hero.get("hero_built")):
        _fail("terrain/hero not ready")
        return
    if int(hero.get("sphere_count")) != 9 or int(hero.get("tube_count")) != 20:
        _fail("Atomium source topology drifted")
        return
    if int(hero.get("unresolved_support_pillars")) != 3:
        _fail("unresolved support-pillar rail drifted")
        return

    var band := hero.get_node_or_null("AtomiumBaseSphereWindowBand")
    if band == null or not bool(band.get("band_built")):
        _fail("base-sphere window band did not build")
        return
    if bool(band.get("exact_layout_resolved")):
        _fail("unresolved exact glazing layout was promoted")
        return
    if not bool(band.get("authored_presentation_not_survey")):
        _fail("authored-presentation disclaimer missing")
        return
    if bool(band.call("source_geometry_moved")) or bool(band.call("collision_changed")):
        _fail("source geometry/collision rail drifted")
        return

    var anchor: Vector3 = terrain.get("atomium_game_position")
    var expected_xz := anchor + EXPECTED_SPAWN_OFFSET
    var xz_error := Vector2(player.global_position.x, player.global_position.z).distance_to(Vector2(expected_xz.x, expected_xz.z))
    if xz_error > 0.02:
        _fail("player horizontal arrival position drifted: %.6f m" % xz_error)
        return

    var pivot := player.get_node_or_null("CameraPivot") as Node3D
    var arm := player.get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
    var camera := player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if pivot == null or arm == null or camera == null or not camera.current:
        _fail("production player camera unavailable")
        return
    if absf(camera.fov - EXPECTED_FOV) > 0.01 or absf(pivot.rotation_degrees.x - EXPECTED_PITCH_DEGREES) > 0.01 or absf(arm.spring_length - EXPECTED_SPRING_LENGTH) > 0.01:
        _fail("production Atomium player camera contract drifted")
        return

    _hide_player_visuals(player)
    _freeze_dynamic_groups()
    for _frame: int in range(24):
        _mask_canvas(root)
        await process_frame

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
    hero.call("set_base_sphere_window_band_enabled", false)
    await process_frame
    if bool(hero.call("base_sphere_window_band_enabled")):
        _fail("BEFORE toggle did not hide window band")
        return
    if not await _capture(OUT_DIR + "/before.png"):
        _fail("BEFORE capture failed")
        return

    hero.call("set_base_sphere_window_band_enabled", true)
    await process_frame
    if not bool(hero.call("base_sphere_window_band_enabled")):
        _fail("AFTER toggle did not show window band")
        return
    if not await _capture(OUT_DIR + "/after.png"):
        _fail("AFTER capture failed")
        return

    print("ATOMIUM_BASE_SPHERE_WINDOW_BAND_WITNESS_OK: player_arrival=true camera_rescue=false fov=%.1f pitch=%.1f spring=%.1f xz_error=%.6f avatar_hidden_for_clean_witness=true exact_layout=false source_geometry_moved=false collision_changed=false" % [camera.fov, pivot.rotation_degrees.x, arm.spring_length, xz_error])
    quit(0)
