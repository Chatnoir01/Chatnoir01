extends SceneTree

const SOURCE_ANIMATION := "UAL1_Standard/Sprint"
const SOURCE_SCENE_SUFFIX := "Models_with_rigging/Master_Rigged.tscn"
const TARGET_SCENE := "res://civ1_body.glb"
const SAMPLE_COUNT := 121
const LEG_SEMANTICS := [
    "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
    "RightUpperLeg", "RightLowerLeg", "RightFoot",
]
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

func _quat_delta_deg(a: Quaternion, b: Quaternion) -> float:
    return rad_to_deg(a.normalized().angle_to(b.normalized()))

func _local_rest_rotation(skeleton: Skeleton3D, idx: int) -> Quaternion:
    return skeleton.get_bone_rest(idx).basis.get_rotation_quaternion()

func _pose_rotation(skeleton: Skeleton3D, idx: int) -> Quaternion:
    return skeleton.get_bone_pose_rotation(idx)

func _append_metric(store: Dictionary, semantic: String, key: String, value: float) -> void:
    if not store.has(semantic):
        store[semantic] = {}
    var semantic_store: Dictionary = store[semantic]
    if not semantic_store.has(key):
        semantic_store[key] = []
    var values: Array = semantic_store[key]
    values.append(value)

func _summarize(values: Array) -> Dictionary:
    if values.is_empty():
        return {"min_deg": 0.0, "mean_deg": 0.0, "max_deg": 0.0}
    var min_v := INF
    var max_v := -INF
    var total := 0.0
    for raw in values:
        var value := float(raw)
        min_v = minf(min_v, value)
        max_v = maxf(max_v, value)
        total += value
    return {"min_deg": min_v, "mean_deg": total / float(values.size()), "max_deg": max_v}

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
        push_error("CIV1_LEG_CHAIN_DIAGNOSTIC_FAIL: expected one Master_Rigged scene")
        quit(3)
        return

    var source_packed := load(_source_scene_paths[0]) as PackedScene
    var target_packed := load(TARGET_SCENE) as PackedScene
    if source_packed == null or target_packed == null:
        push_error("CIV1_LEG_CHAIN_DIAGNOSTIC_FAIL: source/target load failed")
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
        push_error("CIV1_LEG_CHAIN_DIAGNOSTIC_FAIL: Sprint missing")
        quit(5)
        return

    var source_skeletons: Array[Skeleton3D] = []
    var target_skeletons: Array[Skeleton3D] = []
    _collect_skeletons(source_instance, source_skeletons)
    _collect_skeletons(target_instance, target_skeletons)
    if source_skeletons.is_empty() or target_skeletons.size() != 1:
        push_error("CIV1_LEG_CHAIN_DIAGNOSTIC_FAIL: unexpected skeleton inventory")
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
        push_error("CIV1_LEG_CHAIN_DIAGNOSTIC_FAIL: required semantic mapping incomplete")
        quit(7)
        return

    var source_names := {}
    for semantic in SEMANTICS:
        source_names[semantic] = source_skeleton.get_bone_name(int(source_map[semantic]))

    var rest_diagnostics := {}
    for semantic in LEG_SEMANTICS:
        var source_idx := int(source_map[semantic])
        var target_idx := int(target_map[semantic])
        var source_rest_q := _local_rest_rotation(source_skeleton, source_idx)
        var target_rest_q := _local_rest_rotation(target_skeleton, target_idx)
        rest_diagnostics[semantic] = {
            "source_bone_name": String(source_skeleton.get_bone_name(source_idx)),
            "target_bone_name": String(target_skeleton.get_bone_name(target_idx)),
            "rest_local_rotation_delta_deg": _quat_delta_deg(source_rest_q, target_rest_q),
        }

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
        push_error("CIV1_LEG_CHAIN_DIAGNOSTIC_FAIL: invalid Sprint animation")
        quit(8)
        return

    var pose_samples := {}
    player.play(SOURCE_ANIMATION)
    player.advance(0.0)
    await process_frame
    for sample_idx in range(SAMPLE_COUNT):
        var t := animation.length * float(sample_idx) / float(SAMPLE_COUNT - 1)
        player.seek(t, true)
        player.advance(0.0)
        await process_frame
        for semantic in LEG_SEMANTICS:
            var source_idx := int(source_map[semantic])
            var target_idx := int(target_map[semantic])
            var source_pose_q := _pose_rotation(source_skeleton, source_idx)
            var target_pose_q := _pose_rotation(target_skeleton, target_idx)
            var source_rest_q := _local_rest_rotation(source_skeleton, source_idx)
            var target_rest_q := _local_rest_rotation(target_skeleton, target_idx)
            _append_metric(pose_samples, semantic, "pose_local_rotation_delta_deg", _quat_delta_deg(source_pose_q, target_pose_q))
            _append_metric(pose_samples, semantic, "source_pose_from_rest_deg", _quat_delta_deg(source_rest_q, source_pose_q))
            _append_metric(pose_samples, semantic, "target_pose_from_rest_deg", _quat_delta_deg(target_rest_q, target_pose_q))

    var pose_diagnostics := {}
    for semantic in LEG_SEMANTICS:
        var semantic_samples: Dictionary = pose_samples[semantic]
        pose_diagnostics[semantic] = {
            "pose_local_rotation_delta_deg": _summarize(semantic_samples["pose_local_rotation_delta_deg"]),
            "source_pose_from_rest_deg": _summarize(semantic_samples["source_pose_from_rest_deg"]),
            "target_pose_from_rest_deg": _summarize(semantic_samples["target_pose_from_rest_deg"]),
        }

    var payload := {
        "format": "grand-bruxelles-civ1-leg-chain-diagnostic-v1",
        "godot_version": Engine.get_version_info(),
        "source_animation": SOURCE_ANIMATION,
        "sample_count": SAMPLE_COUNT,
        "retarget_modifier": "RetargetModifier3D",
        "use_global_pose": false,
        "position_enabled": false,
        "rotation_enabled": true,
        "scale_enabled": false,
        "leg_chain_rest_diagnostics": rest_diagnostics,
        "leg_chain_pose_diagnostics": pose_diagnostics,
        "diagnostic_only": true,
        "runtime_authorized": false,
        "visual_approval_claimed": false,
    }

    if not _write_payload(payload):
        quit(9)
        return
    print("CIV1_LEG_CHAIN_DIAGNOSTIC_OK")
    quit(0)
