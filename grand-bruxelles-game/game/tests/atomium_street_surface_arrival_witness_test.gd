extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const OUT_DIR := "res://artifacts/qa/atomium_street_surface_arrival"
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
    push_error("ATOMIUM_STREET_SURFACE_ARRIVAL_WITNESS_FAIL: %s" % message)
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
        runtime = root.get_node_or_null("AtomiumStreetSurfaceRuntime")
        if runtime != null:
            break
    if runtime == null:
        _fail("registry module root missing")
        return
    if bool(runtime.call("runtime_approved")) or bool(runtime.call("realism_complete")):
        _fail("candidate was accidentally promoted")
        return
    if bool(runtime.call("source_position_changed")) or bool(runtime.call("collision_changed")):
        _fail("source position/collision rail drifted")
        return

    runtime.call("set_enhanced_enabled", false)
    player.call_deferred("_activate_atomium_direct_spawn")

    var location_label: Node = null
    var spawn_complete := false
    for _attempt: int in range(480):
        await process_frame
        main = current_scene
        if main == null:
            continue
        location_label = main.get_node_or_null("LocationLabel")
        if location_label == null or not location_label.has_method("get_current_location_text"):
            continue
        if str(location_label.call("get_current_location_text")) != EXPECTED_LOCATION:
            continue
        player.velocity = Vector3.ZERO
        player.set_process(false)
        player.set_physics_process(false)
        spawn_complete = true
        break
    if not spawn_complete:
        _fail("production Atomium spawn completion signal was not observed")
        return

    var terrain: Node = main.get_node_or_null("AtomiumDirectTerrain")
    var hero: Node = main.get_node_or_null("AtomiumDirectHero")
    var reflection: Node = main.get_node_or_null("AtomiumDirectReflectionEnvironment")
    var landcover: Node3D = main.get_node_or_null("AtomiumLandCoverContext") as Node3D
    var context := runtime.call("context_node") as Node3D
    if terrain == null or hero == null or reflection == null or landcover == null or context == null:
        _fail("production Atomium context / StreetSurface runtime incomplete after spawn signal")
        return
    if not bool(terrain.get("terrain_loaded")) or not bool(runtime.call("ready_complete")) or bool(runtime.call("failed")):
        _fail("terrain or StreetSurface runtime not ready")
        return
    if context.name != "AtomiumStreetSurfaceContext" or not bool(context.get_meta("registry_mounted", false)):
        _fail("registry-mounted StreetSurface identity invalid")
        return
    if bool(context.get_meta("runtime_approved", true)) or bool(context.get_meta("realism_complete", true)):
        _fail("StreetSurface context was accidentally promoted")
        return
    if str(context.get_meta("source_class", "")) != "urbisvector:StreetSurfaces" or str(context.get_meta("source_crs", "")) != "EPSG:31370":
        _fail("StreetSurface source provenance drifted")
        return
    if float(context.get("context_radius_m")) != 160.0 or int(context.get("source_feature_count")) <= 0 or int(context.get("triangle_count")) <= 0:
        _fail("StreetSurface source-bounded build contract invalid")
        return
    if context.visible:
        _fail("BEFORE toggle did not hide StreetSurface context")
        return
    if not landcover.visible:
        _fail("existing official LandCover baseline must remain visible")
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

    _freeze_dynamic_groups()
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
    if not context.visible:
        _fail("AFTER toggle did not show StreetSurface context")
        return
    if not landcover.visible:
        _fail("AFTER must not remove existing LandCover")
        return
    if not await _capture(after_path):
        _fail("AFTER capture failed")
        return

    print("ATOMIUM_STREET_SURFACE_ARRIVAL_WITNESS_OK: player_eye=true camera_rescue=false radius=160.0 source_features=%d triangles=%d fov=%.1f pitch=%.1f spring=%.1f" % [int(context.get("source_feature_count")), int(context.get("triangle_count")), camera.fov, pivot.rotation_degrees.x, arm.spring_length])
    quit(0)
