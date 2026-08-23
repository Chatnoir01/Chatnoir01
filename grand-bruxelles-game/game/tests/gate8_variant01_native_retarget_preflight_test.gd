extends SceneTree

const SOURCE_SCENE := "res://assets/animation_source.glb"
const TARGET_SCENE := "res://assets/npc_gate_01.glb"
const ROLE_PAIRS := {
    "hips": ["DEF-hips", "pelvis"],
    "spine": ["DEF-spine.001", "spine_01"],
    "chest": ["DEF-spine.002", "spine_02"],
    "upper_chest": ["DEF-spine.003", "spine_03"],
    "neck": ["DEF-neck", "neck_01"],
    "head": ["DEF-head", "head"],
    "left_shoulder": ["DEF-shoulder.L", "clavicle_l"],
    "left_upper_arm": ["DEF-upper_arm.L", "upperarm_l"],
    "left_forearm": ["DEF-forearm.L", "lowerarm_l"],
    "left_hand": ["DEF-hand.L", "hand_l"],
    "right_shoulder": ["DEF-shoulder.R", "clavicle_r"],
    "right_upper_arm": ["DEF-upper_arm.R", "upperarm_r"],
    "right_forearm": ["DEF-forearm.R", "lowerarm_r"],
    "right_hand": ["DEF-hand.R", "hand_r"],
    "left_upper_leg": ["DEF-thigh.L", "thigh_l"],
    "left_lower_leg": ["DEF-shin.L", "calf_l"],
    "left_foot": ["DEF-foot.L", "foot_l"],
    "left_toe": ["DEF-toe.L", "ball_l"],
    "right_upper_leg": ["DEF-thigh.R", "thigh_r"],
    "right_lower_leg": ["DEF-shin.R", "calf_r"],
    "right_foot": ["DEF-foot.R", "foot_r"],
    "right_toe": ["DEF-toe.R", "ball_r"]
}

var _failures: Array[String] = []

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var source := _instantiate(SOURCE_SCENE)
    var target := _instantiate(TARGET_SCENE)
    if source == null or target == null:
        _finish({})
        return
    root.add_child(source)
    root.add_child(target)
    await process_frame

    var source_skeleton := _find_skeleton(source)
    var target_skeleton := _find_skeleton(target)
    if source_skeleton == null or target_skeleton == null:
        _failures.append("skeleton_missing")
        _finish({})
        return

    var same_name_roles: Array[String] = []
    var heteronymous_roles: Array[String] = []
    for role: String in ROLE_PAIRS:
        var pair: Array = ROLE_PAIRS[role]
        var source_name := String(pair[0])
        var target_name := String(pair[1])
        var source_idx := source_skeleton.find_bone(source_name)
        var target_idx := target_skeleton.find_bone(target_name)
        if source_idx < 0:
            _failures.append("source_role_missing=%s bone=%s" % [role, source_name])
            continue
        if target_idx < 0:
            _failures.append("target_role_missing=%s bone=%s" % [role, target_name])
            continue
        if source_name == target_name:
            same_name_roles.append(role)
        else:
            heteronymous_roles.append(role)

    if ROLE_PAIRS.size() != 22:
        _failures.append("reviewed_role_count_changed=%d" % ROLE_PAIRS.size())
    if heteronymous_roles.is_empty():
        _failures.append("native_name_blocker_unexpectedly_absent")

    var modifier := RetargetModifier3D.new()
    modifier.set_use_global_pose(false)
    modifier.set_position_enabled(false)
    modifier.set_rotation_enabled(true)
    modifier.set_scale_enabled(false)
    if modifier.is_using_global_pose():
        _failures.append("native_modifier_global_pose_must_be_false")
    if modifier.is_position_enabled():
        _failures.append("native_modifier_position_must_be_disabled_for_preflight")
    if not modifier.is_rotation_enabled():
        _failures.append("native_modifier_rotation_must_be_enabled")
    if modifier.is_scale_enabled():
        _failures.append("native_modifier_scale_must_be_disabled")
    modifier.free()

    var direct_native_ready := heteronymous_roles.is_empty()
    var result := {
        "format": "grand-bruxelles-gate8-variant01-native-retarget-preflight-v1",
        "engine_version": Engine.get_version_info().get("string", "unknown"),
        "candidate_variant": 1,
        "reviewed_roles": ROLE_PAIRS.size(),
        "same_name_roles": same_name_roles,
        "same_name_role_count": same_name_roles.size(),
        "heteronymous_roles": heteronymous_roles,
        "heteronymous_role_count": heteronymous_roles.size(),
        "retarget_modifier_available": ClassDB.class_exists("RetargetModifier3D"),
        "use_global_pose": false,
        "position_enabled": false,
        "rotation_enabled": true,
        "scale_enabled": false,
        "direct_native_ready": direct_native_ready,
        "selection_state": "READY_DIRECT_NATIVE" if direct_native_ready else "BLOCKED_NEEDS_CANONICAL_BONE_NAMES",
        "required_next_step": "none" if direct_native_ready else "canonicalize source and target humanoid bone names without changing rest pose, then rerun native modifier A/B",
        "run_alias_selected": "",
        "production_authorized": false,
        "activation_ready": false,
        "adoption_ready": false,
        "failures": _failures
    }
    _write_result(result)
    print("GATE8_NATIVE_RETARGET_PREFLIGHT roles=%d same_name=%d heteronymous=%d direct_native_ready=%s state=%s" % [ROLE_PAIRS.size(), same_name_roles.size(), heteronymous_roles.size(), str(direct_native_ready), result["selection_state"]])
    _finish(result)

func _instantiate(path: String) -> Node3D:
    var packed := load(path) as PackedScene
    if packed == null:
        _failures.append("scene_load_failed=%s" % path)
        return null
    var node := packed.instantiate() as Node3D
    if node == null:
        _failures.append("scene_not_node3d=%s" % path)
    return node

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D
    for child: Node in node.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null

func _write_result(result: Dictionary) -> void:
    var file := FileAccess.open("res://gate8_variant01_native_retarget_preflight_result.json", FileAccess.WRITE)
    if file == null:
        _failures.append("result_file_open_failed")
        return
    file.store_string(JSON.stringify(result, "  "))
    file.close()

func _finish(_result: Dictionary) -> void:
    if _failures.is_empty():
        print("GATE8_NATIVE_RETARGET_PREFLIGHT_OK production_authorized=false")
        quit(0)
        return
    for failure: String in _failures:
        push_error("GATE8_NATIVE_RETARGET_PREFLIGHT_FAIL %s" % failure)
    quit(1)
