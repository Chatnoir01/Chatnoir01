extends SceneTree

const SOURCE_ANIMATION := "UAL1_Standard/Sprint"
const SOURCE_SCENE_SUFFIX := "Models_with_rigging/Master_Rigged.tscn"
const TARGET_SCENE := "res://civ1_body.glb"
const SAMPLE_COUNT := 121
const PHASE_DIVERGENCE_MATERIAL_SAMPLES := 12
const SEMANTICS := [
    "Hips", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
    "RightUpperLeg", "RightLowerLeg", "RightFoot",
    "Spine", "Chest", "Neck", "Head",
    "LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
    "RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
]
const DIAGNOSTIC_BONES := [
    "Hips", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
    "RightUpperLeg", "RightLowerLeg", "RightFoot",
]
const PHASE_CHAIN_ORDER := [
    "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
    "RightUpperLeg", "RightLowerLeg", "RightFoot",
]
const SEMANTIC_PARENT := {
    "LeftUpperLeg": "Hips", "LeftLowerLeg": "LeftUpperLeg", "LeftFoot": "LeftLowerLeg",
    "RightUpperLeg": "Hips", "RightLowerLeg": "RightUpperLeg", "RightFoot": "RightLowerLeg",
    "Spine": "Hips", "Chest": "Spine", "Neck": "Chest", "Head": "Neck",
    "LeftShoulder": "Chest", "LeftUpperArm": "LeftShoulder", "LeftLowerArm": "LeftUpperArm", "LeftHand": "LeftLowerArm",
    "RightShoulder": "Chest", "RightUpperArm": "RightShoulder", "RightLowerArm": "RightUpperArm", "RightHand": "RightLowerArm",
}
const ALIASES := {
    "Hips": ["hips", "pelvis"],
    "LeftUpperLeg": ["leftupperleg", "leftupleg", "lupperleg"],
    "LeftLowerLeg": ["leftlowerleg", "leftleg", "llowerleg"],
    "LeftFoot": ["leftfoot", "lfoot"],
    "RightUpperLeg": ["rightupperleg", "rightupleg", "rupperleg"],
    "RightLowerLeg": ["rightlowerleg", "rightleg", "rlowerleg"],
    "RightFoot": ["rightfoot", "rfoot"],
    "Spine": ["spine"], "Chest": ["chest", "spine1"], "Neck": ["neck"], "Head": ["head"],
    "LeftShoulder": ["leftshoulder", "lshoulder"],
    "LeftUpperArm": ["leftupperarm", "leftarm", "lupperarm"],
    "LeftLowerArm": ["leftlowerarm", "leftforearm", "llowerarm"],
    "LeftHand": ["lefthand", "lhand"],
    "RightShoulder": ["rightshoulder", "rshoulder"],
    "RightUpperArm": ["rightupperarm", "rightarm", "rupperarm"],
    "RightLowerArm": ["rightlowerarm", "rightforearm", "rlowerarm"],
    "RightHand": ["righthand", "rhand"],
}

var _output_path := ""
var _source_scene_paths: Array[String] = []

func _init() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 1:
        quit(2)
        return
    _output_path = args[0]
    call_deferred("_run")

func _scan_dir(path: String) -> void:
    var dir := DirAccess.open(path)
    if dir == null:
        return
    dir.list_dir_begin()
    while true:
        var name := dir.get_next()
        if name.is_empty():
            break
        if name.begins_with("."):
            continue
        var child := path.path_join(name)
        if dir.current_is_dir():
            _scan_dir(child)
        elif child.ends_with(SOURCE_SCENE_SUFFIX):
            _source_scene_paths.append(child)
    dir.list_dir_end()

func _collect_skeletons(node: Node, result: Array[Skeleton3D]) -> void:
    if node is Skeleton3D:
        result.append(node as Skeleton3D)
    for child in node.get_children():
        _collect_skeletons(child, result)

func _collect_players(node: Node, result: Array[AnimationPlayer]) -> void:
    if node is AnimationPlayer:
        result.append(node as AnimationPlayer)
    for child in node.get_children():
        _collect_players(child, result)

func _normalize(value: String) -> String:
    var n := value.to_lower()
    for token in [":", "/", ".", "-", "_", " "]:
        n = n.replace(token, "")
    for prefix in ["mixamorig", "armature", "general", "def"]:
        if n.begins_with(prefix):
            n = n.trim_prefix(prefix)
    return n

func _bone_index(skeleton: Skeleton3D, semantic: String) -> int:
    var aliases: Array = ALIASES.get(semantic, [_normalize(semantic)])
    for i in range(skeleton.get_bone_count()):
        var normalized := _normalize(skeleton.get_bone_name(i))
        for alias in aliases:
            if normalized == String(alias):
                return i
    return -1

func _mapping(skeleton: Skeleton3D) -> Dictionary:
    var result := {}
    for semantic in SEMANTICS:
        var idx := _bone_index(skeleton, semantic)
        if idx < 0:
            return {}
        result[semantic] = idx
    return result

func _v3(v: Vector3) -> Array[float]:
    return [v.x, v.y, v.z]

func _quat(q: Quaternion) -> Array[float]:
    var n := q.normalized()
    return [n.x, n.y, n.z, n.w]

func _transform_record(pose: Transform3D, rest: Transform3D, hips_pose: Transform3D) -> Dictionary:
    return {
        "model_origin": _v3(pose.origin),
        "model_rotation_xyzw": _quat(pose.basis.get_rotation_quaternion()),
        "source_motion_from_rest": _v3(pose.origin - rest.origin),
        "target_motion_from_rest": _v3(pose.origin - rest.origin),
        "hips_relative_origin": _v3(pose.origin - hips_pose.origin),
    }

func _signed_circular_delta(target_index: int, source_index: int, cycle_samples: int) -> int:
    var delta: int = target_index - source_index
    var half: int = int(cycle_samples / 2)
    while delta > half:
        delta -= cycle_samples
    while delta < -half:
        delta += cycle_samples
    return delta

func _vertical_phase_summary(samples: Array[Dictionary], animation_length: float) -> Dictionary:
    var cycle_samples: int = SAMPLE_COUNT - 1
    var summary := {}
    var first_material := ""
    for semantic in PHASE_CHAIN_ORDER:
        var source_min_index: int = -1
        var target_min_index: int = -1
        var source_min_y: float = INF
        var target_min_y: float = INF
        for sample_index in range(cycle_samples):
            var pair: Dictionary = samples[sample_index]["bones"][semantic]
            var source_y: float = float(pair["source"]["source_hips_relative_origin"][1])
            var target_y: float = float(pair["target"]["target_hips_relative_origin"][1])
            if source_y < source_min_y:
                source_min_y = source_y
                source_min_index = sample_index
            if target_y < target_min_y:
                target_min_y = target_y
                target_min_index = sample_index
        var phase_delta_samples: int = _signed_circular_delta(target_min_index, source_min_index, cycle_samples)
        var phase_delta_seconds: float = float(phase_delta_samples) * animation_length / float(cycle_samples)
        var material: bool = abs(phase_delta_samples) > PHASE_DIVERGENCE_MATERIAL_SAMPLES
        summary[semantic] = {
            "source_vertical_min_sample_index": source_min_index,
            "target_vertical_min_sample_index": target_min_index,
            "phase_delta_samples": phase_delta_samples,
            "phase_delta_seconds": phase_delta_seconds,
            "material_phase_divergence": material,
        }
        if first_material.is_empty() and material:
            first_material = semantic
    return {
        "per_bone": summary,
        "material_threshold_samples": PHASE_DIVERGENCE_MATERIAL_SAMPLES,
        "first_material_divergence_joint": first_material,
    }

func _reference_ab_summary(
    phase_vertical_summary: Dictionary,
    normalized_target_y: Array[float],
    source_reference_direction_global: Vector3,
    target_local_rest_origin: Vector3,
    normalized_target_local_rest_origin: Vector3,
    animation_length: float,
) -> Dictionary:
    var cycle_samples: int = SAMPLE_COUNT - 1
    var source_min_index: int = int(phase_vertical_summary["per_bone"]["RightFoot"]["source_vertical_min_sample_index"])
    var baseline_target_min_index: int = int(phase_vertical_summary["per_bone"]["RightFoot"]["target_vertical_min_sample_index"])
    var normalized_target_min_index: int = -1
    var normalized_min_y: float = INF
    for sample_index in range(cycle_samples):
        var y: float = normalized_target_y[sample_index]
        if y < normalized_min_y:
            normalized_min_y = y
            normalized_target_min_index = sample_index
    var baseline_phase_delta_samples: int = _signed_circular_delta(baseline_target_min_index, source_min_index, cycle_samples)
    var normalized_phase_delta_samples: int = _signed_circular_delta(normalized_target_min_index, source_min_index, cycle_samples)
    var baseline_phase_delta_seconds: float = float(baseline_phase_delta_samples) * animation_length / float(cycle_samples)
    var normalized_phase_delta_seconds: float = float(normalized_phase_delta_samples) * animation_length / float(cycle_samples)
    var baseline_abs: int = abs(baseline_phase_delta_samples)
    var normalized_abs: int = abs(normalized_phase_delta_samples)
    return {
        "method": "source_global_reference_direction_preserve_target_foot_length",
        "source_reference_direction_global": _v3(source_reference_direction_global),
        "target_local_rest_origin": _v3(target_local_rest_origin),
        "normalized_target_local_rest_origin": _v3(normalized_target_local_rest_origin),
        "target_foot_length_m": target_local_rest_origin.length(),
        "normalized_target_foot_length_m": normalized_target_local_rest_origin.length(),
        "target_foot_length_preserved": is_equal_approx(target_local_rest_origin.length(), normalized_target_local_rest_origin.length()),
        "source_vertical_min_sample_index": source_min_index,
        "baseline_target_vertical_min_sample_index": baseline_target_min_index,
        "normalized_target_vertical_min_sample_index": normalized_target_min_index,
        "baseline_phase_delta_samples": baseline_phase_delta_samples,
        "normalized_phase_delta_samples": normalized_phase_delta_samples,
        "baseline_phase_delta_seconds": baseline_phase_delta_seconds,
        "normalized_phase_delta_seconds": normalized_phase_delta_seconds,
        "normalization_improves_phase": normalized_abs < baseline_abs,
        "normalization_reaches_non_material_phase": normalized_abs <= PHASE_DIVERGENCE_MATERIAL_SAMPLES,
        "counterfactual_only": true,
    }

func _write_payload(payload: Dictionary) -> bool:
    var out := FileAccess.open(_output_path, FileAccess.WRITE)
    if out == null:
        return false
    out.store_string(JSON.stringify(payload, "  "))
    out.close()
    return true

func _run() -> void:
    _scan_dir("res://")
    _source_scene_paths.sort()
    if _source_scene_paths.size() != 1:
        push_error("CIV1_GLOBAL_CHAIN_DIAGNOSTIC_FAIL: expected one Master_Rigged scene")
        quit(3)
        return

    var source_packed := load(_source_scene_paths[0]) as PackedScene
    var target_packed := load(TARGET_SCENE) as PackedScene
    if source_packed == null or target_packed == null:
        push_error("CIV1_GLOBAL_CHAIN_DIAGNOSTIC_FAIL: source/target load failed")
        quit(4)
        return

    var source_instance := source_packed.instantiate()
    var target_instance := target_packed.instantiate()
    root.add_child(source_instance)
    root.add_child(target_instance)
    await process_frame

    var players: Array[AnimationPlayer] = []
    _collect_players(source_instance, players)
    var player: AnimationPlayer = null
    for candidate in players:
        if candidate.has_animation(SOURCE_ANIMATION):
            player = candidate
            break
    if player == null:
        push_error("CIV1_GLOBAL_CHAIN_DIAGNOSTIC_FAIL: Sprint missing")
        quit(5)
        return

    var source_skeletons: Array[Skeleton3D] = []
    var target_skeletons: Array[Skeleton3D] = []
    _collect_skeletons(source_instance, source_skeletons)
    _collect_skeletons(target_instance, target_skeletons)
    if source_skeletons.is_empty() or target_skeletons.size() != 1:
        push_error("CIV1_GLOBAL_CHAIN_DIAGNOSTIC_FAIL: unexpected skeleton inventory")
        quit(6)
        return

    var source_skeleton := source_skeletons[0]
    var player_root := player.get_node_or_null(NodePath(player.root_node))
    if player_root is Skeleton3D:
        source_skeleton = player_root as Skeleton3D
    var target_skeleton := target_skeletons[0]
    var source_map := _mapping(source_skeleton)
    var target_map := _mapping(target_skeleton)
    if source_map.size() != SEMANTICS.size() or target_map.size() != SEMANTICS.size():
        push_error("CIV1_GLOBAL_CHAIN_DIAGNOSTIC_FAIL: semantic mapping incomplete")
        quit(7)
        return

    var source_names := {}
    for semantic in SEMANTICS:
        source_names[semantic] = source_skeleton.get_bone_name(int(source_map[semantic]))
    for semantic in SEMANTICS:
        target_skeleton.set_bone_name(int(target_map[semantic]), StringName("GB_TMP_" + semantic))
    for semantic in SEMANTICS:
        target_skeleton.set_bone_name(int(target_map[semantic]), StringName(source_names[semantic]))

    var profile := SkeletonProfile.new()
    profile.set_bone_size(SEMANTICS.size())
    for i in range(SEMANTICS.size()):
        var semantic: String = SEMANTICS[i]
        var source_name := StringName(source_names[semantic])
        profile.set_bone_name(i, source_name)
        if SEMANTIC_PARENT.has(semantic):
            profile.set_bone_parent(i, StringName(source_names[String(SEMANTIC_PARENT[semantic])]))
        profile.set_reference_pose(i, source_skeleton.get_bone_global_rest(int(source_map[semantic])))
        profile.set_required(i, true)
    profile.set_scale_base_bone(StringName(source_names["Hips"]))

    var modifier := RetargetModifier3D.new()
    modifier.profile = profile
    modifier.set_use_global_pose(false)
    modifier.set_position_enabled(false)
    modifier.set_rotation_enabled(true)
    modifier.set_scale_enabled(false)
    source_skeleton.add_child(modifier)
    target_skeleton.reparent(modifier, true)
    await process_frame

    var animation := player.get_animation(SOURCE_ANIMATION)
    if animation == null or animation.length <= 0.0:
        push_error("CIV1_GLOBAL_CHAIN_DIAGNOSTIC_FAIL: invalid Sprint animation")
        quit(8)
        return

    var source_hips_idx := int(source_map["Hips"])
    var target_hips_idx := int(target_map["Hips"])
    var source_right_lower_idx := int(source_map["RightLowerLeg"])
    var source_right_foot_idx := int(source_map["RightFoot"])
    var target_right_lower_idx := int(target_map["RightLowerLeg"])
    var target_right_foot_idx := int(target_map["RightFoot"])

    var source_parent_rest := source_skeleton.get_bone_global_rest(source_right_lower_idx)
    var source_foot_rest := source_skeleton.get_bone_global_rest(source_right_foot_idx)
    var source_reference_vector_global := source_foot_rest.origin - source_parent_rest.origin
    if source_reference_vector_global.length() <= 0.000001:
        push_error("CIV1_GLOBAL_CHAIN_DIAGNOSTIC_FAIL: source RightFoot reference vector is degenerate")
        quit(10)
        return
    var source_reference_direction_global := source_reference_vector_global.normalized()
    var target_parent_rest := target_skeleton.get_bone_global_rest(target_right_lower_idx)
    var target_local_rest_origin := target_skeleton.get_bone_rest(target_right_foot_idx).origin
    if target_local_rest_origin.length() <= 0.000001:
        push_error("CIV1_GLOBAL_CHAIN_DIAGNOSTIC_FAIL: target RightFoot rest length is degenerate")
        quit(11)
        return
    var normalized_target_local_direction := (target_parent_rest.basis.inverse() * source_reference_direction_global).normalized()
    var normalized_target_local_rest_origin := normalized_target_local_direction * target_local_rest_origin.length()

    var model_space_samples: Array[Dictionary] = []
    var normalized_target_right_foot_y: Array[float] = []
    player.play(SOURCE_ANIMATION)
    player.advance(0.0)
    await process_frame
    for sample_idx in range(SAMPLE_COUNT):
        var t := animation.length * float(sample_idx) / float(SAMPLE_COUNT - 1)
        player.seek(t, true)
        player.advance(0.0)
        await process_frame
        var source_hips_pose := source_skeleton.get_bone_global_pose(source_hips_idx)
        var target_hips_pose := target_skeleton.get_bone_global_pose(target_hips_idx)
        var bones := {}
        for semantic in DIAGNOSTIC_BONES:
            var source_idx := int(source_map[semantic])
            var target_idx := int(target_map[semantic])
            var source_pose := source_skeleton.get_bone_global_pose(source_idx)
            var target_pose := target_skeleton.get_bone_global_pose(target_idx)
            var source_rest := source_skeleton.get_bone_global_rest(source_idx)
            var target_rest := target_skeleton.get_bone_global_rest(target_idx)
            var source_record := _transform_record(source_pose, source_rest, source_hips_pose)
            source_record["source_motion_from_rest"] = _v3(source_pose.origin - source_rest.origin)
            source_record.erase("target_motion_from_rest")
            source_record["source_hips_relative_origin"] = source_record["hips_relative_origin"]
            source_record.erase("hips_relative_origin")
            var target_record := _transform_record(target_pose, target_rest, target_hips_pose)
            target_record["target_motion_from_rest"] = _v3(target_pose.origin - target_rest.origin)
            target_record.erase("source_motion_from_rest")
            target_record["target_hips_relative_origin"] = target_record["hips_relative_origin"]
            target_record.erase("hips_relative_origin")
            bones[semantic] = {"source": source_record, "target": target_record}
        var target_right_parent_pose := target_skeleton.get_bone_global_pose(target_right_lower_idx)
        var normalized_target_foot_origin := target_right_parent_pose.origin + target_right_parent_pose.basis * normalized_target_local_rest_origin
        var normalized_hips_relative := normalized_target_foot_origin - target_hips_pose.origin
        normalized_target_right_foot_y.append(normalized_hips_relative.y)
        model_space_samples.append({"sample_index": sample_idx, "time_s": t, "bones": bones})

    var phase_vertical_summary := _vertical_phase_summary(model_space_samples, animation.length)
    var right_foot_reference_ab := _reference_ab_summary(
        phase_vertical_summary,
        normalized_target_right_foot_y,
        source_reference_direction_global,
        target_local_rest_origin,
        normalized_target_local_rest_origin,
        animation.length,
    )
    var payload := {
        "format": "grand-bruxelles-civ1-global-chain-diagnostic-v3",
        "godot_version": Engine.get_version_info(),
        "source_animation": SOURCE_ANIMATION,
        "sample_count": SAMPLE_COUNT,
        "retarget_modifier": "RetargetModifier3D",
        "use_global_pose": false,
        "position_enabled": false,
        "rotation_enabled": true,
        "scale_enabled": false,
        "diagnostic_bones": DIAGNOSTIC_BONES,
        "model_space_samples": model_space_samples,
        "phase_vertical_summary": phase_vertical_summary,
        "first_material_divergence_joint": phase_vertical_summary["first_material_divergence_joint"],
        "right_foot_reference_ab": right_foot_reference_ab,
        "diagnostic_only": true,
        "runtime_authorized": false,
        "visual_approval_claimed": false,
    }
    if not _write_payload(payload):
        quit(9)
        return
    print("CIV1_GLOBAL_CHAIN_DIAGNOSTIC_OK")
    quit(0)
