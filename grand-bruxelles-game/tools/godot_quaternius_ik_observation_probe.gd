extends SceneTree

const SAMPLE_COUNT := 61
const TARGET_ANIMATIONS := [
    "UAL1_Standard/Walk",
    "UAL1_Standard/Jog_Fwd",
    "UAL1_Standard/Sprint",
]
const LEG_CHAIN_TOKENS := [
    "leftupleg", "leftleg", "leftfoot", "lefttoe",
    "rightupleg", "rightleg", "rightfoot", "righttoe",
]
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
        push_error("usage: godot --headless --script res://probe.gd -- <output.json>")
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
        _walk_scene(instance, scene_path, str(instance.name))
        root.remove_child(instance)
        instance.free()
    observations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["observation_id"]) < str(b["observation_id"]))
    var reference_candidates: Array[String] = []
    for observation in observations:
        if str(observation["scene_path"]).ends_with(REFERENCE_SCENE_SUFFIX) and bool(observation["bilateral_chain_motion"]):
            reference_candidates.append(str(observation["observation_id"]))
    reference_candidates.sort()
    var payload := {
        "format": "grand-bruxelles-quaternius-ik-observation-context-v2",
        "godot_version": Engine.get_version_info(),
        "sample_count": SAMPLE_COUNT,
        "position_motion_epsilon_m": MOTION_POSITION_EPS_M,
        "rotation_motion_epsilon_deg": MOTION_ROTATION_EPS_DEG,
        "pose_motion_epsilon_m": POSE_MOTION_EPS_M,
        "scene_candidates": scene_paths,
        "load_failures": load_failures,
        "observations": observations,
        "reference_scene_suffix": REFERENCE_SCENE_SUFFIX,
        "reference_context_candidates": reference_candidates,
        "semantic_selection_allowed": false,
        "civ1_retarget_authorized": false,
        "grounding_verified": false,
        "foot_slide_verified": false,
        "visual_approval_claimed": false,
    }
    var output := FileAccess.open(args[0], FileAccess.WRITE)
    if output == null:
        push_error("cannot open output path: %s" % args[0])
        quit(3)
        return
    output.store_string(JSON.stringify(payload, "  "))
    output.close()
    print("QUATERNIUS_IK_OBSERVATION_PROBE_OK observations=%d reference_candidates=%d load_failures=%d" % [observations.size(), reference_candidates.size(), load_failures.size()])
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
            continue
        if name.get_extension().to_lower() in ["tscn", "scn", "glb", "gltf"]:
            scene_paths.append(child)
    dir.list_dir_end()

func _walk_scene(node: Node, scene_path: String, relative_node_path: String) -> void:
    if node is AnimationPlayer:
        _inspect_player(node as AnimationPlayer, scene_path, relative_node_path)
    for child in node.get_children():
        _walk_scene(child, scene_path, relative_node_path.path_join(str(child.name)))

func _normalized_path(value: String) -> String:
    return value.to_lower().replace("_", "").replace("-", "").replace(" ", "")

func _chain_side(path: String) -> String:
    var normalized := _normalized_path(path)
    if normalized.contains("leftupleg") or normalized.contains("leftleg") or normalized.contains("leftfoot") or normalized.contains("lefttoe"):
        return "left"
    if normalized.contains("rightupleg") or normalized.contains("rightleg") or normalized.contains("rightfoot") or normalized.contains("righttoe"):
        return "right"
    return ""

func _is_leg_chain_path(path: String) -> bool:
    var normalized := _normalized_path(path)
    for token in LEG_CHAIN_TOKENS:
        if normalized.contains(token):
            return true
    return false

func _sample_position_motion(animation: Animation, track_index: int) -> Dictionary:
    var first_value: Variant = animation.position_track_interpolate(track_index, 0.0)
    if not (first_value is Vector3):
        return {"valid": false}
    var first := first_value as Vector3
    var max_displacement_m := 0.0
    for sample_index in range(SAMPLE_COUNT):
        var t := animation.length * float(sample_index) / float(SAMPLE_COUNT - 1)
        var value: Variant = animation.position_track_interpolate(track_index, t)
        if value is Vector3:
            max_displacement_m = maxf(max_displacement_m, first.distance_to(value as Vector3))
    return {"valid": true, "max_displacement_m": max_displacement_m, "animated": max_displacement_m > MOTION_POSITION_EPS_M}

func _sample_rotation_motion(animation: Animation, track_index: int) -> Dictionary:
    var first_value: Variant = animation.rotation_track_interpolate(track_index, 0.0)
    if not (first_value is Quaternion):
        return {"valid": false}
    var first := first_value as Quaternion
    var max_angle_deg := 0.0
    for sample_index in range(SAMPLE_COUNT):
        var t := animation.length * float(sample_index) / float(SAMPLE_COUNT - 1)
        var value: Variant = animation.rotation_track_interpolate(track_index, t)
        if value is Quaternion:
            max_angle_deg = maxf(max_angle_deg, rad_to_deg(first.angle_to(value as Quaternion)))
    return {"valid": true, "max_angle_deg": max_angle_deg, "animated": max_angle_deg > MOTION_ROTATION_EPS_DEG}

func _measure_pose_with_current_root(player: AnimationPlayer, skeleton: Skeleton3D, left_idx: int, right_idx: int, animation_name: StringName, animation: Animation) -> Dictionary:
    var samples: Array[Dictionary] = []
    var left_first := Vector3.ZERO
    var right_first := Vector3.ZERO
    var left_range := 0.0
    var right_range := 0.0
    var have_first := false
    player.play(animation_name)
    player.advance(0.0)
    for sample_index in range(SAMPLE_COUNT):
        var t := animation.length * float(sample_index) / float(SAMPLE_COUNT - 1)
        player.seek(t, true)
        player.advance(0.0)
        skeleton.force_update_bone_child_transform(left_idx)
        skeleton.force_update_bone_child_transform(right_idx)
        var left_pos := skeleton.get_bone_global_pose(left_idx).origin
        var right_pos := skeleton.get_bone_global_pose(right_idx).origin
        if not have_first:
            left_first = left_pos
            right_first = right_pos
            have_first = true
        left_range = maxf(left_range, left_first.distance_to(left_pos))
        right_range = maxf(right_range, right_first.distance_to(right_pos))
        samples.append({
            "sample_index": sample_index,
            "time_seconds": t,
            "left_foot_global_pose": [left_pos.x, left_pos.y, left_pos.z],
            "right_foot_global_pose": [right_pos.x, right_pos.y, right_pos.z],
        })
    player.stop()
    return {
        "left_foot_pose_range_m": left_range,
        "right_foot_pose_range_m": right_range,
        "bilateral_foot_pose_motion": left_range > POSE_MOTION_EPS_M and right_range > POSE_MOTION_EPS_M,
        "pose_samples": samples,
    }

func _sample_applied_foot_poses(player: AnimationPlayer, animation_name: StringName, animation: Animation) -> Dictionary:
    var original_root: NodePath = player.root_node
    var skeleton_node := player.get_node_or_null(original_root)
    if not (skeleton_node is Skeleton3D):
        return {"valid": false, "reason": "animation_root_is_not_skeleton", "original_root_node": str(original_root)}
    var skeleton := skeleton_node as Skeleton3D
    var left_idx := skeleton.find_bone(LEFT_FOOT_BONE)
    var right_idx := skeleton.find_bone(RIGHT_FOOT_BONE)
    if left_idx < 0 or right_idx < 0:
        return {"valid": false, "reason": "foot_bones_missing", "left_index": left_idx, "right_index": right_idx, "original_root_node": str(original_root)}

    var original_measurement := _measure_pose_with_current_root(player, skeleton, left_idx, right_idx, animation_name, animation)
    var selected_measurement: Dictionary = original_measurement
    var selected_root := original_root
    var root_override_used := false
    var fallback_measurement: Dictionary = {}

    if not bool(original_measurement.get("bilateral_foot_pose_motion", false)):
        # The imported library tracks target `%GeneralSkeleton:<bone>`. Test the scene parent
        # as AnimationMixer root without mutating the source asset permanently.
        player.root_node = NodePath("..")
        fallback_measurement = _measure_pose_with_current_root(player, skeleton, left_idx, right_idx, animation_name, animation)
        if bool(fallback_measurement.get("bilateral_foot_pose_motion", false)):
            selected_measurement = fallback_measurement
            selected_root = NodePath("..")
            root_override_used = true
        player.root_node = original_root

    return {
        "valid": true,
        "skeleton_path": str(player.get_path_to(skeleton)),
        "left_foot_bone": LEFT_FOOT_BONE,
        "right_foot_bone": RIGHT_FOOT_BONE,
        "left_foot_bone_index": left_idx,
        "right_foot_bone_index": right_idx,
        "left_foot_pose_range_m": selected_measurement["left_foot_pose_range_m"],
        "right_foot_pose_range_m": selected_measurement["right_foot_pose_range_m"],
        "bilateral_foot_pose_motion": selected_measurement["bilateral_foot_pose_motion"],
        "pose_samples": selected_measurement["pose_samples"],
        "original_root_node": str(original_root),
        "selected_diagnostic_root_node": str(selected_root),
        "root_override_used": root_override_used,
        "original_root_pose_range_m": [original_measurement["left_foot_pose_range_m"], original_measurement["right_foot_pose_range_m"]],
        "fallback_root_pose_range_m": [] if fallback_measurement.is_empty() else [fallback_measurement["left_foot_pose_range_m"], fallback_measurement["right_foot_pose_range_m"]],
        "root_restored_after_measurement": player.root_node == original_root,
    }

func _inspect_player(player: AnimationPlayer, scene_path: String, relative_player_path: String) -> void:
    var player_path := relative_player_path
    var root_path := str(player.root_node)
    for animation_name in TARGET_ANIMATIONS:
        if not player.has_animation(animation_name):
            continue
        var animation := player.get_animation(animation_name)
        if animation == null:
            continue
        var tracks: Array[Dictionary] = []
        var left_animated := 0
        var right_animated := 0
        for track_index in range(animation.get_track_count()):
            var track_path := str(animation.track_get_path(track_index))
            if not _is_leg_chain_path(track_path):
                continue
            var track_type := animation.track_get_type(track_index)
            var motion: Dictionary = {"valid": false, "animated": false}
            var method := "unsupported"
            if track_type == Animation.TYPE_POSITION_3D:
                motion = _sample_position_motion(animation, track_index)
                method = "position_track_interpolate"
            elif track_type == Animation.TYPE_ROTATION_3D:
                motion = _sample_rotation_motion(animation, track_index)
                method = "rotation_track_interpolate"
            else:
                continue
            if not bool(motion.get("valid", false)):
                continue
            var side := _chain_side(track_path)
            var animated := bool(motion.get("animated", false))
            if animated and side == "left":
                left_animated += 1
            elif animated and side == "right":
                right_animated += 1
            var row := {
                "track_index": track_index,
                "path": track_path,
                "side": side,
                "track_type": int(track_type),
                "method": method,
                "animated": animated,
            }
            for key in motion.keys():
                if key not in ["valid", "animated"]:
                    row[key] = motion[key]
            tracks.append(row)
        tracks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["path"]) < str(b["path"]))
        var pose_measurement: Dictionary = {"valid": false, "reason": "non_reference_scene"}
        if scene_path.ends_with(REFERENCE_SCENE_SUFFIX):
            pose_measurement = _sample_applied_foot_poses(player, StringName(animation_name), animation)
        var observation_id := "%s|%s|%s" % [scene_path, player_path, animation_name]
        observations.append({
            "observation_id": observation_id,
            "scene_path": scene_path,
            "animation_player_path": player_path,
            "animation_root_path": root_path,
            "animation": animation_name,
            "length_seconds": animation.length,
            "track_count": animation.get_track_count(),
            "leg_chain_track_count": tracks.size(),
            "animated_left_chain_track_count": left_animated,
            "animated_right_chain_track_count": right_animated,
            "bilateral_chain_motion": left_animated > 0 and right_animated > 0,
            "leg_chain_tracks": tracks,
            "pose_measurement": pose_measurement,
            "pose_contact_ground_truth": false,
            "semantic_selection_allowed": false,
        })
