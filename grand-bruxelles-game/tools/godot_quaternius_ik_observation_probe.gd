extends SceneTree

const SAMPLE_COUNT := 61
const TARGET_ANIMATIONS := ["UAL1_Standard/Walk", "UAL1_Standard/Jog_Fwd", "UAL1_Standard/Sprint"]
const LEG_CHAIN_TOKENS := ["leftupleg", "leftleg", "leftfoot", "lefttoe", "rightupleg", "rightleg", "rightfoot", "righttoe"]
const MOTION_POSITION_EPS_M := 0.00001
const MOTION_ROTATION_EPS_DEG := 0.1
const POSE_MOTION_EPS_M := 0.00001
const REFERENCE_SCENE_SUFFIX := "Models_with_rigging/Master_Rigged.tscn"
const LEFT_FOOT_BONE := "LeftFoot"
const RIGHT_FOOT_BONE := "RightFoot"

var scene_paths: Array[String] = []
var load_failures: Array[String] = []
var observations: Array[Dictionary] = []

func _init() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 1:
        quit(2)
        return
    _scan_dir("res://")
    scene_paths.sort()
    for scene_path in scene_paths:
        var resource := load(scene_path)
        if not (resource is PackedScene):
            load_failures.append(scene_path)
            continue
        var instance := (resource as PackedScene).instantiate()
        if instance == null:
            load_failures.append(scene_path)
            continue
        root.add_child(instance)
        _walk_scene(instance, scene_path, str(instance.name), instance)
        root.remove_child(instance)
        instance.free()
    observations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["observation_id"]) < str(b["observation_id"]))
    var refs: Array[String] = []
    for observation in observations:
        if str(observation["scene_path"]).ends_with(REFERENCE_SCENE_SUFFIX) and bool(observation["bilateral_chain_motion"]):
            refs.append(str(observation["observation_id"]))
    refs.sort()
    var payload := {
        "format": "grand-bruxelles-quaternius-ik-observation-context-v4",
        "godot_version": Engine.get_version_info(),
        "sample_count": SAMPLE_COUNT,
        "position_motion_epsilon_m": MOTION_POSITION_EPS_M,
        "rotation_motion_epsilon_deg": MOTION_ROTATION_EPS_DEG,
        "pose_motion_epsilon_m": POSE_MOTION_EPS_M,
        "scene_candidates": scene_paths,
        "load_failures": load_failures,
        "observations": observations,
        "reference_scene_suffix": REFERENCE_SCENE_SUFFIX,
        "reference_context_candidates": refs,
        "semantic_selection_allowed": false,
        "civ1_retarget_authorized": false,
        "grounding_verified": false,
        "foot_slide_verified": false,
        "visual_approval_claimed": false,
    }
    var output := FileAccess.open(args[0], FileAccess.WRITE)
    if output == null:
        quit(3)
        return
    output.store_string(JSON.stringify(payload, "  "))
    output.close()
    print("QUATERNIUS_IK_OBSERVATION_PROBE_OK observations=%d reference_candidates=%d load_failures=%d" % [observations.size(), refs.size(), load_failures.size()])
    quit(0)

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
        elif name.get_extension().to_lower() in ["tscn", "scn", "glb", "gltf"]:
            scene_paths.append(child)
    dir.list_dir_end()

func _walk_scene(node: Node, scene_path: String, relative_path: String, scene_root: Node) -> void:
    if node is AnimationPlayer:
        _inspect_player(node as AnimationPlayer, scene_path, relative_path, scene_root)
    for child in node.get_children():
        _walk_scene(child, scene_path, relative_path.path_join(str(child.name)), scene_root)

func _normalized(value: String) -> String:
    return value.to_lower().replace("_", "").replace("-", "").replace(" ", "")

func _chain_side(path: String) -> String:
    var value := _normalized(path)
    if value.contains("leftupleg") or value.contains("leftleg") or value.contains("leftfoot") or value.contains("lefttoe"):
        return "left"
    if value.contains("rightupleg") or value.contains("rightleg") or value.contains("rightfoot") or value.contains("righttoe"):
        return "right"
    return ""

func _is_leg_chain_path(path: String) -> bool:
    var value := _normalized(path)
    for token in LEG_CHAIN_TOKENS:
        if value.contains(token):
            return true
    return false

func _sample_position_motion(animation: Animation, index: int) -> Dictionary:
    var first: Variant = animation.position_track_interpolate(index, 0.0)
    if not (first is Vector3):
        return {"valid": false}
    var max_delta := 0.0
    for sample_index in range(SAMPLE_COUNT):
        var t := animation.length * float(sample_index) / float(SAMPLE_COUNT - 1)
        var value: Variant = animation.position_track_interpolate(index, t)
        if value is Vector3:
            max_delta = maxf(max_delta, (first as Vector3).distance_to(value as Vector3))
    return {"valid": true, "max_displacement_m": max_delta, "animated": max_delta > MOTION_POSITION_EPS_M}

func _sample_rotation_motion(animation: Animation, index: int) -> Dictionary:
    var first: Variant = animation.rotation_track_interpolate(index, 0.0)
    if not (first is Quaternion):
        return {"valid": false}
    var max_angle := 0.0
    for sample_index in range(SAMPLE_COUNT):
        var t := animation.length * float(sample_index) / float(SAMPLE_COUNT - 1)
        var value: Variant = animation.rotation_track_interpolate(index, t)
        if value is Quaternion:
            max_angle = maxf(max_angle, rad_to_deg((first as Quaternion).angle_to(value as Quaternion)))
    return {"valid": true, "max_angle_deg": max_angle, "animated": max_angle > MOTION_ROTATION_EPS_DEG}

func _collect_animation_trees(node: Node, result: Array[AnimationTree]) -> void:
    if node is AnimationTree:
        result.append(node as AnimationTree)
    for child in node.get_children():
        _collect_animation_trees(child, result)

func _linked_animation_tree_inventory(scene_root: Node, player: AnimationPlayer) -> Array[Dictionary]:
    var trees: Array[AnimationTree] = []
    _collect_animation_trees(scene_root, trees)
    var rows: Array[Dictionary] = []
    for tree in trees:
        var raw: Variant = tree.get("anim_player")
        var path := NodePath(str(raw)) if raw != null else NodePath("")
        var linked := false
        if not path.is_empty():
            linked = tree.get_node_or_null(path) == player
        rows.append({"tree_path": str(scene_root.get_path_to(tree)), "anim_player_path": str(path), "active": tree.active, "linked_to_observed_player": linked})
    return rows

func _measure_player_pose(player: AnimationPlayer, skeleton: Skeleton3D, left_idx: int, right_idx: int, animation_name: StringName, animation: Animation) -> Dictionary:
    var samples: Array[Dictionary] = []
    var first_left := Vector3.ZERO
    var first_right := Vector3.ZERO
    var left_range := 0.0
    var right_range := 0.0
    player.play(animation_name)
    player.advance(0.0)
    for sample_index in range(SAMPLE_COUNT):
        var t := animation.length * float(sample_index) / float(SAMPLE_COUNT - 1)
        player.seek(t, true)
        player.advance(0.0)
        skeleton.force_update_all_bone_transforms()
        var left := skeleton.get_bone_global_pose(left_idx).origin
        var right := skeleton.get_bone_global_pose(right_idx).origin
        if sample_index == 0:
            first_left = left
            first_right = right
        left_range = maxf(left_range, first_left.distance_to(left))
        right_range = maxf(right_range, first_right.distance_to(right))
        samples.append({"sample_index": sample_index, "time_seconds": t, "left_foot_global_pose": [left.x,left.y,left.z], "right_foot_global_pose": [right.x,right.y,right.z]})
    player.stop()
    return {"left_foot_pose_range_m": left_range, "right_foot_pose_range_m": right_range, "bilateral_foot_pose_motion": left_range > POSE_MOTION_EPS_M and right_range > POSE_MOTION_EPS_M, "pose_samples": samples}

func _bone_name_from_track_path(track_path: NodePath) -> String:
    var bone_name := str(track_path.get_concatenated_subnames())
    if bone_name.contains(":"):
        bone_name = bone_name.split(":", false, 1)[0]
    return bone_name

func _apply_animation_tracks_to_skeleton(animation: Animation, skeleton: Skeleton3D, t: float) -> int:
    var applied := 0
    for index in range(animation.get_track_count()):
        var track_path: NodePath = animation.track_get_path(index)
        var bone_name := _bone_name_from_track_path(track_path)
        var bone_idx := skeleton.find_bone(bone_name)
        if bone_idx < 0:
            continue
        var track_type := animation.track_get_type(index)
        if track_type == Animation.TYPE_POSITION_3D:
            var value: Variant = animation.position_track_interpolate(index, t)
            if value is Vector3:
                skeleton.set_bone_pose_position(bone_idx, value as Vector3)
                applied += 1
        elif track_type == Animation.TYPE_ROTATION_3D:
            var value: Variant = animation.rotation_track_interpolate(index, t)
            if value is Quaternion:
                skeleton.set_bone_pose_rotation(bone_idx, value as Quaternion)
                applied += 1
        elif track_type == Animation.TYPE_SCALE_3D:
            var value: Variant = animation.scale_track_interpolate(index, t)
            if value is Vector3:
                skeleton.set_bone_pose_scale(bone_idx, value as Vector3)
                applied += 1
    return applied

func _measure_direct_track_pose(animation: Animation, skeleton: Skeleton3D, left_idx: int, right_idx: int) -> Dictionary:
    var bone_count := skeleton.get_bone_count()
    var saved_positions: Array[Vector3] = []
    var saved_rotations: Array[Quaternion] = []
    var saved_scales: Array[Vector3] = []
    for bone_idx in range(bone_count):
        saved_positions.append(skeleton.get_bone_pose_position(bone_idx))
        saved_rotations.append(skeleton.get_bone_pose_rotation(bone_idx))
        saved_scales.append(skeleton.get_bone_pose_scale(bone_idx))
    var samples: Array[Dictionary] = []
    var first_left := Vector3.ZERO
    var first_right := Vector3.ZERO
    var left_range := 0.0
    var right_range := 0.0
    var minimum_applied := 2147483647
    for sample_index in range(SAMPLE_COUNT):
        for bone_idx in range(bone_count):
            skeleton.reset_bone_pose(bone_idx)
        var t := animation.length * float(sample_index) / float(SAMPLE_COUNT - 1)
        var applied := _apply_animation_tracks_to_skeleton(animation, skeleton, t)
        minimum_applied = mini(minimum_applied, applied)
        skeleton.force_update_all_bone_transforms()
        var left := skeleton.get_bone_global_pose(left_idx).origin
        var right := skeleton.get_bone_global_pose(right_idx).origin
        if sample_index == 0:
            first_left = left
            first_right = right
        left_range = maxf(left_range, first_left.distance_to(left))
        right_range = maxf(right_range, first_right.distance_to(right))
        samples.append({"sample_index": sample_index, "time_seconds": t, "applied_track_count": applied, "left_foot_global_pose": [left.x,left.y,left.z], "right_foot_global_pose": [right.x,right.y,right.z]})
    for bone_idx in range(bone_count):
        skeleton.set_bone_pose_position(bone_idx, saved_positions[bone_idx])
        skeleton.set_bone_pose_rotation(bone_idx, saved_rotations[bone_idx])
        skeleton.set_bone_pose_scale(bone_idx, saved_scales[bone_idx])
    skeleton.force_update_all_bone_transforms()
    var restored := true
    for bone_idx in range(bone_count):
        restored = restored and skeleton.get_bone_pose_position(bone_idx).distance_to(saved_positions[bone_idx]) <= 0.000001
        restored = restored and rad_to_deg(skeleton.get_bone_pose_rotation(bone_idx).angle_to(saved_rotations[bone_idx])) <= 0.0001
        restored = restored and skeleton.get_bone_pose_scale(bone_idx).distance_to(saved_scales[bone_idx]) <= 0.000001
    if minimum_applied == 2147483647:
        minimum_applied = 0
    return {"valid": true, "method": "direct_imported_transform_tracks_to_skeleton", "minimum_applied_track_count": minimum_applied, "left_foot_pose_range_m": left_range, "right_foot_pose_range_m": right_range, "bilateral_foot_pose_motion": left_range > POSE_MOTION_EPS_M and right_range > POSE_MOTION_EPS_M, "pose_samples": samples, "direct_pose_state_restored_after_measurement": restored}

func _sample_applied_foot_poses(player: AnimationPlayer, animation_name: StringName, animation: Animation, scene_root: Node) -> Dictionary:
    var original_root: NodePath = player.root_node
    var skeleton_node := player.get_node_or_null(original_root)
    if not (skeleton_node is Skeleton3D):
        return {"valid": false, "reason": "animation_root_is_not_skeleton", "original_root_node": str(original_root)}
    var skeleton := skeleton_node as Skeleton3D
    var left_idx := skeleton.find_bone(LEFT_FOOT_BONE)
    var right_idx := skeleton.find_bone(RIGHT_FOOT_BONE)
    if left_idx < 0 or right_idx < 0:
        return {"valid": false, "reason": "foot_bones_missing"}
    var trees := _linked_animation_tree_inventory(scene_root, player)
    var original_measurement := _measure_player_pose(player, skeleton, left_idx, right_idx, animation_name, animation)
    var fallback_measurement: Dictionary = {}
    if not bool(original_measurement["bilateral_foot_pose_motion"]):
        player.root_node = NodePath("..")
        fallback_measurement = _measure_player_pose(player, skeleton, left_idx, right_idx, animation_name, animation)
        player.root_node = original_root
    var direct_track_pose_measurement := _measure_direct_track_pose(animation, skeleton, left_idx, right_idx)
    player.root_node = original_root
    var player_bilateral := bool(original_measurement["bilateral_foot_pose_motion"]) or bool(fallback_measurement.get("bilateral_foot_pose_motion", false))
    var selected: Dictionary = original_measurement if player_bilateral else direct_track_pose_measurement
    return {
        "valid": true,
        "skeleton_path": str(player.get_path_to(skeleton)),
        "left_foot_bone": LEFT_FOOT_BONE,
        "right_foot_bone": RIGHT_FOOT_BONE,
        "left_foot_pose_range_m": selected["left_foot_pose_range_m"],
        "right_foot_pose_range_m": selected["right_foot_pose_range_m"],
        "bilateral_foot_pose_motion": selected["bilateral_foot_pose_motion"],
        "pose_samples": selected["pose_samples"],
        "selected_pose_measurement_method": "animation_player" if player_bilateral else "direct_imported_transform_tracks_to_skeleton",
        "animation_player_bilateral_foot_pose_motion": player_bilateral,
        "original_root_node": str(original_root),
        "selected_diagnostic_root_node": str(original_root),
        "root_override_used": not fallback_measurement.is_empty(),
        "linked_animation_trees": trees,
        "linked_animation_tree_count": trees.filter(func(row: Dictionary) -> bool: return bool(row["linked_to_observed_player"])).size(),
        "tree_override_used": false,
        "tree_state_restored_after_measurement": true,
        "original_root_pose_range_m": [original_measurement["left_foot_pose_range_m"], original_measurement["right_foot_pose_range_m"]],
        "fallback_root_pose_range_m": [] if fallback_measurement.is_empty() else [fallback_measurement["left_foot_pose_range_m"], fallback_measurement["right_foot_pose_range_m"]],
        "direct_track_pose_measurement": direct_track_pose_measurement,
        "direct_pose_state_restored_after_measurement": direct_track_pose_measurement["direct_pose_state_restored_after_measurement"],
        "root_restored_after_measurement": player.root_node == original_root,
    }

func _inspect_player(player: AnimationPlayer, scene_path: String, relative_player_path: String, scene_root: Node) -> void:
    for animation_name in TARGET_ANIMATIONS:
        if not player.has_animation(animation_name):
            continue
        var animation := player.get_animation(animation_name)
        if animation == null:
            continue
        var tracks: Array[Dictionary] = []
        var left_animated := 0
        var right_animated := 0
        for index in range(animation.get_track_count()):
            var path := str(animation.track_get_path(index))
            if not _is_leg_chain_path(path):
                continue
            var track_type := animation.track_get_type(index)
            var motion: Dictionary
            var method := ""
            if track_type == Animation.TYPE_POSITION_3D:
                motion = _sample_position_motion(animation, index)
                method = "position_track_interpolate"
            elif track_type == Animation.TYPE_ROTATION_3D:
                motion = _sample_rotation_motion(animation, index)
                method = "rotation_track_interpolate"
            else:
                continue
            if not bool(motion.get("valid", false)):
                continue
            var side := _chain_side(path)
            if bool(motion["animated"]) and side == "left": left_animated += 1
            if bool(motion["animated"]) and side == "right": right_animated += 1
            var row := {"track_index": index, "path": path, "side": side, "track_type": int(track_type), "method": method, "animated": bool(motion["animated"])}
            for key in motion.keys():
                if key not in ["valid", "animated"]: row[key] = motion[key]
            tracks.append(row)
        var pose: Dictionary = {"valid": false, "reason": "non_reference_scene"}
        if scene_path.ends_with(REFERENCE_SCENE_SUFFIX):
            pose = _sample_applied_foot_poses(player, StringName(animation_name), animation, scene_root)
        observations.append({
            "observation_id": "%s|%s|%s" % [scene_path, relative_player_path, animation_name],
            "scene_path": scene_path,
            "animation_player_path": relative_player_path,
            "animation_root_path": str(player.root_node),
            "animation": animation_name,
            "length_seconds": animation.length,
            "track_count": animation.get_track_count(),
            "leg_chain_track_count": tracks.size(),
            "animated_left_chain_track_count": left_animated,
            "animated_right_chain_track_count": right_animated,
            "bilateral_chain_motion": left_animated > 0 and right_animated > 0,
            "leg_chain_tracks": tracks,
            "pose_measurement": pose,
            "pose_contact_ground_truth": false,
            "semantic_selection_allowed": false,
        })
