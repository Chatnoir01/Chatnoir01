extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const OUT_DIR := "res://artifacts/qa/police_combat_pressure"
const WIDTH := 1280
const HEIGHT := 720


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("POLICE_COMBAT_VISUAL_WITNESS_FAIL: %s" % message)
    quit(1)


func _wait_frames(count: int) -> void:
    for _i: int in range(count):
        await process_frame


func _mask_canvas(node: Node) -> void:
    if node is CanvasLayer:
        (node as CanvasLayer).visible = false
    if node is CanvasItem:
        (node as CanvasItem).visible = false
    for child: Node in node.get_children():
        _mask_canvas(child)


func _hide_dynamic(node: Node, keep: Array[Node]) -> void:
    for item: Node in keep:
        if node == item or item.is_ancestor_of(node):
            for child: Node in node.get_children():
                _hide_dynamic(child, keep)
            return
    if node is CharacterBody3D or node is RigidBody3D or node is VehicleBody3D:
        node.set_process(false)
        node.set_physics_process(false)
        if node is Node3D:
            (node as Node3D).visible = false
        return
    for child: Node in node.get_children():
        _hide_dynamic(child, keep)


func _capture(path: String, player: CharacterBody3D, officer: NpcAgent) -> bool:
    for _frame: int in range(2):
        _mask_canvas(root)
        _hide_dynamic(root, [player, officer])
        RenderingServer.force_draw()
        await process_frame
    var image := root.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        return false
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
    return image.save_png(ProjectSettings.globalize_path(path)) == OK


func _configure_camera(player: CharacterBody3D, camera: Camera3D) -> void:
    var spring_arm := player.get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
    if spring_arm != null:
        player.set_meta("gta_scale_camera_owner", "special_presentation")
        spring_arm.spring_length = 3.35
        spring_arm.position = Vector3(0.86, 0.28, 0.0)
    camera.fov = 54.0


func _run() -> void:
    if change_scene_to_file(MAIN_SCENE) != OK:
        _fail("main scene load failed")
        return

    var player: CharacterBody3D = null
    for _attempt: int in range(360):
        await process_frame
        if current_scene != null:
            player = current_scene.get_node_or_null("Player") as CharacterBody3D
            if player != null:
                break
    if player == null:
        _fail("production player unavailable")
        return

    var combat_runtime := root.get_node_or_null("NpcPoliceCombatRuntime")
    if combat_runtime == null:
        _fail("NpcPoliceCombatRuntime autoload unavailable")
        return
    var camera := player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if camera == null:
        _fail("production camera unavailable")
        return

    player.velocity = Vector3.ZERO
    player.set_physics_process(false)
    player.set_meta("combat_health", 100)
    _configure_camera(player, camera)

    var forward := -player.global_transform.basis.z.normalized()
    var right := player.global_transform.basis.x.normalized()
    var officer := NpcAgent.new()
    officer.name = "PoliceCombatWitnessOfficer"
    officer.role = NpcBehaviorModel.Role.POLICE
    officer.add_to_group("police_officer")
    officer.add_to_group("police_npc")
    officer.global_position = player.global_position + forward * 10.0 + right * 1.35
    current_scene.add_child(officer)
    officer.set_spawn_context(NpcBehaviorModel.Role.POLICE, 71, officer.global_position)
    officer.report_police_incident(player.global_position, 1.0, 940071)
    officer.update_police_threat(true, 1.0, 0.05)

    var visual: Node3D = null
    for _attempt: int in range(180):
        await process_frame
        visual = officer.get_node_or_null("BelgianPoliceVisual") as Node3D
        if visual != null:
            break
    if visual == null:
        _fail("BelgianPoliceVisual was not created on witness officer")
        return

    _hide_dynamic(root, [player, officer])
    var ranged_decision: Dictionary = combat_runtime.call("combat_decision_for_test", officer, player, true)
    var ranged_action_at_capture := StringName(ranged_decision.get("action_name", &"none"))
    if ranged_action_at_capture != &"ranged_attack":
        _fail("ranged witness decision was %s instead of ranged_attack" % String(ranged_action_at_capture))
        return
    combat_runtime.set_process(false)
    combat_runtime.call("_face_player", officer, player)
    combat_runtime.call("_spawn_ranged_feedback", officer, player)
    officer.set_meta("police_combat_action", ranged_action_at_capture)
    officer.set_meta("police_combat_visual_state", &"ranged")
    await process_frame
    var ranged_path := OUT_DIR + "/police_ranged_pressure.png"
    if not await _capture(ranged_path, player, officer):
        _fail("ranged pressure capture failed")
        return

    officer.global_position = player.global_position + forward * 4.4 + right * 0.65
    combat_runtime.call("_face_player", officer, player)
    officer.set_meta("melee_hit_count", int(officer.get_meta("melee_hit_count", 0)) + 1)
    officer.set_meta("combat_last_weapon_damage", 34.0)
    var reaction: Dictionary = combat_runtime.call("_register_police_hit", officer, player, Time.get_ticks_msec(), true)
    await process_frame
    var hit_path := OUT_DIR + "/police_hit_stagger.png"
    if not await _capture(hit_path, player, officer):
        _fail("hit stagger capture failed")
        return

    var report := {
        "resolution": [WIDTH, HEIGHT],
        "ranged_capture": ranged_path,
        "hit_capture": hit_path,
        "ranged_action": String(ranged_action_at_capture),
        "ranged_distance_m": float(ranged_decision.get("distance_m", INF)),
        "stagger_ms": int(reaction.get("stagger_ms", 0)),
        "impact_intensity": float(reaction.get("impact_intensity", 0.0)),
        "pursuit_speed_mps": float(reaction.get("pursuit_speed_mps", 0.0)),
        "belgian_police_visual": true,
        "combat_health_after_witness": int(player.get_meta("combat_health", 100)),
    }
    var report_file := FileAccess.open(ProjectSettings.globalize_path(OUT_DIR + "/report.json"), FileAccess.WRITE)
    if report_file == null:
        _fail("report.json could not be opened")
        return
    report_file.store_string(JSON.stringify(report, "  "))
    report_file.close()

    print("POLICE_COMBAT_VISUAL_WITNESS_OK: true ranged_attack pressure and body-hit stagger captured from production scene")
    quit(0)
