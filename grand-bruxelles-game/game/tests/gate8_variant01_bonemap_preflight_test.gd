extends SceneTree

const SOURCE_SCENE := "res://assets/animation_source.glb"
const TARGET_SCENE := "res://assets/npc_gate_01.glb"
const REQUIRED_ROLES: Array[String] = [
    "hips", "spine", "chest", "neck", "head",
    "left_upper_arm", "left_forearm", "left_hand",
    "right_upper_arm", "right_forearm", "right_hand",
    "left_upper_leg", "left_lower_leg", "left_foot",
    "right_upper_leg", "right_lower_leg", "right_foot"
]

const ROLE_ALIASES := {
    "hips": ["hips", "pelvis", "hip"],
    "spine": ["spine", "spine01", "spine1"],
    "chest": ["chest", "spine02", "spine2", "spine03", "spine3"],
    "neck": ["neck", "neck01", "neck1"],
    "head": ["head"],
    "left_upper_arm": ["leftarm", "upperarml", "lupperarm", "armleft"],
    "left_forearm": ["leftforearm", "lowerarml", "forearml", "lforearm"],
    "left_hand": ["lefthand", "handl", "lhand"],
    "right_upper_arm": ["rightarm", "upperarmr", "rupperarm", "armright"],
    "right_forearm": ["rightforearm", "lowerarmr", "forearmr", "rforearm"],
    "right_hand": ["righthand", "handr", "rhand"],
    "left_upper_leg": ["leftupleg", "leftupperleg", "thighl", "upperlegl", "lthigh"],
    "left_lower_leg": ["leftleg", "leftlowerleg", "calfl", "lowerlegl", "lcalf"],
    "left_foot": ["leftfoot", "footl", "lfoot"],
    "right_upper_leg": ["rightupleg", "rightupperleg", "thighr", "upperlegr", "rthigh"],
    "right_lower_leg": ["rightleg", "rightlowerleg", "calfr", "lowerlegr", "rcalf"],
    "right_foot": ["rightfoot", "footr", "rfoot"]
}

var _failures: Array[String] = []

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    _regression_duplicate_assignment_rejected()
    _regression_missing_role_rejected()

    var source_skeleton := await _load_skeleton(SOURCE_SCENE, "source")
    var target_skeleton := await _load_skeleton(TARGET_SCENE, "target")
    if source_skeleton == null or target_skeleton == null:
        _finish({})
        return

    var source_map := _resolve_roles(source_skeleton, "source")
    var target_map := _resolve_roles(target_skeleton, "target")
    _validate_required_roles(source_map, "source")
    _validate_required_roles(target_map, "target")
    _validate_unique_assignment(source_map, "source")
    _validate_unique_assignment(target_map, "target")
    _validate_parent_chains(source_skeleton, source_map, "source")
    _validate_parent_chains(target_skeleton, target_map, "target")

    var source_torso_bend := _torso_bend_deg(source_skeleton, source_map)
    var target_torso_bend := _torso_bend_deg(target_skeleton, target_map)
    var torso_deviation := absf(source_torso_bend - target_torso_bend)
    if torso_deviation > 25.0:
        _failures.append("torso_rest_bend_deviation_deg=%.3f limit=25.0" % torso_deviation)

    var source_leg := _mean_leg_length(source_skeleton, source_map)
    var target_leg := _mean_leg_length(target_skeleton, target_map)
    var leg_ratio := target_leg / source_leg if source_leg > 0.0001 else 0.0
    if source_leg <= 0.0001 or target_leg <= 0.0001:
        _failures.append("invalid_leg_length source=%.6f target=%.6f" % [source_leg, target_leg])
    elif leg_ratio < 0.55 or leg_ratio > 1.80:
        _failures.append("target_to_source_leg_ratio=%.4f outside=0.55..1.80" % leg_ratio)

    var source_upper_chest := _find_optional_upper_chest(source_skeleton)
    var target_upper_chest := _find_optional_upper_chest(target_skeleton)
    var result := {
        "format": "grand-bruxelles-gate8-variant01-bonemap-preflight-result-v1",
        "engine_version": Engine.get_version_info().get("string", "unknown"),
        "candidate_variant": 1,
        "source_bone_count": source_skeleton.get_bone_count(),
        "target_bone_count": target_skeleton.get_bone_count(),
        "source_roles": source_map,
        "target_roles": target_map,
        "source_upper_chest_candidates": source_upper_chest,
        "target_upper_chest_candidates": target_upper_chest,
        "source_torso_rest_bend_deg": source_torso_bend,
        "target_torso_rest_bend_deg": target_torso_bend,
        "torso_rest_bend_deviation_deg": torso_deviation,
        "source_mean_leg_length": source_leg,
        "target_mean_leg_length": target_leg,
        "target_to_source_leg_ratio": leg_ratio,
        "required_role_count": REQUIRED_ROLES.size(),
        "bonemap_ready": _failures.is_empty(),
        "bonemap_applied": false,
        "retarget_applied": false,
        "run_alias_selected": "",
        "production_authorized": false,
        "activation_ready": false,
        "visual_approval_claimed": false,
        "failures": _failures
    }
    _write_result(result)
    print("GATE8_VARIANT01_BONEMAP_PREFLIGHT candidate=01 source_bones=%d target_bones=%d roles=%d torso_deviation_deg=%.3f leg_ratio=%.4f source_upper_chest_candidates=%d target_upper_chest_candidates=%d ready=%s" % [
        source_skeleton.get_bone_count(), target_skeleton.get_bone_count(), REQUIRED_ROLES.size(), torso_deviation, leg_ratio,
        source_upper_chest.size(), target_upper_chest.size(), str(_failures.is_empty()).to_lower()
    ])
    _finish(result)

func _load_skeleton(path: String, label: String) -> Skeleton3D:
    if not ResourceLoader.exists(path):
        _failures.append("%s_scene_missing=%s" % [label, path])
        return null
    var packed := load(path) as PackedScene
    if packed == null:
        _failures.append("%s_scene_load_failed=%s" % [label, path])
        return null
    var instance := packed.instantiate()
    root.add_child(instance)
    await process_frame
    var skeleton := _find_skeleton(instance)
    if skeleton == null:
        _failures.append("%s_skeleton_missing" % label)
    return skeleton

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null

func _normalize(name: String) -> String:
    return name.to_lower().replace("_", "").replace("-", "").replace(".", "").replace(" ", "").replace(":", "")

func _resolve_roles(skeleton: Skeleton3D, label: String) -> Dictionary:
    var mapping := {}
    var normalized_names: Array[String] = []
    for bone_idx in range(skeleton.get_bone_count()):
        normalized_names.append(_normalize(skeleton.get_bone_name(bone_idx)))
    for role in REQUIRED_ROLES:
        var matches: Array[int] = []
        var aliases: Array = ROLE_ALIASES.get(role, [])
        for bone_idx in range(normalized_names.size()):
            var normalized := normalized_names[bone_idx]
            for alias_value in aliases:
                var alias := String(alias_value)
                if normalized == alias or normalized.ends_with(alias):
                    matches.append(bone_idx)
                    break
        if matches.size() == 1:
            mapping[role] = skeleton.get_bone_name(matches[0])
        elif matches.is_empty():
            mapping[role] = ""
        else:
            var names: Array[String] = []
            for idx in matches:
                names.append(skeleton.get_bone_name(idx))
            _failures.append("%s_role_ambiguous role=%s candidates=%s" % [label, role, ",".join(names)])
            mapping[role] = ""
    return mapping

func _validate_required_roles(mapping: Dictionary, label: String) -> void:
    for role in REQUIRED_ROLES:
        if String(mapping.get(role, "")).is_empty():
            _failures.append("%s_required_role_missing=%s" % [label, role])

func _validate_unique_assignment(mapping: Dictionary, label: String) -> void:
    var seen := {}
    for role in REQUIRED_ROLES:
        var bone := String(mapping.get(role, ""))
        if bone.is_empty():
            continue
        if seen.has(bone):
            _failures.append("%s_duplicate_bone_assignment bone=%s roles=%s,%s" % [label, bone, seen[bone], role])
        else:
            seen[bone] = role

func _validate_parent_chains(skeleton: Skeleton3D, mapping: Dictionary, label: String) -> void:
    var chains := [
        ["hips", "spine", "chest", "neck", "head"],
        ["left_upper_arm", "left_forearm", "left_hand"],
        ["right_upper_arm", "right_forearm", "right_hand"],
        ["left_upper_leg", "left_lower_leg", "left_foot"],
        ["right_upper_leg", "right_lower_leg", "right_foot"]
    ]
    for chain in chains:
        for i in range(chain.size() - 1):
            var parent_name := String(mapping.get(chain[i], ""))
            var child_name := String(mapping.get(chain[i + 1], ""))
            if parent_name.is_empty() or child_name.is_empty():
                continue
            var parent_idx := skeleton.find_bone(parent_name)
            var child_idx := skeleton.find_bone(child_name)
            if parent_idx < 0 or child_idx < 0 or not _is_ancestor(skeleton, parent_idx, child_idx):
                _failures.append("%s_parent_chain_invalid=%s>%s" % [label, chain[i], chain[i + 1]])

func _is_ancestor(skeleton: Skeleton3D, ancestor_idx: int, child_idx: int) -> bool:
    var cursor := child_idx
    while cursor >= 0:
        cursor = skeleton.get_bone_parent(cursor)
        if cursor == ancestor_idx:
            return true
    return false

func _bone_global_rest(skeleton: Skeleton3D, bone_idx: int) -> Transform3D:
    var chain: Array[int] = []
    var cursor := bone_idx
    while cursor >= 0:
        chain.push_front(cursor)
        cursor = skeleton.get_bone_parent(cursor)
    var result := Transform3D.IDENTITY
    for idx in chain:
        result = result * skeleton.get_bone_rest(idx)
    return result

func _bone_position(skeleton: Skeleton3D, mapping: Dictionary, role: String) -> Vector3:
    var bone_name := String(mapping.get(role, ""))
    var idx := skeleton.find_bone(bone_name)
    if idx < 0:
        return Vector3.ZERO
    return _bone_global_rest(skeleton, idx).origin

func _torso_bend_deg(skeleton: Skeleton3D, mapping: Dictionary) -> float:
    var hips := _bone_position(skeleton, mapping, "hips")
    var spine := _bone_position(skeleton, mapping, "spine")
    var chest := _bone_position(skeleton, mapping, "chest")
    var neck := _bone_position(skeleton, mapping, "neck")
    var lower := (chest - spine).normalized()
    var upper := (neck - chest).normalized()
    if lower.length_squared() < 0.5 or upper.length_squared() < 0.5:
        return 180.0
    return rad_to_deg(lower.angle_to(upper))

func _mean_leg_length(skeleton: Skeleton3D, mapping: Dictionary) -> float:
    var values: Array[float] = []
    for side in ["left", "right"]:
        var upper := _bone_position(skeleton, mapping, "%s_upper_leg" % side)
        var lower := _bone_position(skeleton, mapping, "%s_lower_leg" % side)
        var foot := _bone_position(skeleton, mapping, "%s_foot" % side)
        values.append(upper.distance_to(lower) + lower.distance_to(foot))
    return (values[0] + values[1]) * 0.5

func _find_optional_upper_chest(skeleton: Skeleton3D) -> Array[String]:
    var result: Array[String] = []
    for idx in range(skeleton.get_bone_count()):
        var normalized := _normalize(skeleton.get_bone_name(idx))
        if normalized.contains("upperchest") or normalized.contains("spine03") or normalized.contains("spine3"):
            result.append(skeleton.get_bone_name(idx))
    return result

func _regression_duplicate_assignment_rejected() -> void:
    var mapping := {}
    for role in REQUIRED_ROLES:
        mapping[role] = role
    mapping["left_hand"] = "left_forearm"
    var before := _failures.size()
    _validate_unique_assignment(mapping, "regression")
    if _failures.size() == before:
        _failures.append("regression_duplicate_assignment_not_detected")
    else:
        _failures.resize(before)

func _regression_missing_role_rejected() -> void:
    var mapping := {}
    for role in REQUIRED_ROLES:
        mapping[role] = role
    mapping["head"] = ""
    var before := _failures.size()
    _validate_required_roles(mapping, "regression")
    if _failures.size() == before:
        _failures.append("regression_missing_role_not_detected")
    else:
        _failures.resize(before)

func _write_result(result: Dictionary) -> void:
    var file := FileAccess.open("res://gate8_variant01_bonemap_preflight_result.json", FileAccess.WRITE)
    if file == null:
        _failures.append("result_file_open_failed")
        return
    file.store_string(JSON.stringify(result, "  "))
    file.close()

func _finish(_result: Dictionary) -> void:
    if _failures.is_empty():
        print("GATE8_VARIANT01_BONEMAP_PREFLIGHT_OK candidate=01 bonemap_ready=true bonemap_applied=false retarget_applied=false alias_selected=false production_authorized=false")
        quit(0)
        return
    for failure in _failures:
        push_error("GATE8_VARIANT01_BONEMAP_PREFLIGHT_FAIL %s" % failure)
    quit(1)
