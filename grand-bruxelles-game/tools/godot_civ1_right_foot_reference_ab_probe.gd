extends SceneTree

const SOURCE_ANIMATION := "UAL1_Standard/Sprint"
const SOURCE_SCENE_SUFFIX := "Models_with_rigging/Master_Rigged.tscn"
const TARGET_SCENE := "res://civ1_body.glb"
const SAMPLE_COUNT := 121
const SUPPORT_BAND_FRACTION := 0.10
const MIN_FOOT_RANGE_M := 0.05

const SEMANTICS := [
    "Hips", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
    "RightUpperLeg", "RightLowerLeg", "RightFoot",
    "Spine", "Chest", "Neck", "Head",
    "LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
    "RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
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

func _range_m(points: Array[Vector3]) -> float:
    if points.is_empty():
        return 0.0
    var min_v := points[0]
    var max_v := points[0]
    for point in points:
        min_v.x = minf(min_v.x, point.x)
        min_v.y = minf(min_v.y, point.y)
        min_v.z = minf(min_v.z, point.z)
        max_v.x = maxf(max_v.x, point.x)
        max_v.y = maxf(max_v.y, point.y)
        max_v.z = maxf(max_v.z, point.z)
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
    var threshold := min_y + ((max_y - min_y) * SUPPORT_BAND_FRACTION)
    var dt := animation_length / float(SAMPLE_COUNT - 1)
    var low_indices: Array[int] = []
    var low_times: Array[float] = []
    var low_mask: Array[bool] = []
    low_mask.resize(usable_count)
    for i in range(usable_count):
        var is_low := points[i].y <= threshold
        low_mask[i] = is_low
        if is_low:
            low_indices.append(i)
            low_times.append(float(i) * dt)

    var segment_start_indices: Array[int] = []
    var speeds: Array[float] = []
    var path_m := 0.0
    for i in range(usable_count - 1):
        if low_mask[i] and low_mask[i + 1]:
            var a := Vector2(points[i].x, points[i].z)
            var b := Vector2(points[i + 1].x, points[i + 1].z)
            var distance := a.distance_to(b)
            path_m += distance
            speeds.append(distance / dt if dt > 0.0 else 0.0)
            segment_start_indices.append(i)

    var windows: Array[Dictionary] = []
    if not low_indices.is_empty():
        var start := low_indices[0]
        var previous := start
        for cursor in range(1, low_indices.size()):
            var current := low_indices[cursor]
            if current != previous + 1:
                windows.append({
                    "start_index": start,
                    "end_index": previous,
                    "sample_count": previous - start + 1,
                    "start_time_s": float(start) * dt,
                    "end_time_s": float(previous) * dt,
                    "wraps_cycle": false,
                })
                start = current
            previous = current
        windows.append({
            "start_index": start,
            "end_index": previous,
            "sample_count": previous - start + 1,
            "start_time_s": float(start) * dt,
            "end_time_s": float(previous) * dt,
            "wraps_cycle": false,
        })

    if windows.size() >= 2 and int(windows[0]["start_index"]) == 0 and int(windows[-1]["end_index"]) == usable_count - 1:
        var first := windows[0]
        var last := windows[-1]
        var merged := {
            "start_index": int(last["start_index"]),
            "end_index": int(first["end_index"]),
            "sample_count": int(last["sample_count"]) + int(first["sample_count"]),
            "start_time_s": float(last["start_time_s"]),
            "end_time_s": float(first["end_time_s"]),
            "wraps_cycle": true,
        }
        windows.remove_at(windows.size() - 1)
        windows.remove_at(0)
        windows.push_front(merged)

    return {
        "support_band_fraction": SUPPORT_BAND_FRACTION,
        "low_height_threshold_y": threshold,
        "low_height_sample_count": low_indices.size(),
        "low_height_sample_indices": low_indices,
        "low_height_sample_times_s": low_times,
        "low_height_segment_count": speeds.size(),
        "low_height_segment_start_indices": segment_start_indices,
        "low_height_windows": windows,
        "horizontal_path_m": path_m,
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
        push_error("CIV1_RIGHT_FOOT_REFERENCE_AB_FAIL: expected one Master_Rigged scene")
        quit(3)
        return

    var source_packed := load(_source_scene_paths[0]) as PackedScene
    var target_packed := load(TARGET_SCENE) as PackedScene
    if source_packed == null or target_packed == null:
        push_error("CIV1_RIGHT_FOOT_REFERENCE_AB_FAIL: source/target load failed")
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
        push_error("CIV1_RIGHT_FOOT_REFERENCE_AB_FAIL: Sprint missing")
        quit(5)
        return

    var source_skeletons: Array[Skeleton3D] = []
    var target_skeletons: Array[Skeleton3D] = []
    _collect_skeletons(source_instance, source_skeletons)
    _collect_skeletons(target_instance, target_skeletons)
    if source_skeletons.is_empty() or target_skeletons.size() != 1:
        push_error("CIV1_RIGHT_FOOT_REFERENCE_AB_FAIL: unexpected skeleton inventory")
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
        push_error("CIV1_RIGHT_FOOT_REFERENCE_AB_FAIL: required semantic mapping incomplete")
        quit(7)
        return

    var source_names := {}
    for semantic in SEMANTICS:
        source_names[semantic] = source_skeleton.get_bone_name(int(source_map[semantic]))
    for semantic in SEMANTICS:
        target_skeleton.set_bone_name(int(target_map[semantic]), StringName("GB_TMP_" + semantic))
    for semantic in SEMANTICS:
        target_skeleton.set_bone_name(int(target_map[semantic]), StringName(source_names[semantic]))

    var source_right_lower_idx := int(source_map["RightLowerLeg"])
    var source_right_idx := int(source_map["RightFoot"])
    var target_right_lower_idx := int(target_map["RightLowerLeg"])
    var target_right_idx := int(target_map["RightFoot"])
    var source_parent_rest := source_skeleton.get_bone_global_rest(source_right_lower_idx)
    var source_foot_rest := source_skeleton.get_bone_global_rest(source_right_idx)
    var source_reference_vector_global := source_foot_rest.origin - source_parent_rest.origin
    if source_reference_vector_global.length() <= 0.000001:
        push_error("CIV1_RIGHT_FOOT_REFERENCE_AB_FAIL: source RightFoot reference vector degenerate")
        quit(8)
        return
    var source_reference_direction_global := source_reference_vector_global.normalized()
    var target_parent_rest := target_skeleton.get_bone_global_rest(target_right_lower_idx)
    var target_right_foot_original_rest := target_skeleton.get_bone_rest(target_right_idx)
    var target_right_foot_original_local_rest_origin := target_right_foot_original_rest.origin
    if target_right_foot_original_local_rest_origin.length() <= 0.000001:
        push_error("CIV1_RIGHT_FOOT_REFERENCE_AB_FAIL: target RightFoot rest length degenerate")
        quit(9)
        return
    var normalized_local_direction := (target_parent_rest.basis.inverse() * source_reference_direction_global).normalized()
    var target_right_foot_normalized_local_rest_origin := normalized_local_direction * target_right_foot_original_local_rest_origin.length()
    var normalized_right_foot_rest := target_right_foot_original_rest
    normalized_right_foot_rest.origin = target_right_foot_normalized_local_rest_origin
    target_skeleton.set_bone_rest(target_right_idx, normalized_right_foot_rest)
    target_skeleton.force_update_all_bone_transforms()
    await process_frame

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

    if modifier.is_using_global_pose() or modifier.is_position_enabled() or not modifier.is_rotation_enabled() or modifier.is_scale_enabled():
        push_error("CIV1_RIGHT_FOOT_REFERENCE_AB_FAIL: modifier flags drift")
        quit(10)
        return

    var animation := player.get_animation(SOURCE_ANIMATION)
    if animation == null or animation.length <= 0.0:
        push_error("CIV1_RIGHT_FOOT_REFERENCE_AB_FAIL: invalid Sprint animation")
        quit(11)
        return

    var source_left_idx := int(source_map["LeftFoot"])
    var target_left_idx := int(target_map["LeftFoot"])
    var source_left_points: Array[Vector3] = []
    var source_right_points: Array[Vector3] = []
    var target_left_points: Array[Vector3] = []
    var target_right_points: Array[Vector3] = []

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
        target_left_points.append(target_skeleton.get_bone_global_pose(target_left_idx).origin)
        target_right_points.append(target_skeleton.get_bone_global_pose(target_right_idx).origin)

    var source_left_range := _range_m(source_left_points)
    var source_right_range := _range_m(source_right_points)
    var target_left_range := _range_m(target_left_points)
    var target_right_range := _range_m(target_right_points)
    var source_left_support := _support_metrics(source_left_points, animation.length)
    var source_right_support := _support_metrics(source_right_points, animation.length)
    var target_left_support := _support_metrics(target_left_points, animation.length)
    var target_right_support := _support_metrics(target_right_points, animation.length)
    var source_moves := source_left_range > MIN_FOOT_RANGE_M and source_right_range > MIN_FOOT_RANGE_M
    var target_moves := target_left_range > MIN_FOOT_RANGE_M and target_right_range > MIN_FOOT_RANGE_M
    var measurement_ready := source_moves and target_moves and int(target_left_support["low_height_segment_count"]) > 0 and int(target_right_support["low_height_segment_count"]) > 0
    var original_length := target_right_foot_original_local_rest_origin.length()
    var normalized_length := target_right_foot_normalized_local_rest_origin.length()
    var length_preserved := absf(original_length - normalized_length) <= 0.000001

    var payload := {
        "format": "grand-bruxelles-civ1-right-foot-reference-ab-v1",
        "godot_version": Engine.get_version_info(),
        "source_animation": SOURCE_ANIMATION,
        "sample_count": SAMPLE_COUNT,
        "support_band_fraction": SUPPORT_BAND_FRACTION,
        "mapped_required_bones": SEMANTICS.size(),
        "retarget_modifier": "RetargetModifier3D",
        "target_parent_is_modifier": target_skeleton.get_parent() == modifier,
        "use_global_pose": false,
        "position_enabled": false,
        "rotation_enabled": true,
        "scale_enabled": false,
        "minimum_foot_range_m": MIN_FOOT_RANGE_M,
        "reference_normalization_method": "source_global_reference_direction_preserve_target_foot_length",
        "reference_normalization_applied": true,
        "counterfactual_only": false,
        "source_reference_direction_global": _v3(source_reference_direction_global),
        "target_right_foot_original_local_rest_origin": _v3(target_right_foot_original_local_rest_origin),
        "target_right_foot_normalized_local_rest_origin": _v3(target_right_foot_normalized_local_rest_origin),
        "target_right_foot_original_length_m": original_length,
        "target_right_foot_normalized_length_m": normalized_length,
        "target_right_foot_length_preserved": length_preserved,
        "source_left_foot_range_m": source_left_range,
        "source_right_foot_range_m": source_right_range,
        "target_left_foot_range_m": target_left_range,
        "target_right_foot_range_m": target_right_range,
        "source_bilateral_motion_verified": source_moves,
        "target_bilateral_motion_verified": target_moves,
        "source_left_support_candidate": source_left_support,
        "source_right_support_candidate": source_right_support,
        "target_left_support_candidate": target_left_support,
        "target_right_support_candidate": target_right_support,
        "target_support_candidate_measurement_ready": measurement_ready,
        "diagnostic_only": true,
        "run_alias_selected": false,
        "world_ground_assumed": false,
        "grounding_verified": false,
        "foot_slide_verified": false,
        "runtime_authorized": false,
        "visual_approval_claimed": false,
    }

    if not _write_payload(payload):
        quit(12)
        return
    if not measurement_ready or not length_preserved:
        push_error("CIV1_RIGHT_FOOT_REFERENCE_AB_FAIL: measurement or length-preservation contract failed")
        quit(13)
        return
    print("CIV1_RIGHT_FOOT_REFERENCE_AB_OK")
    quit(0)
