extends SceneTree

const SOURCE_ANIMATION := "UAL1_Standard/Sprint"
const SOURCE_SCENE_SUFFIX := "Models_with_rigging/Master_Rigged.tscn"
const TARGET_SCENE := "res://civ1_body.glb"

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
    "UpperChest": ["upperchest", "spine2"],
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

const REQUIRED_ANCESTRY := [
    ["Hips", "LeftUpperLeg"], ["LeftUpperLeg", "LeftLowerLeg"], ["LeftLowerLeg", "LeftFoot"],
    ["Hips", "RightUpperLeg"], ["RightUpperLeg", "RightLowerLeg"], ["RightLowerLeg", "RightFoot"],
    ["Hips", "Spine"], ["Spine", "Chest"], ["Chest", "Neck"], ["Neck", "Head"],
    ["Chest", "LeftShoulder"], ["LeftShoulder", "LeftUpperArm"], ["LeftUpperArm", "LeftLowerArm"], ["LeftLowerArm", "LeftHand"],
    ["Chest", "RightShoulder"], ["RightShoulder", "RightUpperArm"], ["RightUpperArm", "RightLowerArm"], ["RightLowerArm", "RightHand"],
]

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
            mapped[semantic] = {
                "index": idx,
                "bone_name": skeleton.get_bone_name(idx),
            }
    var optional_upper_chest_idx := _bone_index_by_semantic(skeleton, "UpperChest")
    if optional_upper_chest_idx >= 0:
        mapped["UpperChest"] = {
            "index": optional_upper_chest_idx,
            "bone_name": skeleton.get_bone_name(optional_upper_chest_idx),
        }
    return {"mapped": mapped, "missing": missing}

func _is_ancestor(skeleton: Skeleton3D, ancestor_idx: int, child_idx: int) -> bool:
    var cursor := child_idx
    while cursor >= 0:
        cursor = skeleton.get_bone_parent(cursor)
        if cursor == ancestor_idx:
            return true
    return false

func _hierarchy_violations(skeleton: Skeleton3D, mapping: Dictionary) -> Array[String]:
    var violations: Array[String] = []
    var mapped: Dictionary = mapping["mapped"]
    for pair in REQUIRED_ANCESTRY:
        var parent_semantic := String(pair[0])
        var child_semantic := String(pair[1])
        if not mapped.has(parent_semantic) or not mapped.has(child_semantic):
            continue
        var parent_idx := int(mapped[parent_semantic]["index"])
        var child_idx := int(mapped[child_semantic]["index"])
        if not _is_ancestor(skeleton, parent_idx, child_idx):
            violations.append(parent_semantic + "->" + child_semantic)
    return violations

func _rest_span(skeleton: Skeleton3D, mapping: Dictionary) -> float:
    var mapped: Dictionary = mapping["mapped"]
    if not mapped.has("Hips") or not mapped.has("Head"):
        return 0.0
    var hips_idx := int(mapped["Hips"]["index"])
    var head_idx := int(mapped["Head"]["index"])
    var hips := skeleton.get_bone_global_rest(hips_idx).origin
    var head := skeleton.get_bone_global_rest(head_idx).origin
    return hips.distance_to(head)

func _run() -> void:
    _scan_dir("res://")
    _source_scene_paths.sort()
    if _source_scene_paths.size() != 1:
        push_error("CIV1_SPRINT_RETARGET_PREFLIGHT_FAIL: expected exactly one Quaternius Master_Rigged scene")
        quit(3)
        return

    var source_packed := load(_source_scene_paths[0]) as PackedScene
    var target_packed := load(TARGET_SCENE) as PackedScene
    if source_packed == null or target_packed == null:
        push_error("CIV1_SPRINT_RETARGET_PREFLIGHT_FAIL: source or target scene failed to load")
        quit(4)
        return

    var source_instance := source_packed.instantiate()
    var target_instance := target_packed.instantiate()
    root.add_child(source_instance)
    root.add_child(target_instance)
    await process_frame

    var source_players: Array[AnimationPlayer] = []
    _collect_players(source_instance, source_players)
    var sprint_player: AnimationPlayer = null
    for player in source_players:
        if player.has_animation(SOURCE_ANIMATION):
            sprint_player = player
            break
    if sprint_player == null:
        push_error("CIV1_SPRINT_RETARGET_PREFLIGHT_FAIL: Sprint animation missing")
        quit(5)
        return

    var source_skeletons: Array[Skeleton3D] = []
    var target_skeletons: Array[Skeleton3D] = []
    _collect_skeletons(source_instance, source_skeletons)
    _collect_skeletons(target_instance, target_skeletons)
    if source_skeletons.is_empty() or target_skeletons.size() != 1:
        push_error("CIV1_SPRINT_RETARGET_PREFLIGHT_FAIL: unexpected skeleton inventory")
        quit(6)
        return

    var source_skeleton: Skeleton3D = source_skeletons[0]
    var player_root := sprint_player.get_node_or_null(NodePath(sprint_player.root_node))
    if player_root is Skeleton3D:
        source_skeleton = player_root as Skeleton3D
    var target_skeleton := target_skeletons[0]

    var profile := SkeletonProfileHumanoid.new()
    var source_mapping := _mapping_for(source_skeleton)
    var target_mapping := _mapping_for(target_skeleton)
    var source_violations := _hierarchy_violations(source_skeleton, source_mapping)
    var target_violations := _hierarchy_violations(target_skeleton, target_mapping)
    var source_span := _rest_span(source_skeleton, source_mapping)
    var target_span := _rest_span(target_skeleton, target_mapping)
    var scale_ratio := target_span / source_span if source_span > 0.000001 else 0.0

    var mapped_required_bones := REQUIRED_SEMANTICS.size() - (target_mapping["missing"] as Array).size()
    var preflight_passed := (
        (source_mapping["missing"] as Array).is_empty()
        and (target_mapping["missing"] as Array).is_empty()
        and source_violations.is_empty()
        and target_violations.is_empty()
        and source_span > 0.01
        and target_span > 0.01
        and scale_ratio > 0.2
        and scale_ratio < 5.0
    )

    var payload := {
        "format": "grand-bruxelles-civ1-sprint-retarget-preflight-v1",
        "godot_version": Engine.get_version_info(),
        "source_animation": SOURCE_ANIMATION,
        "source_scene": _source_scene_paths[0],
        "target_scene": TARGET_SCENE,
        "skeleton_profile": "SkeletonProfileHumanoid",
        "profile_bone_count": profile.bone_size,
        "profile_root_bone": profile.root_bone,
        "profile_scale_base_bone": profile.scale_base_bone,
        "source_bone_count": source_skeleton.get_bone_count(),
        "target_bone_count": target_skeleton.get_bone_count(),
        "required_semantic_bone_count": REQUIRED_SEMANTICS.size(),
        "mapped_required_bones": mapped_required_bones,
        "unmapped_required_bones": target_mapping["missing"],
        "source_unmapped_required_bones": source_mapping["missing"],
        "source_hierarchy_violations": source_violations,
        "target_hierarchy_violations": target_violations,
        "source_rest_hips_to_head_m": source_span,
        "target_rest_hips_to_head_m": target_span,
        "source_to_target_scale_ratio": scale_ratio,
        "source_mapping": source_mapping["mapped"],
        "target_mapping": target_mapping["mapped"],
        "mapping_preflight_passed": preflight_passed,
        "diagnostic_only": true,
        "retarget_ready": false,
        "animation_transferred": false,
        "world_ground_assumed": false,
        "grounding_verified": false,
        "foot_slide_verified": false,
        "visual_approval_claimed": false,
    }

    var out := FileAccess.open(_output_path, FileAccess.WRITE)
    if out == null:
        quit(7)
        return
    out.store_string(JSON.stringify(payload, "  "))
    out.close()

    if not preflight_passed:
        push_error("CIV1_SPRINT_RETARGET_PREFLIGHT_FAIL: humanoid mapping or hierarchy incomplete")
        quit(8)
        return
    print("CIV1_SPRINT_RETARGET_PREFLIGHT_OK")
    quit(0)
