extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const OUT_DIR := "res://artifacts/qa/atomium_current_basin_registry"
const WIDTH := 1280
const HEIGHT := 720
const EXPECTED_FOV := 69.0
const EXPECTED_PITCH_DEGREES := 20.0
const EXPECTED_SPRING_LENGTH := 4.9
const EXPECTED_SPAWN_OFFSET := Vector3(120.0, 0.0, 0.0)
const EXPECTED_EYE_HEIGHT_M := 1.05

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ATOMIUM_CURRENT_BASIN_REGISTRY_WITNESS_FAIL: %s" % message)
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
        runtime = root.get_node_or_null("AtomiumCurrentBasinRuntime")
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

    var terrain: Node = null
    var basin: Node3D = null
    var pivot: Node3D = null
    var arm: SpringArm3D = null
    var camera: Camera3D = null
    var expected_xz := Vector3.ZERO
    var expected_y := 0.0
    var arrival_complete := false
    for _attempt: int in range(480):
        await process_frame
        main = current_scene
        if main == null:
            continue
        terrain = main.get_node_or_null("AtomiumDirectTerrain")
        basin = runtime.call("basin_node") as Node3D
        if terrain == null or not bool(terrain.get("terrain_loaded")) or basin == null or not bool(runtime.call("ready_complete")):
            continue
        if main.get_node_or_null("AtomiumDirectHero") == null or main.get_node_or_null("AtomiumDirectReflectionEnvironment") == null:
            continue

        var anchor: Vector3 = terrain.get("atomium_game_position")
        expected_xz = anchor + EXPECTED_SPAWN_OFFSET
        expected_y = float(terrain.call("sample_height", expected_xz.x, expected_xz.z)) + EXPECTED_EYE_HEIGHT_M
        pivot = player.get_node_or_null("CameraPivot") as Node3D
        arm = player.get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
        camera = player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
        if pivot == null or arm == null or camera == null or not camera.current:
            continue
        if Vector2(player.global_position.x, player.global_position.z).distance_to(Vector2(expected_xz.x, expected_xz.z)) > 0.02:
            continue
        if absf(player.global_position.y - expected_y) > 0.05:
            continue
        if absf(camera.fov - EXPECTED_FOV) > 0.01 or absf(pivot.rotation_degrees.x - EXPECTED_PITCH_DEGREES) > 0.01 or absf(arm.spring_length - EXPECTED_SPRING_LENGTH) > 0.01:
            continue
        arrival_complete = true
        break

    if not arrival_complete:
        _fail("Atomium direct spawn did not reach the exact production arrival contract")
        return
    if terrain == null or basin == null or not bool(terrain.get("terrain_loaded")):
        _fail("Atomium direct terrain / registry basin did not become ready")
        return
    if bool(runtime.call("failed")):
        _fail("registry runtime reported failure")
        return
    if basin.name != "AtomiumCurrentBasinFootprint" or not bool(basin.get_meta("registry_mounted", false)):
        _fail("registry-mounted basin identity invalid")
        return
    if basin.visible:
        _fail("BEFORE toggle did not hide basin")
        return
    if Vector2(player.global_position.x, player.global_position.z).distance_to(Vector2(expected_xz.x, expected_xz.z)) > 0.02:
        _fail("player arrival camera position was moved")
        return
    if absf(player.global_position.y - expected_y) > 0.05:
        _fail("player arrival eye height drifted")
        return
    if pivot == null or arm == null or camera == null or not camera.current:
        _fail("production player camera unavailable")
        return
    if absf(camera.fov - EXPECTED_FOV) > 0.01 or absf(pivot.rotation_degrees.x - EXPECTED_PITCH_DEGREES) > 0.01 or absf(arm.spring_length - EXPECTED_SPRING_LENGTH) > 0.01:
        _fail("production Atomium player camera contract drifted")
        return

    player.velocity = Vector3.ZERO
    player.set_process(false)
    player.set_physics_process(false)
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
    if not basin.visible:
        _fail("AFTER toggle did not show basin")
        return
    if not await _capture(after_path):
        _fail("AFTER capture failed")
        return

    print("ATOMIUM_CURRENT_BASIN_REGISTRY_WITNESS_OK: player_eye=true camera_rescue=false fov=%.1f pitch=%.1f spring=%.1f runtime_approved=false realism_complete=false" % [camera.fov, pivot.rotation_degrees.x, arm.spring_length])
    quit(0)
