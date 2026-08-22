extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const OUT_DIR := "res://artifacts/qa/combat_native_weapon"
const WIDTH := 1280
const HEIGHT := 720
const MAX_TWO_HAND_GAP_M := 0.09
const NATIVE_NAMES: Array[String] = [
    "Knife_Offhand",
    "1H_Crossbow",
    "2H_Crossbow",
    "Knife",
    "Throwable",
]

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("COMBAT_NATIVE_WEAPON_PLAYER_WITNESS_FAIL: %s" % message)
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

func _hide_dynamic(node: Node, player: CharacterBody3D) -> void:
    if node != player and not player.is_ancestor_of(node) and node is NpcAgent:
        node.set_process(false)
        node.set_physics_process(false)
        (node as Node3D).visible = false
        return
    for child: Node in node.get_children():
        _hide_dynamic(child, player)

func _configure_close_pose_camera(player: CharacterBody3D, camera: Camera3D) -> void:
    var spring_arm := player.get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
    if spring_arm == null:
        return
    # Witness-only composition: close enough to judge shoulders, wrists, palms
    # and the weapon. Production shoulder-camera behavior has its own gate.
    player.set_meta("gta_scale_camera_owner", "special_presentation")
    spring_arm.spring_length = 2.25
    spring_arm.position = Vector3(0.58, 0.16, 0.0)
    camera.fov = 48.0

func _capture(path: String) -> bool:
    for _frame: int in range(8):
        _mask_canvas(root)
        await process_frame
    RenderingServer.force_draw()
    await process_frame
    var image := root.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        return false
    return image.save_png(ProjectSettings.globalize_path(path)) == OK

func _native_nodes(player: CharacterBody3D) -> Dictionary:
    var found: Dictionary = {}
    for node_name: String in NATIVE_NAMES:
        var node := player.find_child(node_name, true, false) as Node3D
        if node != null:
            found[node_name] = node
    return found

func _visible_native_names(player: CharacterBody3D) -> Array[String]:
    var visible: Array[String] = []
    var nodes := _native_nodes(player)
    for node_name: String in NATIVE_NAMES:
        var node := nodes.get(node_name) as Node3D
        if node != null and node.visible:
            visible.append(node_name)
    return visible

func _wait_equipped(player: CharacterBody3D, weapon_id: StringName) -> bool:
    for _attempt: int in range(240):
        await process_frame
        if StringName(player.get_meta("combat_weapon_id", &"")) != weapon_id:
            continue
        if StringName(player.get_meta("combat_weapon_state", &"")) != &"equipped":
            continue
        if bool(player.get_meta("combat_weapon_switching", true)):
            continue
        return true
    return false

func _wait_two_hand_pose(player: CharacterBody3D) -> bool:
    for _attempt: int in range(240):
        await process_frame
        var carry_gap := float(player.get_meta("combat_carry_hand_gap_m", 999.0))
        var support_gap := float(player.get_meta("combat_support_hand_gap_m", 999.0))
        if bool(player.get_meta("combat_carry_ik_locked", false)) \
                and bool(player.get_meta("combat_support_ik_locked", false)) \
                and carry_gap <= MAX_TWO_HAND_GAP_M and support_gap <= MAX_TWO_HAND_GAP_M:
            return true
    return false

func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D:
        var mesh_instance := node as MeshInstance3D
        if mesh_instance.mesh != null and mesh_instance.visible:
            out.append(mesh_instance)
    for child: Node in node.get_children():
        _collect_meshes(child, out)

func _project_bounds(node: Node3D, camera: Camera3D) -> Dictionary:
    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(node, meshes)
    if meshes.is_empty():
        return {"visible": false, "mesh_count": 0, "extent_px": [0.0, 0.0]}
    var min_x := INF
    var min_y := INF
    var max_x := -INF
    var max_y := -INF
    var projected := 0
    for mesh_instance: MeshInstance3D in meshes:
        var aabb := mesh_instance.get_aabb()
        for endpoint: int in range(8):
            var world_point := mesh_instance.global_transform * aabb.get_endpoint(endpoint)
            if camera.is_position_behind(world_point):
                continue
            var screen := camera.unproject_position(world_point)
            min_x = minf(min_x, screen.x)
            min_y = minf(min_y, screen.y)
            max_x = maxf(max_x, screen.x)
            max_y = maxf(max_y, screen.y)
            projected += 1
    if projected == 0:
        return {"visible": false, "mesh_count": meshes.size(), "extent_px": [0.0, 0.0]}
    var left := clampf(min_x, 0.0, float(WIDTH))
    var top := clampf(min_y, 0.0, float(HEIGHT))
    var right := clampf(max_x, 0.0, float(WIDTH))
    var bottom := clampf(max_y, 0.0, float(HEIGHT))
    var width := maxf(0.0, right - left)
    var height := maxf(0.0, bottom - top)
    return {
        "visible": width > 0.0 and height > 0.0,
        "mesh_count": meshes.size(),
        "extent_px": [width, height],
        "bbox": [left, top, right, bottom],
        "projected_points": projected,
    }

func _assert_single_visual_owner(player: CharacterBody3D) -> bool:
    var visible_native := _visible_native_names(player)
    var holder := player.get_node_or_null("CombatWeaponVisual") as Node3D
    var procedural_visible := holder != null and holder.visible
    var visible_count := visible_native.size() + (1 if procedural_visible else 0)
    if visible_count > 1:
        _fail("multiple active weapon visuals: native=%s procedural=%s" % [str(visible_native), str(procedural_visible)])
        return false
    return true

func _witness_long_weapon(player: CharacterBody3D, arsenal: Node, camera: Camera3D, weapon_id: StringName, report: Dictionary) -> bool:
    if not bool(arsenal.call("equip_weapon", player, weapon_id)):
        _fail("%s equip request rejected" % weapon_id)
        return false
    if not await _wait_equipped(player, weapon_id):
        _fail("%s never reached equipped state" % weapon_id)
        return false
    if not await _wait_two_hand_pose(player):
        _fail("%s two-hand pose did not lock: carry_gap=%.4f support_gap=%.4f" % [
            weapon_id,
            float(player.get_meta("combat_carry_hand_gap_m", 999.0)),
            float(player.get_meta("combat_support_hand_gap_m", 999.0)),
        ])
        return false
    await _wait_frames(16)
    if not _visible_native_names(player).is_empty():
        _fail("native ghost visible with %s: %s" % [weapon_id, str(_visible_native_names(player))])
        return false
    if not _assert_single_visual_owner(player):
        return false
    var holder := player.get_node_or_null("CombatWeaponVisual") as Node3D
    if holder == null:
        _fail("%s procedural holder unavailable" % weapon_id)
        return false
    var bounds := _project_bounds(holder, camera)
    if not bool(bounds.get("visible", false)):
        _fail("%s is not projected in close witness camera" % weapon_id)
        return false
    var carry_gap := float(player.get_meta("combat_carry_hand_gap_m", 999.0))
    var support_gap := float(player.get_meta("combat_support_hand_gap_m", 999.0))
    var path := OUT_DIR + "/%s_close.png" % String(weapon_id)
    if not await _capture(path):
        _fail("%s close capture failed" % weapon_id)
        return false
    report["weapons"][String(weapon_id)] = {
        "two_hand_pose_locked": true,
        "carry_gap_m": carry_gap,
        "support_gap_m": support_gap,
        "support_surface_locked": bool(holder.get_meta("combat_long_weapon_support_surface_locked", false)),
        "bounds": bounds,
        "capture": path,
    }
    return true

func _run() -> void:
    if change_scene_to_file(MAIN_SCENE) != OK:
        _fail("main scene load failed")
        return

    var player: CharacterBody3D = null
    for _attempt: int in range(360):
        await process_frame
        if current_scene != null:
            player = current_scene.get_node_or_null("Player") as CharacterBody3D
            if player != null and _native_nodes(player).size() == NATIVE_NAMES.size():
                break
    if player == null:
        _fail("production player unavailable")
        return

    var arsenal := root.get_node_or_null("PlayerCombatArsenalRuntime")
    if arsenal == null:
        _fail("production arsenal unavailable")
        return
    var camera := player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if camera == null or not camera.current:
        _fail("production camera unavailable")
        return

    player.velocity = Vector3.ZERO
    player.set_physics_process(false)
    _hide_dynamic(root, player)
    _configure_close_pose_camera(player, camera)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
    var report: Dictionary = {"resolution": [WIDTH, HEIGHT], "weapons": {}, "single_visual_owner": true, "close_pose_camera": true}

    if not await _witness_long_weapon(player, arsenal, camera, &"cbr4", report):
        return
    if not await _witness_long_weapon(player, arsenal, camera, &"sct8", report):
        return

    if not bool(arsenal.call("equip_weapon", player, &"crossbow")):
        _fail("crossbow equip request rejected")
        return
    if not await _wait_equipped(player, &"crossbow"):
        _fail("crossbow never reached equipped state")
        return
    if not await _wait_two_hand_pose(player):
        _fail("crossbow two-hand pose did not lock")
        return
    await _wait_frames(16)
    var crossbow_visible := _visible_native_names(player)
    if crossbow_visible != ["2H_Crossbow"]:
        _fail("crossbow visibility invariant failed: %s" % str(crossbow_visible))
        return
    if not _assert_single_visual_owner(player):
        return
    var crossbow := player.find_child("2H_Crossbow", true, false) as Node3D
    var crossbow_bounds := _project_bounds(crossbow, camera)
    if not bool(crossbow_bounds.get("visible", false)):
        _fail("crossbow is not projected in player camera")
        return
    var crossbow_gap := float(player.get_meta("combat_native_crossbow_hand_region_gap_m", 999.0))
    if not bool(player.get_meta("combat_native_crossbow_orientation_locked", false)) or crossbow_gap > 0.1201:
        _fail("crossbow hand-region lock failed: gap=%.4f" % crossbow_gap)
        return
    if not await _capture(OUT_DIR + "/crossbow_close.png"):
        _fail("crossbow capture failed")
        return
    report["weapons"]["crossbow"] = {
        "native_visible": crossbow_visible,
        "hand_region_gap_m": crossbow_gap,
        "carry_gap_m": float(player.get_meta("combat_carry_hand_gap_m", 999.0)),
        "support_gap_m": float(player.get_meta("combat_support_hand_gap_m", 999.0)),
        "orientation_locked": true,
        "bounds": crossbow_bounds,
        "capture": OUT_DIR + "/crossbow_close.png",
    }

    if not bool(arsenal.call("equip_weapon", player, &"knife")):
        _fail("knife equip request rejected")
        return
    var max_visual_owners := 0
    for _frame: int in range(40):
        await process_frame
        var visible_native := _visible_native_names(player)
        var holder := player.get_node_or_null("CombatWeaponVisual") as Node3D
        var owners := visible_native.size() + (1 if holder != null and holder.visible else 0)
        max_visual_owners = maxi(max_visual_owners, owners)
        if owners > 1:
            _fail("crossbow->knife overlap during switch: native=%s procedural=%s" % [str(visible_native), str(holder != null and holder.visible)])
            return
        if StringName(player.get_meta("combat_weapon_state", &"")) == &"equipped" and StringName(player.get_meta("combat_weapon_id", &"")) == &"knife":
            break
    if not await _wait_equipped(player, &"knife"):
        _fail("knife never reached equipped state")
        return
    await _wait_frames(24)
    var knife_visible := _visible_native_names(player)
    if knife_visible != ["Knife"]:
        _fail("knife visibility invariant failed: %s" % str(knife_visible))
        return
    if not _assert_single_visual_owner(player):
        return
    var knife := player.find_child("Knife", true, false) as Node3D
    var knife_bounds := _project_bounds(knife, camera)
    if not bool(knife_bounds.get("visible", false)):
        _fail("knife is not projected in player camera")
        return
    if not bool(player.get_meta("combat_native_knife_orientation_locked", false)):
        _fail("knife presentation never locked")
        return
    if not await _capture(OUT_DIR + "/knife_close.png"):
        _fail("knife capture failed")
        return
    report["weapons"]["knife"] = {
        "native_visible": knife_visible,
        "orientation_locked": true,
        "bounds": knife_bounds,
        "max_visual_owners_during_crossbow_to_knife": max_visual_owners,
        "capture": OUT_DIR + "/knife_close.png",
    }

    if not bool(arsenal.call("equip_weapon", player, &"cbr4")):
        _fail("CBR-4 switch request rejected")
        return
    if not bool(arsenal.call("equip_weapon", player, &"crossbow")):
        _fail("rapid crossbow queue rejected")
        return
    if not bool(arsenal.call("equip_weapon", player, &"bx9")):
        _fail("rapid BX-9 queue rejected")
        return
    max_visual_owners = 0
    for _frame: int in range(150):
        await process_frame
        var visible_native := _visible_native_names(player)
        var holder := player.get_node_or_null("CombatWeaponVisual") as Node3D
        var owners := visible_native.size() + (1 if holder != null and holder.visible else 0)
        max_visual_owners = maxi(max_visual_owners, owners)
        if owners > 1:
            _fail("rapid switch created multiple owners: native=%s procedural=%s" % [str(visible_native), str(holder != null and holder.visible)])
            return
        if StringName(player.get_meta("combat_weapon_state", &"")) == &"equipped" and StringName(player.get_meta("combat_weapon_id", &"")) == &"bx9":
            break
    if not await _wait_equipped(player, &"bx9"):
        _fail("rapid switch did not settle on last requested BX-9")
        return
    await _wait_frames(24)
    if not _visible_native_names(player).is_empty():
        _fail("native ghost remained after returning to BX-9: %s" % str(_visible_native_names(player)))
        return
    var holder := player.get_node_or_null("CombatWeaponVisual") as Node3D
    if holder == null or StringName(holder.get_meta("combat_weapon_holder_weapon_id", &"")) != &"bx9":
        _fail("canonical BX-9 holder missing after rapid switch")
        return
    if not bool(player.get_meta("combat_weapon_grip_locked", false)) or not bool(player.get_meta("combat_weapon_orientation_locked", false)):
        _fail("BX-9 hand/orientation lock missing after rapid switch")
        return
    if not await _capture(OUT_DIR + "/bx9_after_native_close.png"):
        _fail("BX-9 after-native capture failed")
        return
    report["weapons"]["bx9_after_native"] = {
        "native_visible": [],
        "grip_locked": true,
        "orientation_locked": true,
        "max_visual_owners_during_rapid_switch": max_visual_owners,
        "capture": OUT_DIR + "/bx9_after_native_close.png",
    }

    var report_file := FileAccess.open(OUT_DIR + "/report.json", FileAccess.WRITE)
    if report_file == null:
        _fail("report write failed")
        return
    report_file.store_string(JSON.stringify(report, "  "))
    report_file.close()

    print("COMBAT_NATIVE_WEAPON_PLAYER_WITNESS_OK: cbr4=close_2h sct8=close_2h crossbow=close_2h knife=visible_lock rapid_switch=last_wins single_owner=true bx9_regrip=true")
    quit(0)
