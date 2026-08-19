extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const OUT_DIR := "res://artifacts/qa/rogue_crossbow_orientation_calibration"
const CROSSBOW_NODE := "2H_Crossbow"
const CANDIDATES: Array[Dictionary] = [
    {"id":"baseline", "keep":true},
    {"id":"player_zero", "deg":Vector3(0.0, 0.0, 0.0)},
    {"id":"carry_left", "deg":Vector3(-12.0, -24.0, -5.0)},
    {"id":"carry_right", "deg":Vector3(-12.0, 24.0, 5.0)},
    {"id":"quarter_left", "deg":Vector3(-8.0, -70.0, 0.0)},
    {"id":"quarter_right", "deg":Vector3(-8.0, 70.0, 0.0)},
    {"id":"roll_90", "deg":Vector3(0.0, 0.0, 90.0)},
]

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ROGUE_CROSSBOW_ORIENTATION_CALIBRATION_FAIL: %s" % message)
    quit(1)

func _mask_canvas(node: Node) -> void:
    if node is CanvasLayer:
        (node as CanvasLayer).visible = false
    if node is CanvasItem:
        (node as CanvasItem).visible = false
    for child: Node in node.get_children():
        _mask_canvas(child)

func _hide_dynamic(node: Node, player: CharacterBody3D) -> void:
    if node != player and not player.is_ancestor_of(node) and node is NpcAgent:
        node.set_process(false)
        node.set_physics_process(false)
        (node as Node3D).visible = false
        return
    for child: Node in node.get_children():
        _hide_dynamic(child, player)

func _capture(path: String, player: CharacterBody3D) -> bool:
    for _i: int in range(6):
        _mask_canvas(root)
        _hide_dynamic(root, player)
        await process_frame
    RenderingServer.force_draw()
    await process_frame
    var image := root.get_texture().get_image()
    if image == null or image.is_empty():
        return false
    return image.save_png(ProjectSettings.globalize_path(path)) == OK

func _mesh_screen_metrics(mesh_instance: MeshInstance3D, camera: Camera3D) -> Dictionary:
    if mesh_instance == null or mesh_instance.mesh == null or camera == null:
        return {}
    var aabb := mesh_instance.get_aabb()
    var minp := Vector2(INF, INF)
    var maxp := Vector2(-INF, -INF)
    var visible_count := 0
    for xi: int in [0, 1]:
        for yi: int in [0, 1]:
            for zi: int in [0, 1]:
                var local := aabb.position + Vector3(aabb.size.x * xi, aabb.size.y * yi, aabb.size.z * zi)
                var world := mesh_instance.global_transform * local
                if camera.is_position_behind(world):
                    continue
                var screen := camera.unproject_position(world)
                minp.x = minf(minp.x, screen.x)
                minp.y = minf(minp.y, screen.y)
                maxp.x = maxf(maxp.x, screen.x)
                maxp.y = maxf(maxp.y, screen.y)
                visible_count += 1
    if visible_count == 0:
        return {"visible":false}
    return {
        "visible":true,
        "extent_px":maxp-minp,
        "center_px":(minp+maxp)*0.5,
        "min_px":minp,
        "max_px":maxp,
    }

func _run() -> void:
    if root.get_node_or_null("CombatAuthoredPoseRuntime") != null:
        _fail("unsafe pose runtime active")
        return
    if change_scene_to_file(MAIN_SCENE) != OK:
        _fail("main scene load failed")
        return

    var player: CharacterBody3D = null
    var crossbow: Node3D = null
    for _attempt: int in range(420):
        await process_frame
        if current_scene == null:
            continue
        player = current_scene.get_node_or_null("Player") as CharacterBody3D
        if player != null:
            crossbow = player.find_child(CROSSBOW_NODE, true, false) as Node3D
            if crossbow != null:
                break
    if player == null or crossbow == null:
        _fail("player/crossbow unavailable")
        return

    var arsenal := root.get_node_or_null("PlayerCombatArsenalRuntime")
    var grip_runtime := root.get_node_or_null("CombatWeaponVisualUpgradeRuntime")
    if arsenal == null or grip_runtime == null or not grip_runtime.has_method("resolve_right_hand_anchor"):
        _fail("arsenal/grip runtime unavailable")
        return
    if not bool(arsenal.call("equip_weapon", player, &"crossbow")):
        _fail("crossbow equip failed")
        return
    for _i: int in range(24): await process_frame

    var anchor_variant: Variant = grip_runtime.call("resolve_right_hand_anchor", player)
    if not anchor_variant is Dictionary or not bool((anchor_variant as Dictionary).get("found", false)):
        _fail("right hand anchor unavailable")
        return
    var hand_transform: Transform3D = (anchor_variant as Dictionary).get("transform", Transform3D.IDENTITY)
    var hand_origin := hand_transform.origin
    var base_transform := crossbow.global_transform
    var base_offset := base_transform.origin - hand_origin
    var camera := player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if camera == null:
        _fail("production camera unavailable")
        return

    arsenal.set_process(false)
    player.velocity = Vector3.ZERO
    player.set_physics_process(false)
    _hide_dynamic(root, player)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

    var report: Dictionary = {}
    for candidate: Dictionary in CANDIDATES:
        var id := String(candidate.get("id", "candidate"))
        if bool(candidate.get("keep", false)):
            crossbow.global_transform = base_transform
        else:
            var deg: Vector3 = candidate.get("deg", Vector3.ZERO)
            crossbow.global_rotation = player.global_rotation + Vector3(deg_to_rad(deg.x), deg_to_rad(deg.y), deg_to_rad(deg.z))
            crossbow.global_position = hand_origin + base_offset
        for _i: int in range(4): await process_frame
        var metrics := _mesh_screen_metrics(crossbow as MeshInstance3D, camera) if crossbow is MeshInstance3D else {}
        metrics["hand_gap_m"] = crossbow.global_position.distance_to(hand_origin)
        report[id] = metrics
        if not await _capture(OUT_DIR + "/%s.png" % id, player):
            _fail("capture failed: %s" % id)
            return

    print("ROGUE_CROSSBOW_ORIENTATION_CALIBRATION_OK: %s" % JSON.stringify(report))
    quit(0)
