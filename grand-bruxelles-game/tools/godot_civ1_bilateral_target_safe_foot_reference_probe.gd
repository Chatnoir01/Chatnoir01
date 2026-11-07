extends SceneTree

const SOURCE_ANIMATION := "UAL1_Standard/Sprint"
const SOURCE_SCENE_SUFFIX := "Models_with_rigging/Master_Rigged.tscn"
const TARGET_SCENE := "res://civ1_body.glb"
const SAMPLE_COUNT := 121
const SEMANTICS := ["Hips", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"]
const PARENT := {
    "LeftUpperLeg": "Hips", "LeftLowerLeg": "LeftUpperLeg", "LeftFoot": "LeftLowerLeg",
    "RightUpperLeg": "Hips", "RightLowerLeg": "RightUpperLeg", "RightFoot": "RightLowerLeg",
}
const ALIASES := {
    "Hips": ["hips", "pelvis"],
    "LeftUpperLeg": ["leftupperleg", "leftupleg", "lupperleg"],
    "LeftLowerLeg": ["leftlowerleg", "leftleg", "llowerleg"],
    "LeftFoot": ["leftfoot", "lfoot"],
    "RightUpperLeg": ["rightupperleg", "rightupleg", "rupperleg"],
    "RightLowerLeg": ["rightlowerleg", "rightleg", "rlowerleg"],
    "RightFoot": ["rightfoot", "rfoot"],
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

func _collect_skeletons(node: Node, out: Array[Skeleton3D]) -> void:
    if node is Skeleton3D:
        out.append(node as Skeleton3D)
    for child in node.get_children():
        _collect_skeletons(child, out)

func _collect_players(node: Node, out: Array[AnimationPlayer]) -> void:
    if node is AnimationPlayer:
        out.append(node as AnimationPlayer)
    for child in node.get_children():
        _collect_players(child, out)

func _normalize(value: String) -> String:
    var n := value.to_lower()
    for token in [":", "/", ".", "-", "_", " "]:
        n = n.replace(token, "")
    for prefix in ["mixamorig", "armature", "general", "def"]:
        if n.begins_with(prefix):
            n = n.trim_prefix(prefix)
    return n

func _bone_index(skeleton: Skeleton3D, semantic: String) -> int:
    var aliases: Array = ALIASES[semantic]
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

func _write(payload: Dictionary) -> bool:
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
        push_error("CIV1_BILATERAL_TARGET_SAFE_FOOT_REFERENCE_FAIL: expected one Master_Rigged scene")
        quit(3)
        return

    var source_packed := load(_source_scene_paths[0]) as PackedScene
    var target_packed := load(TARGET_SCENE) as PackedScene
    if source_packed == null or target_packed == null:
        push_error("CIV1_BILATERAL_TARGET_SAFE_FOOT_REFERENCE_FAIL: source/target load failed")
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
        push_error("CIV1_BILATERAL_TARGET_SAFE_FOOT_REFERENCE_FAIL: Sprint missing")
        quit(5)
        return

    var source_skeletons: Array[Skeleton3D] = []
    var target_skeletons: Array[Skeleton3D] = []
    _collect_skeletons(source_instance, source_skeletons)
    _collect_skeletons(target_instance, target_skeletons)
    if source_skeletons.is_empty() or target_skeletons.size() != 1:
        push_error("CIV1_BILATERAL_TARGET_SAFE_FOOT_REFERENCE_FAIL: unexpected skeleton inventory")
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
        push_error("CIV1_BILATERAL_TARGET_SAFE_FOOT_REFERENCE_FAIL: semantic mapping incomplete")
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
        if PARENT.has(semantic):
            profile.set_bone_parent(i, StringName(source_names[String(PARENT[semantic])]))
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
        push_error("CIV1_BILATERAL_TARGET_SAFE_FOOT_REFERENCE_FAIL: invalid Sprint")
        quit(8)
        return

    var side_defs := {
        "Left": ["LeftLowerLeg", "LeftFoot"],
        "Right": ["RightLowerLeg", "RightFoot"],
    }
    var target_local_rest := {}
    for side in side_defs:
        var foot_semantic: String = side_defs[side][1]
        var foot_idx := int(target_map[foot_semantic])
        var target_local_rest_vector := target_skeleton.get_bone_rest(foot_idx).origin
        if target_local_rest_vector.length() <= 0.000001:
            push_error("CIV1_BILATERAL_TARGET_SAFE_FOOT_REFERENCE_FAIL: degenerate target local rest")
            quit(9)
            return
        target_local_rest[side] = target_local_rest_vector

    var left_local: Vector3 = target_local_rest["Left"]
    var right_local: Vector3 = target_local_rest["Right"]
    var left_direction := left_local.normalized()
    var mirrored_right_direction := Vector3(-right_local.x, right_local.y, right_local.z).normalized()
    var mirrored_common_direction := (left_direction + mirrored_right_direction).normalized()
    if mirrored_common_direction.length() <= 0.999999:
        push_error("CIV1_BILATERAL_TARGET_SAFE_FOOT_REFERENCE_FAIL: mirrored common direction degenerate")
        quit(10)
        return

    var target_safe_local := {
        "Left": mirrored_common_direction * left_local.length(),
        "Right": Vector3(-mirrored_common_direction.x, mirrored_common_direction.y, mirrored_common_direction.z) * right_local.length(),
    }

    var samples: Array[Dictionary] = []
    player.play(SOURCE_ANIMATION)
    player.advance(0.0)
    await process_frame
    for sample_idx in range(SAMPLE_COUNT):
        var t := animation.length * float(sample_idx) / float(SAMPLE_COUNT - 1)
        player.seek(t, true)
        player.advance(0.0)
        await process_frame
        var row := {"sample_index": sample_idx, "time_s": t, "sides": {}}
        for side in side_defs:
            var parent_semantic: String = side_defs[side][0]
            var foot_semantic: String = side_defs[side][1]
            var sp := int(source_map[parent_semantic])
            var sf := int(source_map[foot_semantic])
            var tp := int(target_map[parent_semantic])
            var tf := int(target_map[foot_semantic])
            var source_parent_pose := source_skeleton.get_bone_global_pose(sp)
            var source_foot_pose := source_skeleton.get_bone_global_pose(sf)
            var target_parent_pose := target_skeleton.get_bone_global_pose(tp)
            var target_foot_pose := target_skeleton.get_bone_global_pose(tf)
            var source_actual := source_foot_pose.origin - source_parent_pose.origin
            var baseline_actual := target_foot_pose.origin - target_parent_pose.origin
            var target_safe_reference_vector: Vector3 = target_safe_local[side]
            var target_safe_counterfactual := target_parent_pose.basis * target_safe_reference_vector
            var target_safe_foot_model := target_parent_pose.origin + target_safe_counterfactual
            row["sides"][side] = {
                "source_actual_relative_vector": _v3(source_actual),
                "baseline_actual_relative_vector": _v3(baseline_actual),
                "target_safe_counterfactual_vector": _v3(target_safe_counterfactual),
                "source_foot_model_origin": _v3(source_foot_pose.origin),
                "baseline_foot_model_origin": _v3(target_foot_pose.origin),
                "target_safe_foot_model_origin": _v3(target_safe_foot_model),
            }
        samples.append(row)

    var payload := {
        "format": "grand-bruxelles-civ1-bilateral-target-safe-foot-reference-v1",
        "godot_version": Engine.get_version_info(),
        "source_animation": SOURCE_ANIMATION,
        "animation_length_s": animation.length,
        "sample_count": SAMPLE_COUNT,
        "retarget_modifier": "RetargetModifier3D",
        "use_global_pose": false,
        "position_enabled": false,
        "rotation_enabled": true,
        "scale_enabled": false,
        "target_local_rest_vector": {
            "Left": _v3(left_local),
            "Right": _v3(right_local),
        },
        "mirrored_common_direction": _v3(mirrored_common_direction),
        "target_safe_reference_vector": {
            "Left": _v3(target_safe_local["Left"]),
            "Right": _v3(target_safe_local["Right"]),
        },
        "samples": samples,
        "diagnostic_only": true,
        "world_ground_assumed": false,
        "grounding_verified": false,
        "foot_slide_verified": false,
        "runtime_authorized": false,
        "visual_approval_claimed": false,
    }
    if not _write(payload):
        quit(11)
        return
    print("CIV1_BILATERAL_TARGET_SAFE_FOOT_REFERENCE_OK")
    quit(0)
