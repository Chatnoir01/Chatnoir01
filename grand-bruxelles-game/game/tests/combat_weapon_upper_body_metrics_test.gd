extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const RUNTIME_SCRIPT := "res://game/scripts/combat_weapon_upper_body_runtime.gd"
const WEAPON_ID: StringName = &"cbr4"
const MAX_HAND_TARGET_GAP_M := 0.14
const MIN_RIGHT_HAND_RAISE_M := 0.08

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("COMBAT_WEAPON_UPPER_BODY_METRICS_FAIL: %s" % message)
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

func _resolve_runtime() -> Dictionary:
    var runtime := root.get_node_or_null("CombatWeaponUpperBodyRuntime")
    if runtime != null:
        return {"node": runtime, "source": "autoload"}
    var runtime_script := load(RUNTIME_SCRIPT) as Script
    if runtime_script == null:
        return {"node": null, "source": "missing"}
    runtime = runtime_script.new() as Node
    if runtime == null:
        return {"node": null, "source": "instantiate_failed"}
    runtime.name = "CombatWeaponUpperBodyRuntimeMetrics"
    root.add_child(runtime)
    return {"node": runtime, "source": "metrics_instance"}

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
    for _frame: int in range(60):
        await process_frame

    var runtime_info := _resolve_runtime()
    var runtime := runtime_info.get("node") as Node
    if runtime == null or not runtime.has_method("set_pose_enabled"):
        _fail("upper-body runtime unavailable")
        return

    runtime.call("set_pose_enabled", false)
    for _frame: int in range(45):
        await process_frame
    await skeleton.skeleton_updated
    var baseline_right := _bone_world_position(skeleton, right_hand)
    var baseline_left := _bone_world_position(skeleton, left_hand)

    runtime.call("set_pose_enabled", true)
    for _frame: int in range(120):
        await process_frame
    await skeleton.skeleton_updated

    var right_target_variant: Variant = runtime.call("current_right_target_world")
    var left_target_variant: Variant = runtime.call("current_support_target_world")
    if not right_target_variant is Vector3 or not left_target_variant is Vector3:
        _fail("runtime did not expose vector hand targets")
        return

    var right_target := right_target_variant as Vector3
    var left_target := left_target_variant as Vector3
    if right_target == Vector3.INF or left_target == Vector3.INF:
        _fail("runtime targets remained unresolved")
        return

    var posed_right := _bone_world_position(skeleton, right_hand)
    var posed_left := _bone_world_position(skeleton, left_hand)
    var right_gap := posed_right.distance_to(right_target)
    var support_gap := posed_left.distance_to(left_target)
    var right_raise := posed_right.y - baseline_right.y
    var left_motion := posed_left.distance_to(baseline_left)
    var right_root := String(player.get_meta("combat_upper_body_right_root", ""))
    var left_root := String(player.get_meta("combat_upper_body_left_root", ""))
    var right_forearm := String(player.get_meta("combat_upper_body_right_forearm", ""))
    var left_forearm := String(player.get_meta("combat_upper_body_left_forearm", ""))

    print("COMBAT_WEAPON_UPPER_BODY_METRICS: weapon=%s runtime=%s right_gap=%.4f support_gap=%.4f right_raise=%.4f left_motion=%.4f right_root=%s right_forearm=%s left_root=%s left_forearm=%s right_chain=%s left_chain=%s" % [
        String(WEAPON_ID),
        String(runtime_info.get("source", "unknown")),
        right_gap,
        support_gap,
        right_raise,
        left_motion,
        right_root,
        right_forearm,
        left_root,
        left_forearm,
        _chain_names(skeleton, right_hand),
        _chain_names(skeleton, left_hand),
    ])

    if right_gap > MAX_HAND_TARGET_GAP_M:
        _fail("right hand misses carry target: %.3fm" % right_gap)
        return
    if support_gap > MAX_HAND_TARGET_GAP_M:
        _fail("support hand misses foregrip target: %.3fm" % support_gap)
        return
    if right_raise < MIN_RIGHT_HAND_RAISE_M:
        _fail("right hand remained too low: raised only %.3fm" % right_raise)
        return

    print("COMBAT_WEAPON_UPPER_BODY_METRICS_OK: runtime=%s right_gap=%.3f support_gap=%.3f raise=%.3f left_motion=%.3f root=%s forearm=%s" % [String(runtime_info.get("source", "unknown")), right_gap, support_gap, right_raise, left_motion, right_root, right_forearm])
    quit(0)