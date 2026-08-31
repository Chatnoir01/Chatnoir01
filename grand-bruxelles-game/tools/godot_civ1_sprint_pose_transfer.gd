extends SceneTree

const SOURCE_ANIMATION := "UAL1_Standard/Sprint"
const SOURCE_SCENE_SUFFIX := "Models_with_rigging/Master_Rigged.tscn"
const TARGET_SCENE := "res://civ1_body.glb"
const SAMPLE_COUNT := 121
const MAX_NORMALIZED_FOOT_MOTION_GAIN := 1.5
const TARGET_SUPPORT_BAND_FRACTION := 0.10

const REQUIRED_SEMANTICS := [
    "Hips", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
    "RightUpperLeg", "RightLowerLeg", "RightFoot",
    "Spine", "Chest", "Neck", "Head",
    "LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
    "RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
]

const ALIASES := {
    "Hips": ["hips", "pelvis"],
    "LeftUpperLeg": ["leftupperleg", "leftupleg", "lupperleg"],
    "LeftLowerLeg": ["leftlowerleg", "leftleg", "llowerleg"],
    "LeftFoot": ["leftfoot", "lfoot"],
    "RightUpperLeg": ["rightupperleg", "rightupleg", "rupperleg"],
    "RightLowerLeg": ["rightlowerleg", "rightleg", "rlowerleg"],
    "RightFoot": ["rightfoot", "rfoot"],
    "Spine": ["spine"],
    "Chest": ["chest", "spine1"],
    "Neck": ["neck"],
    "Head": ["head"],
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

func _normalize_bone_name(value: String) -> String:
    var n := value.to_lower()
    for token in [":", "/", ".", "-", "_", " "]:
        n = n.replace(token, "")
    for prefix in ["mixamorig", "armature", "general", "def"]:
        if n.begins_with(prefix):
            n = n.trim_prefix(prefix)
    return n

func _bone_index_by_semantic(skeleton: Skeleton3D, semantic: String) -> int:
    var aliases: Array = ALIASES.get(semantic, [_normalize_bone_name(semantic)])
    for i in range(skeleton.get_bone_count()):
        var normalized := _normalize_bone_name(skeleton.get_bone_name(i))
        for alias in aliases:
            if normalized == String(alias):
                return i
    return -1

func _mapping_for(skeleton: Skeleton3D) -> Dictionary:
    var mapped := {}
    var missing: Array[String] = []
    for semantic in REQUIRED_SEMANTICS:
        var idx := _bone_index_by_semantic(skeleton, semantic)
        if idx < 0:
            missing.append(semantic)
        else:
            mapped[semantic] = idx
    return {"mapped": mapped, "missing": missing}

func _rest_span(skeleton: Skeleton3D, mapping: Dictionary) -> float:
    var mapped: Dictionary = mapping["mapped"]
    return skeleton.get_bone_global_rest(int(mapped["Hips"])).origin.distance_to(skeleton.get_bone_global_rest(int(mapped["Head"])).origin)

func _rest_leg_metrics(skeleton: Skeleton3D, mapped: Dictionary, side: String) -> Dictionary:
    var hips := skeleton.get_bone_global_rest(int(mapped["Hips"])).origin
    var upper := skeleton.get_bone_global_rest(int(mapped[side + "UpperLeg"])).origin
    var lower := skeleton.get_bone_global_rest(int(mapped[side + "LowerLeg"])).origin
    var foot := skeleton.get_bone_global_rest(int(mapped[side + "Foot"])).origin
    return {
        "span_m": hips.distance_to(foot),
        "upper_leg_m": upper.distance_to(lower),
        "lower_leg_m": lower.distance_to(foot),
    }

func _apply_rest_normalized_rotation_with_scaled_hips_translation(source: Skeleton3D, target: Skeleton3D, source_map: Dictionary, target_map: Dictionary, scale_ratio: float) -> int:
    var applied := 0
    for semantic in REQUIRED_SEMANTICS:
        var source_idx := int(source_map[semantic])
        var target_idx := int(target_map[semantic])
        var source_rest := source.get_bone_rest(source_idx)
        var source_pose := source.get_bone_pose(source_idx)
        var rest_normalized_global_delta := source_rest.affine_inverse() * source_pose
        var target_rest := target.get_bone_rest(target_idx)
        var rotation_only_delta := Transform3D(rest_normalized_global_delta.basis.orthonormalized(), Vector3.ZERO)
        var desired := target_rest * rotation_only_delta
        var desired_position := target_rest.origin
        if semantic == "Hips":
            desired_position = target_rest.origin + (rest_normalized_global_delta.origin * scale_ratio)
        target.set_bone_pose_position(target_idx, desired_position)
        target.set_bone_pose_rotation(target_idx, desired.basis.get_rotation_quaternion())
        target.set_bone_pose_scale(target_idx, Vector3.ONE)
        applied += 1
    return applied

func _range_m(points: Array[Vector3]) -> float:
    if points.is_empty():
        return 0.0
    var min_v := points[0]
    var max_v := points[0]
    for p in points:
        min_v.x = minf(min_v.x, p.x)
        min_v.y = minf(min_v.y, p.y)
        min_v.z = minf(min_v.z, p.z)
        max_v.x = maxf(max_v.x, p.x)
        max_v.y = maxf(max_v.y, p.y)
        max_v.z = maxf(max_v.z, p.z)
    return min_v.distance_to(max_v)

func _percentile(values: Array[float], fraction: float) -> float:
    if values.is_empty():
        return 0.0
    var ordered := values.duplicate()
    ordered.sort()
    var idx := clampi(int(round(fraction * float(ordered.size() - 1))), 0, ordered.size() - 1)
    return ordered[idx]

func _support_metrics(points: Array[Vector3], animation_length: float) -> Dictionary:
    var usable_count := points.size() - 1
    var min_y := INF
    var max_y := -INF
    for i in range(usable_count):
        min_y = minf(min_y, points[i].y)
        max_y = maxf(max_y, points[i].y)
    var threshold := min_y + ((max_y - min_y) * TARGET_SUPPORT_BAND_FRACTION)
    var low_samples := 0
    for i in range(usable_count):
        if points[i].y <= threshold:
            low_samples += 1
    var dt := animation_length / float(SAMPLE_COUNT - 1)
    var speeds: Array[float] = []
    var horizontal_path := 0.0
    for i in range(usable_count - 1):
        if points[i].y <= threshold and points[i + 1].y <= threshold:
            var a := Vector2(points[i].x, points[i].z)
            var b := Vector2(points[i + 1].x, points[i + 1].z)
            var distance := a.distance_to(b)
            horizontal_path += distance
            speeds.append(distance / dt if dt > 0.0 else 0.0)
    return {
        "support_band_fraction": TARGET_SUPPORT_BAND_FRACTION,
        "min_y_m": min_y,
        "max_y_m": max_y,
        "threshold_y_m": threshold,
        "low_height_sample_count": low_samples,
        "low_height_segment_count": speeds.size(),
        "horizontal_path_m": horizontal_path,
        "median_horizontal_speed_mps": _percentile(speeds, 0.50),
        "p90_horizontal_speed_mps": _percentile(speeds, 0.90),
        "max_horizontal_speed_mps": _percentile(speeds, 1.00),
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
        push_error("CIV1_SPRINT_POSE_TRANSFER_FAIL: expected one Master_Rigged scene")
        quit(3)
        return

    var source_packed := load(_source_scene_paths[0]) as PackedScene
    var target_packed := load(TARGET_SCENE) as PackedScene
    if source_packed == null or target_packed == null:
        push_error("CIV1_SPRINT_POSE_TRANSFER_FAIL: source or target load failed")
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
        push_error("CIV1_SPRINT_POSE_TRANSFER_FAIL: Sprint missing")
        quit(5)
        return

    var source_skeletons: Array[Skeleton3D] = []
    var target_skeletons: Array[Skeleton3D] = []
    _collect_skeletons(source_instance, source_skeletons)
    _collect_skeletons(target_instance, target_skeletons)
    if source_skeletons.is_empty() or target_skeletons.size() != 1:
        push_error("CIV1_SPRINT_POSE_TRANSFER_FAIL: unexpected skeleton inventory")
        quit(6)
        return

    var source_skeleton := source_skeletons[0]
    var player_root := player.get_node_or_null(NodePath(player.root_node))
    if player_root is Skeleton3D:
        source_skeleton = player_root as Skeleton3D
    var target_skeleton := target_skeletons[0]
    var source_mapping := _mapping_for(source_skeleton)
    var target_mapping := _mapping_for(target_skeleton)
    if not (source_mapping["missing"] as Array).is_empty() or not (target_mapping["missing"] as Array).is_empty():
        push_error("CIV1_SPRINT_POSE_TRANSFER_FAIL: required humanoid mapping incomplete")
        quit(7)
        return

    var source_span := _rest_span(source_skeleton, source_mapping)
    var target_span := _rest_span(target_skeleton, target_mapping)
    var scale_ratio := target_span / source_span if source_span > 0.000001 else 0.0
    if scale_ratio <= 0.2 or scale_ratio >= 5.0:
        push_error("CIV1_SPRINT_POSE_TRANSFER_FAIL: invalid rest scale ratio")
        quit(8)
        return

    var source_map: Dictionary = source_mapping["mapped"]
    var target_map: Dictionary = target_mapping["mapped"]
    var source_left_leg := _rest_leg_metrics(source_skeleton, source_map, "Left")
    var source_right_leg := _rest_leg_metrics(source_skeleton, source_map, "Right")
    var target_left_leg := _rest_leg_metrics(target_skeleton, target_map, "Left")
    var target_right_leg := _rest_leg_metrics(target_skeleton, target_map, "Right")
    var left_leg_scale_ratio := float(target_left_leg["span_m"]) / float(source_left_leg["span_m"]) if float(source_left_leg["span_m"]) > 0.000001 else 0.0
    var right_leg_scale_ratio := float(target_right_leg["span_m"]) / float(source_right_leg["span_m"]) if float(source_right_leg["span_m"]) > 0.000001 else 0.0
    if left_leg_scale_ratio <= 0.2 or left_leg_scale_ratio >= 5.0 or right_leg_scale_ratio <= 0.2 or right_leg_scale_ratio >= 5.0:
        push_error("CIV1_SPRINT_POSE_TRANSFER_FAIL: invalid side-specific leg scale ratio")
        quit(9)
        return

    var animation := player.get_animation(SOURCE_ANIMATION)
    if animation == null or animation.length <= 0.0:
        push_error("CIV1_SPRINT_POSE_TRANSFER_FAIL: invalid Sprint animation")
        quit(10)
        return

    var source_left_idx := int(source_map["LeftFoot"])
    var source_right_idx := int(source_map["RightFoot"])
    var target_left_idx := int(target_map["LeftFoot"])
    var target_right_idx := int(target_map["RightFoot"])
    var source_left_points: Array[Vector3] = []
    var source_right_points: Array[Vector3] = []
    var target_left_points: Array[Vector3] = []
    var target_right_points: Array[Vector3] = []
    var applied_per_sample := 0

    player.play(SOURCE_ANIMATION)
    player.advance(0.0)
    await process_frame

    for sample_idx in range(SAMPLE_COUNT):
        var t := animation.length * float(sample_idx) / float(SAMPLE_COUNT - 1)
        player.seek(t, true)
        player.advance(0.0)
        await process_frame
        source_left_points.append(source_skeleton.get_bone_global_pose(source_left_idx).origin)
        source_right_points.append(source_skeleton.get_bone_global_pose(source_right_idx).origin)
        applied_per_sample = _apply_rest_normalized_rotation_with_scaled_hips_translation(source_skeleton, target_skeleton, source_map, target_map, scale_ratio)
        await process_frame
        target_left_points.append(target_skeleton.get_bone_global_pose(target_left_idx).origin)
        target_right_points.append(target_skeleton.get_bone_global_pose(target_right_idx).origin)

    var source_left_range := _range_m(source_left_points)
    var source_right_range := _range_m(source_right_points)
    var target_left_range := _range_m(target_left_points)
    var target_right_range := _range_m(target_right_points)
    var torso_scaled_source_left := source_left_range * scale_ratio
    var torso_scaled_source_right := source_right_range * scale_ratio
    var left_gain_vs_torso := target_left_range / torso_scaled_source_left if torso_scaled_source_left > 0.000001 else 999.0
    var right_gain_vs_torso := target_right_range / torso_scaled_source_right if torso_scaled_source_right > 0.000001 else 999.0
    var leg_scaled_source_left := source_left_range * left_leg_scale_ratio
    var leg_scaled_source_right := source_right_range * right_leg_scale_ratio
    var left_gain_vs_leg := target_left_range / leg_scaled_source_left if leg_scaled_source_left > 0.000001 else 999.0
    var right_gain_vs_leg := target_right_range / leg_scaled_source_right if leg_scaled_source_right > 0.000001 else 999.0
    var motion_plausible := left_gain_vs_leg <= MAX_NORMALIZED_FOOT_MOTION_GAIN and right_gain_vs_leg <= MAX_NORMALIZED_FOOT_MOTION_GAIN
    var target_left_support := _support_metrics(target_left_points, animation.length)
    var target_right_support := _support_metrics(target_right_points, animation.length)
    var support_measurement_ready := int(target_left_support["low_height_segment_count"]) > 0 and int(target_right_support["low_height_segment_count"]) > 0
    var transfer_ok := applied_per_sample == REQUIRED_SEMANTICS.size() and target_left_range > 0.05 and target_right_range > 0.05 and motion_plausible and support_measurement_ready

    var payload := {
        "format": "grand-bruxelles-civ1-sprint-pose-transfer-v4",
        "godot_version": Engine.get_version_info(),
        "source_animation": SOURCE_ANIMATION,
        "transfer_method": "rest_normalized_rotation_scaled_hips_translation",
        "sample_count": SAMPLE_COUNT,
        "source_bone_count": source_skeleton.get_bone_count(),
        "target_bone_count": target_skeleton.get_bone_count(),
        "mapped_required_bones": REQUIRED_SEMANTICS.size(),
        "source_to_target_scale_ratio": scale_ratio,
        "source_left_leg_span_m": source_left_leg["span_m"],
        "source_right_leg_span_m": source_right_leg["span_m"],
        "target_left_leg_span_m": target_left_leg["span_m"],
        "target_right_leg_span_m": target_right_leg["span_m"],
        "source_left_upper_leg_m": source_left_leg["upper_leg_m"],
        "source_left_lower_leg_m": source_left_leg["lower_leg_m"],
        "source_right_upper_leg_m": source_right_leg["upper_leg_m"],
        "source_right_lower_leg_m": source_right_leg["lower_leg_m"],
        "target_left_upper_leg_m": target_left_leg["upper_leg_m"],
        "target_left_lower_leg_m": target_left_leg["lower_leg_m"],
        "target_right_upper_leg_m": target_right_leg["upper_leg_m"],
        "target_right_lower_leg_m": target_right_leg["lower_leg_m"],
        "left_leg_scale_ratio": left_leg_scale_ratio,
        "right_leg_scale_ratio": right_leg_scale_ratio,
        "source_left_foot_range_m": source_left_range,
        "source_right_foot_range_m": source_right_range,
        "target_left_foot_range_m": target_left_range,
        "target_right_foot_range_m": target_right_range,
        "left_motion_gain_vs_scaled_source": left_gain_vs_torso,
        "right_motion_gain_vs_scaled_source": right_gain_vs_torso,
        "left_motion_gain_vs_leg_scaled_source": left_gain_vs_leg,
        "right_motion_gain_vs_leg_scaled_source": right_gain_vs_leg,
        "max_normalized_foot_motion_gain": MAX_NORMALIZED_FOOT_MOTION_GAIN,
        "motion_plausibility_passed": motion_plausible,
        "target_left_support_candidate": target_left_support,
        "target_right_support_candidate": target_right_support,
        "target_support_candidate_measurement_ready": support_measurement_ready,
        "terminal_loop_sample_excluded_from_speed": true,
        "animation_transferred": transfer_ok,
        "diagnostic_only": true,
        "run_alias_selected": false,
        "world_ground_assumed": false,
        "grounding_verified": false,
        "foot_slide_verified": false,
        "runtime_authorized": false,
        "visual_approval_claimed": false,
    }

    if not _write_payload(payload):
        quit(11)
        return
    if not transfer_ok:
        push_error("CIV1_SPRINT_POSE_TRANSFER_FAIL: bilateral motion, plausibility, or target support measurement gate failed")
        quit(12)
        return
    print("CIV1_SPRINT_POSE_TRANSFER_OK")
    quit(0)
