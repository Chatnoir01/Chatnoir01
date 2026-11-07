extends SceneTree

const SOURCE_ANIMATION := "UAL1_Standard/Sprint"
const SOURCE_SCENE_SUFFIX := "Models_with_rigging/Master_Rigged.tscn"
const TARGET_SCENE := "res://civ1_body.glb"
const SAMPLE_COUNT := 121
const SEMANTICS := ["Hips", "LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg"]
const PARENT := {
    "LeftUpperLeg": "Hips", "LeftLowerLeg": "LeftUpperLeg",
    "RightUpperLeg": "Hips", "RightLowerLeg": "RightUpperLeg",
}
const ALIASES := {
    "Hips": ["hips", "pelvis"],
    "LeftUpperLeg": ["leftupperleg", "leftupleg", "lupperleg"],
    "LeftLowerLeg": ["leftlowerleg", "leftleg", "llowerleg"],
    "RightUpperLeg": ["rightupperleg", "rightupleg", "rupperleg"],
    "RightLowerLeg": ["rightlowerleg", "rightleg", "rlowerleg"],
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

func _basis_rows(b: Basis) -> Array:
    return [_v3(b.x), _v3(b.y), _v3(b.z)]

func _mirror_x(v: Vector3) -> Vector3:
    return Vector3(-v.x, v.y, v.z)

func _axis_counterfactual(target_local: Vector3, source_in_target_basis: Vector3, axis: int) -> Vector3:
    var candidate := target_local
    candidate[axis] = source_in_target_basis[axis]
    if candidate.length() <= 0.000001:
        return target_local
    return candidate.normalized() * target_local.length()

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
        push_error("CIV1_UPPERLEG_LOWERLEG_REST_ROTATION_FAIL: expected one Master_Rigged scene")
        quit(3)
        return

    var source_packed := load(_source_scene_paths[0]) as PackedScene
    var target_packed := load(TARGET_SCENE) as PackedScene
    if source_packed == null or target_packed == null:
        push_error("CIV1_UPPERLEG_LOWERLEG_REST_ROTATION_FAIL: source/target load failed")
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
        push_error("CIV1_UPPERLEG_LOWERLEG_REST_ROTATION_FAIL: Sprint missing")
        quit(5)
        return

    var source_skeletons: Array[Skeleton3D] = []
    var target_skeletons: Array[Skeleton3D] = []
    _collect_skeletons(source_instance, source_skeletons)
    _collect_skeletons(target_instance, target_skeletons)
    if source_skeletons.is_empty() or target_skeletons.size() != 1:
        push_error("CIV1_UPPERLEG_LOWERLEG_REST_ROTATION_FAIL: unexpected skeleton inventory")
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
        push_error("CIV1_UPPERLEG_LOWERLEG_REST_ROTATION_FAIL: semantic mapping incomplete")
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
        push_error("CIV1_UPPERLEG_LOWERLEG_REST_ROTATION_FAIL: invalid Sprint")
        quit(8)
        return

    var side_defs := {
        "Left": ["LeftUpperLeg", "LeftLowerLeg"],
        "Right": ["RightUpperLeg", "RightLowerLeg"],
    }
    var rest_meta := {}
    for side in side_defs:
        var parent_semantic: String = side_defs[side][0]
        var child_semantic: String = side_defs[side][1]
        var source_parent_idx := int(source_map[parent_semantic])
        var source_child_idx := int(source_map[child_semantic])
        var target_parent_idx := int(target_map[parent_semantic])
        var target_child_idx := int(target_map[child_semantic])
        var source_local_rest := source_skeleton.get_bone_rest(source_child_idx).origin
        var target_local_rest := target_skeleton.get_bone_rest(target_child_idx).origin
        var source_parent_global_rest := source_skeleton.get_bone_global_rest(source_parent_idx)
        var target_parent_global_rest := target_skeleton.get_bone_global_rest(target_parent_idx)
        if source_local_rest.length() <= 0.000001 or target_local_rest.length() <= 0.000001:
            push_error("CIV1_UPPERLEG_LOWERLEG_REST_ROTATION_FAIL: degenerate rest vector")
            quit(9)
            return
        var source_world_rest := source_parent_global_rest.basis * source_local_rest
        var source_rest_in_target_parent_basis := target_parent_global_rest.basis.inverse() * source_world_rest
        source_rest_in_target_parent_basis = source_rest_in_target_parent_basis.normalized() * target_local_rest.length()
        rest_meta[side] = {
            "parent_semantic": parent_semantic,
            "child_semantic": child_semantic,
            "source_local_rest": source_local_rest,
            "target_local_rest": target_local_rest,
            "source_parent_global_rest_basis": source_parent_global_rest.basis,
            "target_parent_global_rest_basis": target_parent_global_rest.basis,
            "source_direction_target_length": source_local_rest.normalized() * target_local_rest.length(),
            "source_rest_in_target_parent_basis": source_rest_in_target_parent_basis,
            "axis_counterfactual_x": _axis_counterfactual(target_local_rest, source_rest_in_target_parent_basis, 0),
            "axis_counterfactual_y": _axis_counterfactual(target_local_rest, source_rest_in_target_parent_basis, 1),
            "axis_counterfactual_z": _axis_counterfactual(target_local_rest, source_rest_in_target_parent_basis, 2),
        }

    var left_world_rest: Vector3 = rest_meta["Left"]["target_parent_global_rest_basis"] * rest_meta["Left"]["target_local_rest"]
    var right_world_rest: Vector3 = rest_meta["Right"]["target_parent_global_rest_basis"] * rest_meta["Right"]["target_local_rest"]
    var right_world_mirrored: Vector3 = _mirror_x(right_world_rest)
    var canonical_world_direction: Vector3 = (left_world_rest.normalized() + right_world_mirrored.normalized()).normalized()
    if canonical_world_direction.length() <= 0.000001:
        push_error("CIV1_UPPERLEG_LOWERLEG_REST_ROTATION_FAIL: degenerate common mirrored direction")
        quit(10)
        return
    var common_parent_rest_basis: Basis = rest_meta["Left"]["target_parent_global_rest_basis"]
    for side in side_defs:
        var side_world_direction: Vector3 = canonical_world_direction if side == "Left" else _mirror_x(canonical_world_direction)
        var side_parent_basis: Basis = rest_meta[side]["target_parent_global_rest_basis"]
        var target_length: float = rest_meta[side]["target_local_rest"].length()
        rest_meta[side]["common_mirrored_target_local_rest"] = side_parent_basis.inverse() * side_world_direction * target_length

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
            var child_semantic: String = side_defs[side][1]
            var sp := int(source_map[parent_semantic])
            var sc := int(source_map[child_semantic])
            var tp := int(target_map[parent_semantic])
            var tc := int(target_map[child_semantic])
            var source_parent_pose := source_skeleton.get_bone_global_pose(sp)
            var source_child_pose := source_skeleton.get_bone_global_pose(sc)
            var target_parent_pose := target_skeleton.get_bone_global_pose(tp)
            var target_child_pose := target_skeleton.get_bone_global_pose(tc)
            var source_actual := source_child_pose.origin - source_parent_pose.origin
            var target_actual := target_child_pose.origin - target_parent_pose.origin
            var target_local_rest: Vector3 = rest_meta[side]["target_local_rest"]
            var source_direction_target_length: Vector3 = rest_meta[side]["source_direction_target_length"]
            var common_mirrored_target_local_rest: Vector3 = rest_meta[side]["common_mirrored_target_local_rest"]
            var source_parent_basis: Basis = source_parent_pose.basis.orthonormalized()
            var target_parent_basis: Basis = target_parent_pose.basis.orthonormalized()
            var parent_rotation_delta: Basis = source_parent_basis.inverse() * target_parent_basis
            var parent_rotation_delta_euler: Vector3 = parent_rotation_delta.get_euler()
            var parent_rotation_delta_angle: float = parent_rotation_delta.get_rotation_quaternion().get_angle()
            var rotated_target_rest_vector := target_parent_pose.basis * target_local_rest
            var source_rest_direction_counterfactual := target_parent_pose.basis * source_direction_target_length
            var source_parent_rotation_counterfactual := source_parent_pose.basis * target_local_rest
            var common_mirrored_target_rest_counterfactual := target_parent_pose.basis * common_mirrored_target_local_rest
            var axis_counterfactual_x: Vector3 = target_parent_pose.basis * rest_meta[side]["axis_counterfactual_x"]
            var axis_counterfactual_y: Vector3 = target_parent_pose.basis * rest_meta[side]["axis_counterfactual_y"]
            var axis_counterfactual_z: Vector3 = target_parent_pose.basis * rest_meta[side]["axis_counterfactual_z"]
            var local_translation_residual := target_actual - rotated_target_rest_vector
            row["sides"][side] = {
                "source_actual_relative_vector": _v3(source_actual),
                "target_actual_relative_vector": _v3(target_actual),
                "rotated_target_rest_vector": _v3(rotated_target_rest_vector),
                "source_rest_direction_counterfactual": _v3(source_rest_direction_counterfactual),
                "source_parent_rotation_counterfactual": _v3(source_parent_rotation_counterfactual),
                "common_mirrored_target_rest_counterfactual": _v3(common_mirrored_target_rest_counterfactual),
                "axis_counterfactual_x": _v3(axis_counterfactual_x),
                "axis_counterfactual_y": _v3(axis_counterfactual_y),
                "axis_counterfactual_z": _v3(axis_counterfactual_z),
                "parent_rotation_delta_angle_rad": parent_rotation_delta_angle,
                "parent_rotation_delta_euler_rad": _v3(parent_rotation_delta_euler),
                "local_translation_residual": _v3(local_translation_residual),
            }
        samples.append(row)

    var payload := {
        "format": "grand-bruxelles-civ1-upperleg-lowerleg-rest-rotation-v4",
        "godot_version": Engine.get_version_info(),
        "source_animation": SOURCE_ANIMATION,
        "animation_length_s": animation.length,
        "sample_count": SAMPLE_COUNT,
        "retarget_modifier": "RetargetModifier3D",
        "use_global_pose": false,
        "position_enabled": false,
        "rotation_enabled": true,
        "scale_enabled": false,
        "common_parent_rest_basis": _basis_rows(common_parent_rest_basis),
        "canonical_mirrored_world_direction": _v3(canonical_world_direction),
        "rest_vectors": {
            "Left": {
                "source": _v3(rest_meta["Left"]["source_local_rest"]),
                "target": _v3(rest_meta["Left"]["target_local_rest"]),
                "source_parent_rest_basis": _basis_rows(rest_meta["Left"]["source_parent_global_rest_basis"]),
                "target_parent_rest_basis": _basis_rows(rest_meta["Left"]["target_parent_global_rest_basis"]),
                "source_rest_in_target_parent_basis": _v3(rest_meta["Left"]["source_rest_in_target_parent_basis"]),
                "axis_counterfactual_x": _v3(rest_meta["Left"]["axis_counterfactual_x"]),
                "axis_counterfactual_y": _v3(rest_meta["Left"]["axis_counterfactual_y"]),
                "axis_counterfactual_z": _v3(rest_meta["Left"]["axis_counterfactual_z"]),
                "common_mirrored_target": _v3(rest_meta["Left"]["common_mirrored_target_local_rest"]),
            },
            "Right": {
                "source": _v3(rest_meta["Right"]["source_local_rest"]),
                "target": _v3(rest_meta["Right"]["target_local_rest"]),
                "source_parent_rest_basis": _basis_rows(rest_meta["Right"]["source_parent_global_rest_basis"]),
                "target_parent_rest_basis": _basis_rows(rest_meta["Right"]["target_parent_global_rest_basis"]),
                "source_rest_in_target_parent_basis": _v3(rest_meta["Right"]["source_rest_in_target_parent_basis"]),
                "axis_counterfactual_x": _v3(rest_meta["Right"]["axis_counterfactual_x"]),
                "axis_counterfactual_y": _v3(rest_meta["Right"]["axis_counterfactual_y"]),
                "axis_counterfactual_z": _v3(rest_meta["Right"]["axis_counterfactual_z"]),
                "common_mirrored_target": _v3(rest_meta["Right"]["common_mirrored_target_local_rest"]),
            },
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
    print("CIV1_UPPERLEG_LOWERLEG_REST_ROTATION_OK")
    quit(0)
