extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const OUT_DIR := "res://artifacts/qa/combat_weapon_hand_grip"
const WIDTH := 1280
const HEIGHT := 720
const MAX_HAND_GAP_M := 0.025
const MAX_SOCKET_SCREEN_GAP_PX := 6.0
const WEAPONS: Array[StringName] = [&"bx9", &"cbr4", &"sct8"]
const MIN_EXTENT_PX: Dictionary = {
    &"bx9": Vector2(10.0, 12.0),
    &"cbr4": Vector2(24.0, 18.0),
    &"sct8": Vector2(24.0, 18.0),
}

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("COMBAT_WEAPON_HAND_GRIP_PLAYER_WITNESS_FAIL: %s" % message)
    quit(1)

func _mask_canvas(node: Node) -> void:
    if node is CanvasLayer:
        (node as CanvasLayer).visible = false
    if node is CanvasItem:
        (node as CanvasItem).visible = false
    for child: Node in node.get_children():
        _mask_canvas(child)

func _hide_dynamic_occluders(player: CharacterBody3D) -> void:
    _hide_dynamic_recursive(root, player)
    for group_name: StringName in [&"vehicle", &"npc", &"ambient", &"traffic"]:
        for node: Node in get_nodes_in_group(group_name):
            if node == player or player.is_ancestor_of(node):
                continue
            node.set_process(false)
            node.set_physics_process(false)
            if node is Node3D:
                (node as Node3D).visible = false

func _hide_dynamic_recursive(node: Node, player: CharacterBody3D) -> void:
    if node != player and not player.is_ancestor_of(node) and node is NpcAgent:
        node.set_process(false)
        node.set_physics_process(false)
        (node as Node3D).visible = false
        return
    for child: Node in node.get_children():
        _hide_dynamic_recursive(child, player)

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

func _wait_for_authored_hand(player: CharacterBody3D, visual_runtime: Node) -> Dictionary:
    var stable_frames := 0
    var last_source := ""
    for _attempt: int in range(420):
        await process_frame
        var anchor_variant: Variant = visual_runtime.call("resolve_right_hand_anchor", player)
        if not anchor_variant is Dictionary:
            stable_frames = 0
            continue
        var anchor := anchor_variant as Dictionary
        var source := String(anchor.get("source", ""))
        if bool(anchor.get("found", false)) and source.begins_with("skeleton:"):
            stable_frames = stable_frames + 1 if source == last_source else 1
            last_source = source
            if stable_frames >= 45:
                return anchor
        else:
            stable_frames = 0
            last_source = source
    return {"found": false, "source": last_source}

func _wait_for_grip(player: CharacterBody3D, weapon_id: StringName) -> Dictionary:
    for _attempt: int in range(240):
        await process_frame
        if StringName(player.get_meta("combat_weapon_id", &"")) != weapon_id:
            continue
        var grip_locked := bool(player.get_meta("combat_weapon_grip_locked", false))
        var orientation_locked := bool(player.get_meta("combat_weapon_orientation_locked", false))
        var gap_m := float(player.get_meta("combat_weapon_hand_gap_m", 999.0))
        var orientation_gap_m := float(player.get_meta("combat_weapon_orientation_gap_m", 999.0))
        if grip_locked and orientation_locked and gap_m <= MAX_HAND_GAP_M and orientation_gap_m <= MAX_HAND_GAP_M:
            return {
                "locked": true,
                "gap_m": gap_m,
                "orientation_gap_m": orientation_gap_m,
                "source": String(player.get_meta("combat_weapon_mount_source", "")),
            }
    return {
        "locked": false,
        "gap_m": float(player.get_meta("combat_weapon_hand_gap_m", 999.0)),
        "orientation_gap_m": float(player.get_meta("combat_weapon_orientation_gap_m", 999.0)),
        "source": String(player.get_meta("combat_weapon_mount_source", "")),
    }

func _final_right_hand(player: CharacterBody3D, weapon_id: StringName, visual_runtime: Node) -> Dictionary:
    # Godot evaluates SkeletonModifier3D after ordinary process callbacks. For
    # the long-weapon TwoBoneIK3D modes, the authoritative rendered hand.r pose
    # is therefore the value captured from modification_processed and published
    # as combat_carry_ik_post_hand_world. Reading Skeleton3D later would compare
    # against the authored/pre-modifier hand pose instead of the rendered hand.
    if weapon_id == &"cbr4" or weapon_id == &"sct8":
        if StringName(player.get_meta("combat_support_ik_weapon_id", &"")) != weapon_id:
            return {"found": false, "source": "modifier:stale_weapon"}
        if not bool(player.get_meta("combat_carry_ik_active", false)):
            return {"found": false, "source": "modifier:carry_inactive"}
        var final_world: Vector3 = player.get_meta("combat_carry_ik_post_hand_world", Vector3.ZERO)
        if final_world == Vector3.ZERO:
            return {"found": false, "source": "modifier:final_hand_unavailable"}
        return {
            "found": true,
            "position": final_world,
            "source": "modifier:CombatCarryHandIK.modification_processed",
        }

    var anchor_variant: Variant = visual_runtime.call("resolve_right_hand_anchor", player)
    if not anchor_variant is Dictionary:
        return {"found": false, "source": "skeleton:invalid_payload"}
    var anchor := anchor_variant as Dictionary
    if not bool(anchor.get("found", false)):
        return {"found": false, "source": String(anchor.get("source", "skeleton:unresolved"))}
    var transform: Transform3D = anchor.get("transform", Transform3D.IDENTITY)
    return {
        "found": true,
        "position": transform.origin,
        "source": String(anchor.get("source", "skeleton:unknown")),
    }

func _collect_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D:
        var mesh_instance := node as MeshInstance3D
        if mesh_instance.mesh != null and mesh_instance.visible:
            out.append(mesh_instance)
    for child: Node in node.get_children():
        _collect_mesh_instances(child, out)

func _project_weapon_bounds(holder: Node3D, camera: Camera3D) -> Dictionary:
    var meshes: Array[MeshInstance3D] = []
    _collect_mesh_instances(holder, meshes)
    if meshes.is_empty():
        return {"visible": false, "reason": "no_meshes"}

    var min_x := INF
    var min_y := INF
    var max_x := -INF
    var max_y := -INF
    var projected_points := 0
    for mesh_instance: MeshInstance3D in meshes:
        var bounds := mesh_instance.get_aabb()
        for endpoint_index: int in range(8):
            var world_point := mesh_instance.global_transform * bounds.get_endpoint(endpoint_index)
            if camera.is_position_behind(world_point):
                continue
            var screen_point := camera.unproject_position(world_point)
            min_x = minf(min_x, screen_point.x)
            min_y = minf(min_y, screen_point.y)
            max_x = maxf(max_x, screen_point.x)
            max_y = maxf(max_y, screen_point.y)
            projected_points += 1
    if projected_points == 0:
        return {"visible": false, "reason": "all_points_behind_camera"}

    var clipped_left := clampf(min_x, 0.0, float(WIDTH))
    var clipped_top := clampf(min_y, 0.0, float(HEIGHT))
    var clipped_right := clampf(max_x, 0.0, float(WIDTH))
    var clipped_bottom := clampf(max_y, 0.0, float(HEIGHT))
    var clipped_width := maxf(0.0, clipped_right - clipped_left)
    var clipped_height := maxf(0.0, clipped_bottom - clipped_top)
    return {
        "visible": clipped_width > 0.0 and clipped_height > 0.0,
        "mesh_count": meshes.size(),
        "projected_points": projected_points,
        "bbox": [clipped_left, clipped_top, clipped_right, clipped_bottom],
        "extent_px": [clipped_width, clipped_height],
    }

func _run() -> void:
    var error := change_scene_to_file(MAIN_SCENE)
    if error != OK:
        _fail("main scene load failed: %s" % error)
        return

    var main: Node = null
    var player: CharacterBody3D = null
    for _attempt: int in range(300):
        await process_frame
        main = current_scene
        if main != null:
            player = main.get_node_or_null("Player") as CharacterBody3D
            if player != null:
                break
    if main == null or player == null:
        _fail("production main/player unavailable")
        return

    var arsenal := root.get_node_or_null("PlayerCombatArsenalRuntime")
    var visual_runtime := root.get_node_or_null("CombatWeaponVisualUpgradeRuntime")
    var orientation_runtime := root.get_node_or_null("CombatWeaponHandOrientationRuntime")
    if arsenal == null or not arsenal.has_method("equip_weapon"):
        _fail("production combat arsenal autoload unavailable")
        return
    if visual_runtime == null or not visual_runtime.has_method("resolve_right_hand_anchor"):
        _fail("weapon visual hand-mount runtime unavailable")
        return
    if orientation_runtime == null or not orientation_runtime.has_method("orient_weapon_from_player"):
        _fail("weapon hand-orientation runtime unavailable")
        return

    var camera := player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if camera == null or not camera.current:
        _fail("production player camera unavailable")
        return

    player.velocity = Vector3.ZERO
    player.set_physics_process(false)
    _hide_dynamic_occluders(player)

    var anchor := await _wait_for_authored_hand(player, visual_runtime)
    if not bool(anchor.get("found", false)):
        _fail("stable authored skeleton right hand unavailable: source=%s" % String(anchor.get("source", "")))
        return

    # Give authored visual replacement and camera spring one final stabilization
    # window before baseline. The earlier witness was polluted by NPC/avatar
    # changes between weapon captures and could report a false visual PASS.
    for _frame: int in range(45):
        _hide_dynamic_occluders(player)
        await process_frame

    var refreshed_anchor_variant: Variant = visual_runtime.call("resolve_right_hand_anchor", player)
    if not refreshed_anchor_variant is Dictionary:
        _fail("right-hand anchor returned invalid payload")
        return
    anchor = refreshed_anchor_variant as Dictionary
    var hand_transform: Transform3D = anchor.get("transform", Transform3D.IDENTITY)
    var hand_world := hand_transform.origin
    if camera.is_position_behind(hand_world):
        _fail("production right hand is behind the player camera")
        return
    var hand_screen := camera.unproject_position(hand_world)
    if hand_screen.x < 0.0 or hand_screen.x >= WIDTH or hand_screen.y < 0.0 or hand_screen.y >= HEIGHT:
        _fail("production right hand is outside the 1280x720 player view: %s" % hand_screen)
        return

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
    arsenal.call("equip_weapon", player, &"")
    for _frame: int in range(24):
        _hide_dynamic_occluders(player)
        await process_frame
    if not await _capture(OUT_DIR + "/unarmed.png"):
        _fail("unarmed player-view capture failed")
        return

    var report: Dictionary = {
        "resolution": [WIDTH, HEIGHT],
        "hand_screen": [hand_screen.x, hand_screen.y],
        "hand_anchor_source": String(anchor.get("source", "")),
        "max_hand_gap_m": MAX_HAND_GAP_M,
        "max_socket_screen_gap_px": MAX_SOCKET_SCREEN_GAP_PX,
        "weapons": {},
    }

    for weapon_id: StringName in WEAPONS:
        if not bool(arsenal.call("equip_weapon", player, weapon_id)):
            _fail("equip failed for %s" % weapon_id)
            return
        var grip := await _wait_for_grip(player, weapon_id)
        if not bool(grip.get("locked", false)):
            _fail("%s grip/orientation never locked: gap=%.6f orientation_gap=%.6f source=%s" % [weapon_id, float(grip.get("gap_m", 999.0)), float(grip.get("orientation_gap_m", 999.0)), String(grip.get("source", ""))])
            return

        for _frame: int in range(24):
            _hide_dynamic_occluders(player)
            await process_frame

        var holder := player.get_node_or_null("CombatWeaponVisual") as Node3D
        if holder == null or not bool(holder.get_meta("weapon_hand_mount_locked", false)):
            _fail("%s canonical holder is not mount-locked" % weapon_id)
            return
        if not bool(holder.get_meta("combat_weapon_orientation_locked", false)):
            _fail("%s canonical holder is not orientation-locked" % weapon_id)
            return
        if StringName(holder.get_meta("combat_weapon_holder_weapon_id", &"")) != weapon_id:
            _fail("%s canonical holder belongs to wrong weapon" % weapon_id)
            return

        var right_socket := holder.get_node_or_null("WeaponRightHandGripSocket") as Node3D
        if right_socket == null:
            _fail("%s right-hand socket missing" % weapon_id)
            return
        var final_hand := _final_right_hand(player, weapon_id, visual_runtime)
        if not bool(final_hand.get("found", false)):
            _fail("%s final right hand unavailable: source=%s" % [weapon_id, String(final_hand.get("source", ""))])
            return
        var current_hand_world: Vector3 = final_hand.get("position", Vector3.ZERO)
        var direct_gap := right_socket.global_position.distance_to(current_hand_world)
        if direct_gap > MAX_HAND_GAP_M:
            _fail("%s socket-to-final-hand gap %.6f m exceeds gate source=%s" % [weapon_id, direct_gap, String(final_hand.get("source", ""))])
            return

        if camera.is_position_behind(right_socket.global_position):
            _fail("%s right-hand socket ended behind camera" % weapon_id)
            return
        var current_hand_screen := camera.unproject_position(current_hand_world)
        var socket_screen := camera.unproject_position(right_socket.global_position)
        var socket_screen_gap := current_hand_screen.distance_to(socket_screen)
        if socket_screen_gap > MAX_SOCKET_SCREEN_GAP_PX:
            _fail("%s projected socket is %.3f px from final rendered hand" % [weapon_id, socket_screen_gap])
            return

        if not bool(player.get_meta("combat_weapon_support_grip_ready", false)):
            _fail("%s support-hand target was not published" % weapon_id)
            return

        var bounds := _project_weapon_bounds(holder, camera)
        if not bool(bounds.get("visible", false)):
            _fail("%s weapon mesh is not visible in production player camera: %s" % [weapon_id, String(bounds.get("reason", "unknown"))])
            return
        var extent_values: Array = bounds.get("extent_px", [0.0, 0.0])
        var extent := Vector2(float(extent_values[0]), float(extent_values[1]))
        var minimum: Vector2 = MIN_EXTENT_PX.get(weapon_id, Vector2(10.0, 10.0))
        if extent.x < minimum.x or extent.y < minimum.y:
            _fail("%s projected weapon extent %.1fx%.1f px below %.1fx%.1f player-view gate" % [weapon_id, extent.x, extent.y, minimum.x, minimum.y])
            return

        var weapon_forward := -holder.global_transform.basis.z.normalized()
        var player_forward := -player.global_transform.basis.z.normalized()
        var forward_dot := weapon_forward.dot(player_forward)
        if forward_dot < 0.70:
            _fail("%s weapon points away from player forward axis: dot=%.3f" % [weapon_id, forward_dot])
            return

        var capture_path := OUT_DIR + "/%s.png" % String(weapon_id)
        if not await _capture(capture_path):
            _fail("%s player-view capture failed" % weapon_id)
            return
        report["weapons"][String(weapon_id)] = {
            "gap_m": float(grip.get("gap_m", 999.0)),
            "orientation_gap_m": float(grip.get("orientation_gap_m", 999.0)),
            "direct_gap_m": direct_gap,
            "direct_gap_source": String(final_hand.get("source", "")),
            "socket_screen_gap_px": socket_screen_gap,
            "mount_source": String(grip.get("source", "")),
            "grip_locked": true,
            "orientation_locked": true,
            "support_grip_ready": true,
            "screen_bbox": bounds.get("bbox", []),
            "screen_extent_px": bounds.get("extent_px", []),
            "mesh_count": int(bounds.get("mesh_count", 0)),
            "forward_dot": forward_dot,
        }

    var report_file := FileAccess.open(OUT_DIR + "/report.json", FileAccess.WRITE)
    if report_file == null:
        _fail("could not write player witness report")
        return
    report_file.store_string(JSON.stringify(report, "  "))
    report_file.close()

    print("COMBAT_WEAPON_HAND_GRIP_PLAYER_WITNESS_OK: player_view=1280x720 authored_hand=true final_modifier_hand=true grip=true orientation=true projected_mesh=true bx9=visible cbr4=visible sct8=visible max_gap_m=%.3f source=%s" % [MAX_HAND_GAP_M, String(anchor.get("source", ""))])
    quit(0)