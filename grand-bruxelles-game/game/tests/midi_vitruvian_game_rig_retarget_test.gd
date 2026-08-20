extends SceneTree

const RESOURCE_PATH := "res://assets/characters/_review/vitruvian_game_rig_retarget/body.glb"
const BONE_MAP_PATH := "res://data/qa/midi_vitruvian_game_rig_humanoid_bone_map.json"

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var output := "/tmp/vitruvian-game-rig-retarget.metrics.json"
    var args := OS.get_cmdline_user_args()
    if not args.is_empty():
        output = str(args[0])

    if not ResourceLoader.exists(RESOURCE_PATH):
        _fail("review body missing: %s" % RESOURCE_PATH)
        return
    var packed := ResourceLoader.load(RESOURCE_PATH) as PackedScene
    if packed == null:
        _fail("review body did not import as PackedScene")
        return
    var body := packed.instantiate() as Node3D
    if body == null:
        _fail("review body could not instantiate")
        return
    get_root().add_child(body)

    var skeletons: Array[Skeleton3D] = []
    var players: Array[AnimationPlayer] = []
    var meshes: Array[MeshInstance3D] = []
    _collect(body, skeletons, players, meshes)
    if skeletons.size() != 1:
        _fail("expected exactly one Skeleton3D, got %d" % skeletons.size())
        return
    if meshes.is_empty():
        _fail("review body has no MeshInstance3D")
        return
    var skeleton := skeletons[0]
    if skeleton.get_bone_count() < 35:
        _fail("review body skeleton too small: %d" % skeleton.get_bone_count())
        return

    var animation_clip_count := _count_non_reset_clips(players)
    if animation_clip_count != 0:
        _fail("retarget source body must be static before clip injection, got %d clips" % animation_clip_count)
        return

    var config := _read_json(BONE_MAP_PATH)
    if config.is_empty():
        _fail("bone map config missing or invalid")
        return
    if bool(config.get("production_authorized", true)):
        _fail("review BoneMap cannot be production-authorized")
        return
    var mapping_variant: Variant = config.get("required_core_mapping", {})
    var expectations_variant: Variant = config.get("required_profile_parent_expectations", {})
    if not mapping_variant is Dictionary or not expectations_variant is Dictionary:
        _fail("bone map dictionaries missing")
        return
    var mapping := mapping_variant as Dictionary
    var expectations := expectations_variant as Dictionary
    if mapping.size() != 22:
        _fail("expected 22 locomotion core mappings, got %d" % mapping.size())
        return
    if str(mapping.get("Hips", "")) != "Pelvis":
        _fail("Hips must map to Pelvis")
        return

    var profile := SkeletonProfileHumanoid.new()
    var bone_map := BoneMap.new()
    bone_map.profile = profile
    var source_to_profile: Dictionary = {}
    var missing_profile_bones: Array[String] = []
    var missing_source_bones: Array[String] = []
    var roundtrip_failures: Array[String] = []
    var mapped_core_count := 0

    for profile_name_variant: Variant in mapping.keys():
        var profile_name := str(profile_name_variant)
        var source_name := str(mapping[profile_name_variant])
        if profile.find_bone(StringName(profile_name)) < 0:
            missing_profile_bones.append(profile_name)
            continue
        if skeleton.find_bone(source_name) < 0:
            missing_source_bones.append(source_name)
            continue
        bone_map.set_skeleton_bone_name(StringName(profile_name), StringName(source_name))
        if str(bone_map.get_skeleton_bone_name(StringName(profile_name))) != source_name:
            roundtrip_failures.append("%s->%s" % [profile_name, source_name])
            continue
        source_to_profile[source_name] = profile_name
        mapped_core_count += 1

    var parent_failures: Array[String] = []
    for child_profile_variant: Variant in expectations.keys():
        var child_profile := str(child_profile_variant)
        var expected_parent_profile := str(expectations[child_profile_variant])
        if not mapping.has(child_profile) or not mapping.has(expected_parent_profile):
            parent_failures.append("%s missing configured role %s" % [child_profile, expected_parent_profile])
            continue
        var child_source := str(mapping[child_profile])
        var child_index := skeleton.find_bone(child_source)
        if child_index < 0:
            continue
        var parent_index := skeleton.get_bone_parent(child_index)
        var nearest_mapped_parent_profile := ""
        while parent_index >= 0:
            var parent_source := skeleton.get_bone_name(parent_index)
            if source_to_profile.has(parent_source):
                nearest_mapped_parent_profile = str(source_to_profile[parent_source])
                break
            parent_index = skeleton.get_bone_parent(parent_index)
        if nearest_mapped_parent_profile != expected_parent_profile:
            parent_failures.append("%s nearest=%s expected=%s" % [child_profile, nearest_mapped_parent_profile, expected_parent_profile])

    if not missing_profile_bones.is_empty() or not missing_source_bones.is_empty() or not roundtrip_failures.is_empty() or not parent_failures.is_empty() or mapped_core_count != mapping.size():
        _fail("BoneMap readiness failed profile=%s source=%s roundtrip=%s parents=%s mapped=%d/%d" % [str(missing_profile_bones), str(missing_source_bones), str(roundtrip_failures), str(parent_failures), mapped_core_count, mapping.size()])
        return

    var rest := _rest_pose_metrics(skeleton)
    if not bool(rest.get("ready", false)):
        _fail("rest-pose limb sanity failed: %s" % str(rest))
        return

    var forbidden_bones: Array[String] = []
    var bone_names: Array[String] = []
    for bone_index in range(skeleton.get_bone_count()):
        var bone_name := skeleton.get_bone_name(bone_index)
        bone_names.append(bone_name)
        var lower := bone_name.to_lower()
        if "mixamo" in lower or "adobe" in lower:
            forbidden_bones.append(bone_name)
    if not forbidden_bones.is_empty():
        _fail("forbidden source bone names: %s" % str(forbidden_bones))
        return

    var metrics := {
        "schema": "grand-bruxelles-vitruvian-game-rig-retarget-readiness-v1",
        "production_authorized": false,
        "resource": RESOURCE_PATH,
        "source_rig": "game-rig",
        "target_profile": "SkeletonProfileHumanoid",
        "mapped_core_count": mapped_core_count,
        "required_core_count": mapping.size(),
        "mapping": mapping.duplicate(true),
        "parent_expectations": expectations.duplicate(true),
        "parent_failures": parent_failures,
        "missing_profile_bones": missing_profile_bones,
        "missing_source_bones": missing_source_bones,
        "roundtrip_failures": roundtrip_failures,
        "root_profile_intentionally_unmapped": true,
        "hips_source_bone": str(mapping.get("Hips", "")),
        "root_motion_policy": str(config.get("root_motion_policy", "")),
        "animation_clip_count": animation_clip_count,
        "bone_count": skeleton.get_bone_count(),
        "bone_names": bone_names,
        "forbidden_bones": forbidden_bones,
        "rest_pose": rest,
        "next_gate": str(config.get("next_gate", ""))
    }
    var file := FileAccess.open(output, FileAccess.WRITE)
    if file == null:
        _fail("could not write metrics: %s" % output)
        return
    file.store_string(JSON.stringify(metrics, "  ") + "\n")
    file.close()
    print("GB_VITRUVIAN_GAME_RIG_RETARGET_READY mapped=%d bones=%d animations=0 hips=Pelvis parents=GREEN rest=GREEN production_authorized=false" % [mapped_core_count, skeleton.get_bone_count()])
    quit(0)

func _rest_pose_metrics(skeleton: Skeleton3D) -> Dictionary:
    var segment_pairs := {
        "left_upper_arm": ["upperarm_l", "lowerarm_l"],
        "right_upper_arm": ["upperarm_r", "lowerarm_r"],
        "left_lower_arm": ["lowerarm_l", "hand_l"],
        "right_lower_arm": ["lowerarm_r", "hand_r"],
        "left_upper_leg": ["thigh_l", "calf_l"],
        "right_upper_leg": ["thigh_r", "calf_r"],
        "left_lower_leg": ["calf_l", "foot_l"],
        "right_lower_leg": ["calf_r", "foot_r"]
    }
    var lengths := {}
    for key in segment_pairs:
        var pair: Array = segment_pairs[key]
        var a := skeleton.find_bone(str(pair[0]))
        var b := skeleton.find_bone(str(pair[1]))
        if a < 0 or b < 0:
            return {"ready": false, "reason": "missing_segment_bone", "segment": key}
        var length := skeleton.get_bone_global_rest(a).origin.distance_to(skeleton.get_bone_global_rest(b).origin)
        lengths[key] = length
        if length <= 0.03:
            return {"ready": false, "reason": "collapsed_segment", "segment": key, "length": length}

    var symmetry := {
        "upper_arm_ratio": _symmetry_ratio(float(lengths["left_upper_arm"]), float(lengths["right_upper_arm"])),
        "lower_arm_ratio": _symmetry_ratio(float(lengths["left_lower_arm"]), float(lengths["right_lower_arm"])),
        "upper_leg_ratio": _symmetry_ratio(float(lengths["left_upper_leg"]), float(lengths["right_upper_leg"])),
        "lower_leg_ratio": _symmetry_ratio(float(lengths["left_lower_leg"]), float(lengths["right_lower_leg"]))
    }
    for key in symmetry:
        var ratio := float(symmetry[key])
        if ratio < 0.85 or ratio > 1.15:
            return {"ready": false, "reason": "asymmetric_rest_segments", "metric": key, "ratio": ratio, "lengths": lengths}

    var hips := _rest_origin(skeleton, "Pelvis")
    var left_foot := _rest_origin(skeleton, "foot_l")
    var right_foot := _rest_origin(skeleton, "foot_r")
    if left_foot.y >= hips.y or right_foot.y >= hips.y:
        return {"ready": false, "reason": "feet_not_below_hips", "hips_y": hips.y, "left_foot_y": left_foot.y, "right_foot_y": right_foot.y}

    return {
        "ready": true,
        "segment_lengths": lengths,
        "symmetry": symmetry,
        "hips_y": hips.y,
        "left_foot_y": left_foot.y,
        "right_foot_y": right_foot.y
    }

func _symmetry_ratio(left: float, right: float) -> float:
    if left <= 0.0 or right <= 0.0:
        return 0.0
    return left / right

func _rest_origin(skeleton: Skeleton3D, bone_name: String) -> Vector3:
    var index := skeleton.find_bone(bone_name)
    if index < 0:
        return Vector3.ZERO
    return skeleton.get_bone_global_rest(index).origin

func _count_non_reset_clips(players: Array[AnimationPlayer]) -> int:
    var count := 0
    for player in players:
        for library_name in player.get_animation_library_list():
            var library := player.get_animation_library(library_name)
            if library == null:
                continue
            for animation_name in library.get_animation_list():
                if str(animation_name).to_upper() != "RESET":
                    count += 1
    return count

func _collect(node: Node, skeletons: Array[Skeleton3D], players: Array[AnimationPlayer], meshes: Array[MeshInstance3D]) -> void:
    if node is Skeleton3D:
        skeletons.append(node as Skeleton3D)
    if node is AnimationPlayer:
        players.append(node as AnimationPlayer)
    if node is MeshInstance3D:
        meshes.append(node as MeshInstance3D)
    for child in node.get_children():
        _collect(child, skeletons, players, meshes)

func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if parsed is Dictionary:
        return parsed as Dictionary
    return {}

func _fail(message: String) -> void:
    push_error("GB_VITRUVIAN_GAME_RIG_RETARGET_FAIL: %s" % message)
    quit(2)
