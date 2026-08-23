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

    var source_snapshot := _snapshot_mapped_bones(source_skeleton, 0)
    var target_snapshot := _snapshot_mapped_bones(target_skeleton, 1)
    var source_version_before := source_skeleton.get_version()
    var target_version_before := target_skeleton.get_version()

    var source_renamed := _canonicalize(source_skeleton, 0)
    var target_renamed := _canonicalize(target_skeleton, 1)

    _verify_snapshot_unchanged(source_skeleton, source_snapshot, "source")
    _verify_snapshot_unchanged(target_skeleton, target_snapshot, "target")

    var common_roles := 0
    for role: String in ROLE_PAIRS:
        var canonical := _canonical_name(role)
        var source_idx := source_skeleton.find_bone(canonical)
        var target_idx := target_skeleton.find_bone(canonical)
        if source_idx < 0 or target_idx < 0:
            _failures.append("canonical_role_missing role=%s source_idx=%d target_idx=%d" % [role, source_idx, target_idx])
            continue
        common_roles += 1

    if source_renamed != ROLE_PAIRS.size() or target_renamed != ROLE_PAIRS.size():
        _failures.append("canonical_rename_count source=%d target=%d expected=%d" % [source_renamed, target_renamed, ROLE_PAIRS.size()])
    if common_roles != ROLE_PAIRS.size():
        _failures.append("canonical_common_role_count=%d expected=%d" % [common_roles, ROLE_PAIRS.size()])
    if source_skeleton.get_version() <= source_version_before:
        _failures.append("source_skeleton_version_did_not_advance")
    if target_skeleton.get_version() <= target_version_before:
        _failures.append("target_skeleton_version_did_not_advance")

    var result := {
        "format": "grand-bruxelles-gate8-variant01-native-canonical-names-v1",
        "engine_version": Engine.get_version_info().get("string", "unknown"),
        "candidate_variant": 1,
        "reviewed_roles": ROLE_PAIRS.size(),
        "source_renamed_roles": source_renamed,
        "target_renamed_roles": target_renamed,
        "canonical_common_role_count": common_roles,
        "canonical_prefix": "gb_humanoid_",
        "rest_pose_unchanged": _failures.filter(func(item: String) -> bool: return item.contains("rest_changed")).is_empty(),
        "parent_topology_unchanged": _failures.filter(func(item: String) -> bool: return item.contains("parent_changed")).is_empty(),
        "bone_indices_unchanged": _failures.filter(func(item: String) -> bool: return item.contains("index_changed")).is_empty(),
        "canonicalization_runtime_only": true,
        "source_asset_modified": false,
        "target_asset_modified": false,
        "retarget_applied": false,
        "run_alias_selected": "",
        "production_authorized": false,
        "activation_ready": false,
        "adoption_ready": false,
        "selection_state": "READY_CANONICAL_NATIVE_AB" if _failures.is_empty() else "BLOCKED_CANONICALIZATION_INTEGRITY",
        "failures": _failures
    }
    _write_result(result)
    print("GATE8_NATIVE_CANONICAL_NAMES roles=%d source_renamed=%d target_renamed=%d common=%d rest_unchanged=%s topology_unchanged=%s state=%s" % [ROLE_PAIRS.size(), source_renamed, target_renamed, common_roles, str(result["rest_pose_unchanged"]), str(result["parent_topology_unchanged"]), result["selection_state"]])
    _finish(result)

func _canonicalize(skeleton: Skeleton3D, side: int) -> int:
    var renamed := 0
    var planned := {}
    for role: String in ROLE_PAIRS:
        var canonical := _canonical_name(role)
        if skeleton.find_bone(canonical) >= 0:
            _failures.append("canonical_name_collision role=%s name=%s" % [role, canonical])
            continue
        planned[role] = canonical
    if planned.size() != ROLE_PAIRS.size():
        return 0

    for role: String in ROLE_PAIRS:
        var pair: Array = ROLE_PAIRS[role]
        var original_name := String(pair[side])
        var idx := skeleton.find_bone(original_name)
        if idx < 0:
            _failures.append("original_bone_missing role=%s side=%d bone=%s" % [role, side, original_name])
            continue
        skeleton.set_bone_name(idx, String(planned[role]))
        if skeleton.get_bone_name(idx) != String(planned[role]):
            _failures.append("rename_failed role=%s side=%d" % [role, side])
            continue
        if skeleton.find_bone(original_name) >= 0:
            _failures.append("original_name_still_present role=%s side=%d bone=%s" % [role, side, original_name])
            continue
        renamed += 1
    return renamed

func _snapshot_mapped_bones(skeleton: Skeleton3D, side: int) -> Dictionary:
    var snapshot := {}
    for role: String in ROLE_PAIRS:
        var pair: Array = ROLE_PAIRS[role]
        var name := String(pair[side])
        var idx := skeleton.find_bone(name)
        if idx < 0:
            _failures.append("snapshot_bone_missing role=%s side=%d bone=%s" % [role, side, name])
            continue
        snapshot[role] = {
            "index": idx,
            "parent": skeleton.get_bone_parent(idx),
            "rest": skeleton.get_bone_rest(idx)
        }
    return snapshot

func _verify_snapshot_unchanged(skeleton: Skeleton3D, snapshot: Dictionary, label: String) -> void:
    for role_value: Variant in snapshot.keys():
        var role := String(role_value)
        var row: Dictionary = snapshot[role]
        var canonical := _canonical_name(role)
        var idx := skeleton.find_bone(canonical)
        if idx != int(row["index"]):
            _failures.append("index_changed label=%s role=%s before=%d after=%d" % [label, role, int(row["index"]), idx])
            continue
        var parent_before := int(row["parent"])
        var parent_after := skeleton.get_bone_parent(idx)
        if parent_after != parent_before:
            _failures.append("parent_changed label=%s role=%s before=%d after=%d" % [label, role, parent_before, parent_after])
        var rest_before: Transform3D = row["rest"]
        var rest_after := skeleton.get_bone_rest(idx)
        if not rest_after.is_equal_approx(rest_before):
            _failures.append("rest_changed label=%s role=%s" % [label, role])

func _canonical_name(role: String) -> String:
    return "gb_humanoid_%s" % role

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
    var file := FileAccess.open("res://gate8_variant01_native_canonical_names_result.json", FileAccess.WRITE)
    if file == null:
        _failures.append("result_file_open_failed")
        return
    file.store_string(JSON.stringify(result, "  "))
    file.close()

func _finish(_result: Dictionary) -> void:
    if _failures.is_empty():
        print("GATE8_NATIVE_CANONICAL_NAMES_OK roles=22 rest_pose_unchanged=true topology_unchanged=true retarget_applied=false production_authorized=false")
        quit(0)
        return
    for failure: String in _failures:
        push_error("GATE8_NATIVE_CANONICAL_NAMES_FAIL %s" % failure)
    quit(1)
