extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const RUNTIME_SCRIPT := "res://game/scripts/combat_weapon_upper_body_runtime.gd"
const OUT_DIR := "res://artifacts/qa/combat_weapon_upper_body"
const WIDTH := 1280
const HEIGHT := 720
const WEAPON_ID: StringName = &"cbr4"
const MAX_HAND_TARGET_GAP_M := 0.14
const MIN_RIGHT_HAND_RAISE_M := 0.08

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("COMBAT_WEAPON_UPPER_BODY_WITNESS_FAIL: %s" % message)
    quit(1)

func _normalized_bone_name(value: String) -> String:
    var compact := value.to_lower()
    for token: String in [":", "_", "-", ".", " "]:
        compact = compact.replace(token, "")
    return compact

func _is_right_hand(value: String) -> bool:
    var compact := _normalized_bone_name(value)
    return compact.ends_with("righthand") or compact.ends_with("handr") or compact == "rhand"

func _is_left_hand(value: String) -> bool:
    var compact := _normalized_bone_name(value)
    return compact.ends_with("lefthand") or compact.ends_with("handl") or compact == "lhand"

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        var skeleton := node as Skeleton3D
        var has_left := false
        var has_right := false
        for bone_index: int in range(skeleton.get_bone_count()):
            var bone_name := String(skeleton.get_bone_name(bone_index))
            has_left = has_left or _is_left_hand(bone_name)
            has_right = has_right or _is_right_hand(bone_name)
        if has_left and has_right:
            return skeleton
    for child: Node in node.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null

func _find_hand_bone(skeleton: Skeleton3D, right_side: bool) -> int:
    for bone_index: int in range(skeleton.get_bone_count()):
        var bone_name := String(skeleton.get_bone_name(bone_index))
        if (right_side and _is_right_hand(bone_name)) or (not right_side and _is_left_hand(bone_name)):
            return bone_index
    return -1

func _bone_world_position(skeleton: Skeleton3D, bone_index: int) -> Vector3:
    return (skeleton.global_transform * skeleton.get_bone_global_pose(bone_index)).origin

func _chain_names(skeleton: Skeleton3D, tip_index: int) -> Array[String]:
    var names: Array[String] = []
    var current := tip_index
    for _depth: int in range(6):
        if current < 0:
            break
        names.append(String(skeleton.get_bone_name(current)))
        current = skeleton.get_bone_parent(current)
    return names

func _mask_canvas(node: Node) -> void:
    if node is CanvasLayer:
        (node as CanvasLayer).visible = false
    elif node is CanvasItem:
        (node as CanvasItem).visible = false
    for child: Node in node.get_children():
        _mask_canvas(child)

func _hide_dynamic_recursive(node: Node, player: CharacterBody3D) -> void:
    if node != player and not player.is_ancestor_of(node) and node is NpcAgent:
        node.set_process(false)
        node.set_physics_process(false)
        (node as Node3D).visible = false
        return
    for child: Node in node.get_children():
        _hide_dynamic_recursive(child, player)

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

func _settle(player: CharacterBody3D, frames: int) -> void:
    for _frame: int in range(frames):
        _hide_dynamic_occluders(player)
        _mask_canvas(root)
        await process_frame

func _capture(player: CharacterBody3D, path: String) -> bool:
    await _settle(player, 8)
    RenderingServer.force_draw()
    await process_frame
    _mask_canvas(root)
    RenderingServer.force_draw()
    await process_frame
    var image := root.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        return false
    return image.save_png(ProjectSettings.globalize_path(path)) == OK

func _write_report(payload: Dictionary) -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
    var file := FileAccess.open(OUT_DIR + "/report.json", FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify(payload, "  "))
        file.close()

func _ensure_runtime() -> Dictionary:
    var runtime := root.get_node_or_null("CombatWeaponUpperBodyRuntime")
    if runtime != null:
        return {"node": runtime, "source": "autoload"}
    var runtime_script := load(RUNTIME_SCRIPT) as Script
    if runtime_script == null:
        return {"node": null, "source": "missing"}
    runtime = runtime_script.new() as Node
    if runtime == null:
        return {"node": null, "source": "instantiate_failed"}
    runtime.name = "CombatWeaponUpperBodyRuntime"
    root.add_child(runtime)
    return {"node": runtime, "source": "witness_instance"}

func _run() -> void:
    var change_error := change_scene_to_file(MAIN_SCENE)
    if change_error != OK:
        _fail("production main scene failed to load")
        return

    var player: CharacterBody3D = null
    var visual: Node = null
    for _attempt: int in range(360):
        await process_frame
        var scene := current_scene
        if scene == null:
            continue
        player = scene.get_node_or_null("Player") as CharacterBody3D
        if player == null:
            continue
        visual = player.get_node_or_null("VisualUpgrade")
        if visual != null and visual.has_method("is_using_authored_character") and bool(visual.call("is_using_authored_character")):
            break
    if player == null or visual == null:
        _fail("production authored player unavailable")
        return

    var skeleton := _find_skeleton(visual)
    if skeleton == null:
        _fail("authored skeleton with bilateral hands unavailable")
        return
    var right_hand := _find_hand_bone(skeleton, true)
    var left_hand := _find_hand_bone(skeleton, false)
    if right_hand < 0 or left_hand < 0:
        _fail("left/right hand bones unresolved")
        return

    var arsenal := root.get_node_or_null("PlayerCombatArsenalRuntime")
    if arsenal == null or not arsenal.has_method("equip_weapon"):
        _fail("production combat arsenal unavailable")
        return
    arsenal.call("equip_weapon", player, WEAPON_ID)
    player.velocity = Vector3.ZERO
    player.set_physics_process(false)
    _hide_dynamic_occluders(player)

    var runtime_info := _ensure_runtime()
    var runtime := runtime_info.get("node") as Node
    var report: Dictionary = {
        "weapon": String(WEAPON_ID),
        "right_chain": _chain_names(skeleton, right_hand),
        "left_chain": _chain_names(skeleton, left_hand),
        "runtime_present": runtime != null,
        "runtime_source": String(runtime_info.get("source", "unknown")),
    }
    if runtime == null or not runtime.has_method("set_pose_enabled"):
        _write_report(report)
        _fail("upper-body runtime unavailable")
        return

    runtime.call("set_pose_enabled", false)
    await _settle(player, 60)
    await skeleton.skeleton_updated
    var baseline_right := _bone_world_position(skeleton, right_hand)
    var baseline_left := _bone_world_position(skeleton, left_hand)
    report["baseline_right_hand_world"] = [baseline_right.x, baseline_right.y, baseline_right.z]
    report["baseline_left_hand_world"] = [baseline_left.x, baseline_left.y, baseline_left.z]
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
    if not await _capture(player, OUT_DIR + "/before.png"):
        _write_report(report)
        _fail("baseline player capture failed")
        return

    runtime.call("set_pose_enabled", true)
    await _settle(player, 90)
    await skeleton.skeleton_updated

    var right_target_variant: Variant = runtime.call("current_right_target_world")
    var left_target_variant: Variant = runtime.call("current_support_target_world")
    if typeof(right_target_variant) != TYPE_VECTOR3 or typeof(left_target_variant) != TYPE_VECTOR3:
        _write_report(report)
        _fail("runtime did not expose vector hand targets")
        return
    var right_target: Vector3 = right_target_variant
    var left_target: Vector3 = left_target_variant
    var posed_right := _bone_world_position(skeleton, right_hand)
    var posed_left := _bone_world_position(skeleton, left_hand)
    var right_gap := posed_right.distance_to(right_target)
    var left_gap := posed_left.distance_to(left_target)
    var raise_m := posed_right.y - baseline_right.y

    report["right_target_world"] = [right_target.x, right_target.y, right_target.z]
    report["support_target_world"] = [left_target.x, left_target.y, left_target.z]
    report["posed_right_hand_world"] = [posed_right.x, posed_right.y, posed_right.z]
    report["posed_left_hand_world"] = [posed_left.x, posed_left.y, posed_left.z]
    report["right_gap_m"] = right_gap
    report["support_gap_m"] = left_gap
    report["right_raise_m"] = raise_m
    report["right_root"] = String(player.get_meta("combat_upper_body_right_root", ""))
    report["left_root"] = String(player.get_meta("combat_upper_body_left_root", ""))
    report["right_forearm"] = String(player.get_meta("combat_upper_body_right_forearm", ""))
    report["left_forearm"] = String(player.get_meta("combat_upper_body_left_forearm", ""))
    report["max_hand_target_gap_m"] = MAX_HAND_TARGET_GAP_M
    report["min_right_hand_raise_m"] = MIN_RIGHT_HAND_RAISE_M

    if not await _capture(player, OUT_DIR + "/after.png"):
        _write_report(report)
        _fail("posed player capture failed")
        return
    _write_report(report)

    if right_gap > MAX_HAND_TARGET_GAP_M:
        _fail("right hand misses carry target: %.3fm" % right_gap)
        return
    if left_gap > MAX_HAND_TARGET_GAP_M:
        _fail("support hand misses foregrip target: %.3fm" % left_gap)
        return
    if raise_m < MIN_RIGHT_HAND_RAISE_M:
        _fail("right hand remained too low: raised only %.3fm" % raise_m)
        return

    print("COMBAT_WEAPON_UPPER_BODY_WITNESS_OK: weapon=%s runtime=%s right_gap=%.3f support_gap=%.3f raise=%.3f right_root=%s right_forearm=%s right_chain=%s left_chain=%s" % [String(WEAPON_ID), String(runtime_info.get("source", "unknown")), right_gap, left_gap, raise_m, String(player.get_meta("combat_upper_body_right_root", "")), String(player.get_meta("combat_upper_body_right_forearm", "")), _chain_names(skeleton, right_hand), _chain_names(skeleton, left_hand)])
    quit(0)