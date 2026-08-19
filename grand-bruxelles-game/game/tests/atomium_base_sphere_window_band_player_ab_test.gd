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
    push_error("ATOMIUM_BASE_SPHERE_WINDOW_BAND_PLAYER_AB_FAIL: %s" % message)
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
    var runtime: Node = null
    var arrival_runtime: Node = null
    for _attempt: int in range(240):
        await process_frame
        main = current_scene
        runtime = root.get_node_or_null("AtomiumBaseSphereWindowBandRuntime")
        arrival_runtime = root.get_node_or_null("AtomiumArrivalPresentationRuntime")
        if main != null:
            player = main.get_node_or_null("Player") as CharacterBody3D
        if main != null and player != null and runtime != null and arrival_runtime != null:
            break
    if main == null or player == null:
        _fail("main/player unavailable")
        return
    if runtime == null:
        _fail("window-band registry runtime missing")
        return
    if arrival_runtime == null:
        _fail("shipped Atomium arrival presentation runtime missing")
        return
    if bool(runtime.call("runtime_approved")) or bool(runtime.call("realism_complete")):
        _fail("window-band candidate was accidentally promoted")
        return
    if bool(runtime.call("source_position_changed")) or bool(runtime.call("collision_changed")):
        _fail("runtime source-position/collision rail drifted")
        return

    runtime.call("set_enhanced_enabled", false)
    player.call_deferred("_activate_atomium_direct_spawn")

    var spawn_complete := false
    for _attempt: int in range(480):
        await process_frame
        main = current_scene
        if main == null:
            continue
        var location_label := main.get_node_or_null("LocationLabel")
        if location_label == null or not location_label.has_method("get_current_location_text"):
            continue
        if str(location_label.call("get_current_location_text")) != EXPECTED_LOCATION:
            continue
        var terrain_probe := main.get_node_or_null("AtomiumDirectTerrain")
        var hero_probe := main.get_node_or_null("AtomiumDirectHero")
        var reflection_probe := main.get_node_or_null("AtomiumDirectReflectionEnvironment")
        if terrain_probe == null or hero_probe == null or reflection_probe == null:
            continue
        if not bool(terrain_probe.get("terrain_loaded")) or not bool(hero_probe.get("hero_built")):
            continue
        if not bool(runtime.call("ready_complete")) or bool(runtime.call("failed")):
            continue
        if runtime.call("band_node") == null:
            continue
        if not bool(arrival_runtime.call("ready_complete")) or not bool(arrival_runtime.call("applied")):
            continue
        player.velocity = Vector3.ZERO
        player.set_process(false)
        player.set_physics_process(false)
        spawn_complete = true
        break
    if not spawn_complete:
        _fail("production Atomium arrival with registry glazing was not observed")
        return

    var terrain: Node = main.get_node_or_null("AtomiumDirectTerrain")
    var hero: Node3D = main.get_node_or_null("AtomiumDirectHero") as Node3D
    var reflection: Node = main.get_node_or_null("AtomiumDirectReflectionEnvironment")
    if terrain == null or hero == null or reflection == null:
        _fail("production Atomium context incomplete")
        return
    if int(hero.get("sphere_count")) != 9 or int(hero.get("tube_count")) != 20:
        _fail("Atomium topology drifted")
        return
    if absf(float(hero.get("source_height_m")) - 102.0) > 0.001 or absf(float(hero.get("source_sphere_diameter_m")) - 18.0) > 0.001 or absf(float(hero.get("source_tube_diameter_m")) - 3.3) > 0.001:
        _fail("published Atomium dimensions drifted")
        return
    if int(hero.get("unresolved_support_pillars")) != 3:
        _fail("unresolved support-pillar blocker was lost")
        return

    var base_sphere := hero.get_node_or_null("Sphere_00") as MeshInstance3D
    var band := runtime.call("band_node") as Node3D
    if base_sphere == null or band == null or not bool(band.get("band_built")):
        _fail("registry-bound base-sphere window-band component missing")
        return
    if band.get_parent() != hero:
        _fail("window-band component is not attached to the production hero")
        return
    if not bool(band.get_meta("registry_mounted", false)):
        _fail("window-band registry identity missing")
        return
    if bool(band.get("exact_layout_resolved")):
        _fail("unresolved exact window layout was incorrectly promoted")
        return
    if not bool(band.get("authored_presentation_not_survey")):
        _fail("authored-not-survey disclaimer missing")
        return
    if bool(band.call("source_geometry_moved")) or bool(band.call("collision_changed")):
        _fail("source geometry/collision rail drifted")
        return
    var overlay := band.get("overlay") as MeshInstance3D
    if overlay == null or overlay.name != "BaseSphereWindowBand_SemanticsOnly":
        _fail("window-band overlay identity missing")
        return
    if bool(overlay.get_meta("exact_layout_resolved", true)):
        _fail("overlay claims an exact window layout")
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
        _fail("production Atomium camera contract drifted")
        return
    if int(arrival_runtime.call("current_visible_visual_count")) != 0:
        _fail("shipped #881 avatar occluder suppression is not active")
        return

    _freeze_dynamic_groups()
    if bool(runtime.call("enhanced_enabled")) or overlay.visible:
        _fail("BEFORE toggle did not hide window band")
        return

    for _frame: int in range(24):
        _mask_canvas(root)
        await process_frame

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
    var before_path := OUT_DIR + "/before.png"
    var after_path := OUT_DIR + "/after.png"
    if not await _capture(before_path):
        _fail("BEFORE capture failed")
        return

    runtime.call("set_enhanced_enabled", true)
    await process_frame
    if not bool(runtime.call("enhanced_enabled")) or not overlay.visible:
        _fail("AFTER toggle did not show window band")
        return
    if not await _capture(after_path):
        _fail("AFTER capture failed")
        return

    print("ATOMIUM_BASE_SPHERE_WINDOW_BAND_PLAYER_AB_OK: player_eye=true registry_mount=true avatar_occluder_hidden=true camera_rescue=false fov=%.1f pitch=%.1f spring=%.1f xz_error=%.6f spheres=9 tubes=20 exact_layout=false geometry_moved=false collision_changed=false" % [camera.fov, pivot.rotation_degrees.x, arm.spring_length, xz_error])
    quit(0)
