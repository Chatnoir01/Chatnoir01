extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const OUT_DIR := "res://artifacts/qa/atomium_arrival_occluder"
const WIDTH := 1280
const HEIGHT := 720
const EXPECTED_LOCATION := "ATOMIUM · HEYSEL / HEIZEL"
const EXPECTED_SPAWN_OFFSET := Vector3(120.0, 0.0, 0.0)

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ATOMIUM_ARRIVAL_OCCLUDER_PLAYER_AB_FAIL: %s" % message)
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

    var runtime: Node = null
    for _attempt: int in range(180):
        await process_frame
        runtime = root.get_node_or_null("AtomiumArrivalPresentationRuntime")
        if runtime != null:
            break
    if runtime == null:
        _fail("Atomium arrival presentation registry module missing")
        return
    if bool(runtime.call("camera_changed")) or bool(runtime.call("source_position_changed")) or bool(runtime.call("collision_changed")):
        _fail("presentation safety rail reports a forbidden world/camera change")
        return

    player.call_deferred("_activate_atomium_direct_spawn")

    var spawn_complete := false
    for _attempt: int in range(480):
        await process_frame
        main = current_scene
        if main == null:
            continue
        var location_label := main.get_node_or_null("LocationLabel")
        var terrain_probe := main.get_node_or_null("AtomiumDirectTerrain")
        var hero_probe := main.get_node_or_null("AtomiumDirectHero")
        var reflection_probe := main.get_node_or_null("AtomiumDirectReflectionEnvironment")
        if location_label == null or not location_label.has_method("get_current_location_text"):
            continue
        if str(location_label.call("get_current_location_text")) != EXPECTED_LOCATION:
            continue
        if terrain_probe == null or hero_probe == null or reflection_probe == null:
            continue
        if not bool(terrain_probe.get("terrain_loaded")) or not bool(hero_probe.get("hero_built")):
            continue
        if not bool(runtime.call("ready_complete")) or not bool(runtime.call("applied")):
            continue
        player.velocity = Vector3.ZERO
        player.set_process(false)
        player.set_physics_process(false)
        spawn_complete = true
        break
    if not spawn_complete:
        _fail("production Atomium arrival / presentation completion signal was not observed")
        return

    var terrain: Node = main.get_node_or_null("AtomiumDirectTerrain")
    var hero: Node = main.get_node_or_null("AtomiumDirectHero")
    if terrain == null or hero == null:
        _fail("Atomium production context incomplete")
        return
    if int(hero.get("sphere_count")) != 9 or int(hero.get("tube_count")) != 20:
        _fail("Atomium topology drifted")
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
    if not is_finite(camera.fov) or camera.fov <= 1.0 or camera.fov >= 179.0 or not is_finite(pivot.rotation_degrees.x) or not is_finite(arm.spring_length) or arm.spring_length <= 0.0:
        _fail("production player camera is invalid")
        return

    var locked_position := player.global_position
    var locked_yaw := player.rotation_degrees.y
    var locked_collision_layer := player.collision_layer
    var locked_collision_mask := player.collision_mask
    var locked_fov := camera.fov
    var locked_pitch := pivot.rotation_degrees.x
    var locked_spring := arm.spring_length

    _freeze_dynamic_groups()
    runtime.call("set_enhanced_enabled", false)
    await process_frame
    if int(runtime.call("baseline_visible_visual_count")) < 1 or int(runtime.call("current_visible_visual_count")) < 1:
        _fail("BEFORE did not restore the production avatar occluder")
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
    if not bool(runtime.call("applied")) or int(runtime.call("current_visible_visual_count")) != 0:
        _fail("AFTER did not remove both player presentation meshes")
        return
    if not await _capture(after_path):
        _fail("AFTER capture failed")
        return

    if player.global_position.distance_to(locked_position) > 0.0001 or absf(player.rotation_degrees.y - locked_yaw) > 0.0001:
        _fail("player pose moved during presentation A/B")
        return
    if player.collision_layer != locked_collision_layer or player.collision_mask != locked_collision_mask:
        _fail("player collision changed during presentation A/B")
        return
    if absf(camera.fov - locked_fov) > 0.0001 or absf(pivot.rotation_degrees.x - locked_pitch) > 0.0001 or absf(arm.spring_length - locked_spring) > 0.0001:
        _fail("camera moved during presentation A/B")
        return

    print("ATOMIUM_ARRIVAL_OCCLUDER_PLAYER_AB_OK: player_eye=true avatar_before=true avatar_after=false camera_rescue=false fov=%.1f pitch=%.1f spring=%.1f xz_error=%.6f geometry_moved=false collision_changed=false" % [camera.fov, pivot.rotation_degrees.x, arm.spring_length, xz_error])
    quit(0)
