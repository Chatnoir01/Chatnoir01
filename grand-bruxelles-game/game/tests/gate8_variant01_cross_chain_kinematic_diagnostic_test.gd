extends SceneTree

const SOURCE_SCENE := "res://assets/animation_source.glb"
const TARGET_SCENE := "res://assets/npc_gate_01.glb"
const CLIPS: Array[String] = ["Jog_Fwd", "Sprint"]
const SAMPLE_RATE_HZ := 60.0
const MIN_SAMPLES := 40
const EXPECTED_ROLES := 22
const MAX_COMBINED_BOUND_EXCESS_M := 0.002
const MAX_SEGMENT_LENGTH_ERROR_M := 0.0001
const ROLE_ORDER: Array[String] = [
    "hips", "spine", "chest", "upper_chest", "neck", "head",
    "left_shoulder", "left_upper_arm", "left_forearm", "left_hand",
    "right_shoulder", "right_upper_arm", "right_forearm", "right_hand",
    "left_upper_leg", "left_lower_leg", "left_foot", "left_toe",
    "right_upper_leg", "right_lower_leg", "right_foot", "right_toe"
]
const ROLE_MAP := {
    "hips": ["DEF-hips", "pelvis"],
    "spine": ["DEF-spine.001", "spine_01"],
    "chest": ["DEF-spine.002", "spine_02"],
    "upper_chest": ["DEF-spine.003", "spine_03"],
    "neck": ["DEF-neck", "neck_01"],
    "head": ["DEF-head", "head"],
    "left_shoulder": ["DEF-shoulder.L", "clavicle_l"],
    "left_upper_arm": ["DEF-upper_arm.L", "upperarm_l"],
    "left_forearm": ["DEF-forearm.L", "lowerarm_l"],
    "left_hand": ["DEF-hand.L", "hand_l"],
    "right_shoulder": ["DEF-shoulder.R", "clavicle_r"],
    "right_upper_arm": ["DEF-upper_arm.R", "upperarm_r"],
    "right_forearm": ["DEF-forearm.R", "lowerarm_r"],
    "right_hand": ["DEF-hand.R", "hand_r"],
    "left_upper_leg": ["DEF-thigh.L", "thigh_l"],
    "left_lower_leg": ["DEF-shin.L", "calf_l"],
    "left_foot": ["DEF-foot.L", "foot_l"],
    "left_toe": ["DEF-toe.L", "ball_l"],
    "right_upper_leg": ["DEF-thigh.R", "thigh_r"],
    "right_lower_leg": ["DEF-shin.R", "calf_r"],
    "right_foot": ["DEF-foot.R", "foot_r"],
    "right_toe": ["DEF-toe.R", "ball_r"]
}

var _failures: Array[String] = []
var _source: Skeleton3D
var _target: Skeleton3D
var _player: AnimationPlayer
var _source_indices: Dictionary = {}
var _target_indices: Dictionary = {}
var _target_rest_positions: Dictionary = {}
var _target_rest_segment_lengths: Dictionary = {}

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var source_packed := load(SOURCE_SCENE) as PackedScene
    var target_packed := load(TARGET_SCENE) as PackedScene
    if source_packed == null or target_packed == null:
        _failures.append("source_or_target_load_failed")
        _finish({})
        return
    var source_scene := source_packed.instantiate() as Node3D
    var target_scene := target_packed.instantiate() as Node3D
    if source_scene == null or target_scene == null:
        _failures.append("source_or_target_instance_failed")
        _finish({})
        return
    root.add_child(source_scene)
    root.add_child(target_scene)
    await process_frame
    await process_frame
    _source = _find_skeleton(source_scene)
    _target = _find_skeleton(target_scene)
    _player = _find_animation_player(source_scene)
    if _source == null or _target == null or _player == null:
        _failures.append("required_skeleton_or_animation_player_missing")
        _finish({})
        return
    if not _build_role_cache():
        _finish({})
        return
    _capture_target_rest_geometry()

    var clips: Dictionary = {}
    var global_max_excess := 0.0
    var global_max_segment_error := 0.0
    var global_worst_clip := ""
    var global_worst_endpoint := ""
    for clip: String in CLIPS:
        var row := _measure_clip(clip)
        clips[clip] = row
        var excess := float(row.get("max_combined_bound_excess_m", 0.0))
        var segment_error := float(row.get("max_segment_length_error_m", 0.0))
        if excess > global_max_excess:
            global_max_excess = excess
            global_worst_clip = clip
            global_worst_endpoint = String(row.get("worst_endpoint_role", ""))
        global_max_segment_error = maxf(global_max_segment_error, segment_error)

    if global_max_excess > MAX_COMBINED_BOUND_EXCESS_M:
        _failures.append("combined_kinematic_bound_exceeded clip=%s endpoint=%s excess_m=%.6f limit=%.6f" % [global_worst_clip, global_worst_endpoint, global_max_excess, MAX_COMBINED_BOUND_EXCESS_M])
    if global_max_segment_error > MAX_SEGMENT_LENGTH_ERROR_M:
        _failures.append("combined_segment_length_error value=%.8f limit=%.8f" % [global_max_segment_error, MAX_SEGMENT_LENGTH_ERROR_M])

    var result := {
        "format": "grand-bruxelles-gate8-cross-chain-kinematic-diagnostic-v1",
        "engine_version": Engine.get_version_info().get("string", "unknown"),
        "candidate_variant": 1,
        "reviewed_role_count": ROLE_ORDER.size(),
        "clips": clips,
        "max_combined_bound_excess_m": global_max_excess,
        "max_combined_bound_excess_allowed_m": MAX_COMBINED_BOUND_EXCESS_M,
        "max_segment_length_error_m": global_max_segment_error,
        "max_segment_length_error_allowed_m": MAX_SEGMENT_LENGTH_ERROR_M,
        "worst_clip": global_worst_clip,
        "worst_endpoint_role": global_worst_endpoint,
        "diagnostic_state": "CROSS_CHAIN_BOUND_INVALID" if not _failures.is_empty() else "CROSS_CHAIN_BOUND_VALID",
        "retarget_applied": false,
        "target_skin_modified": false,
        "target_rest_modified": false,
        "run_alias_selected": "",
        "production_authorized": false,
        "activation_ready": false,
        "adoption_ready": false,
        "runtime_population_changed": false,
        "visual_approval_claimed": false,
        "failures": _failures
    }
    _write_result(result)
    print("GATE8_CROSS_CHAIN_KINEMATIC state=%s max_excess_m=%.6f segment_error_m=%.8f clip=%s endpoint=%s" % [result["diagnostic_state"], global_max_excess, global_max_segment_error, global_worst_clip, global_worst_endpoint])
    _finish(result)

func _build_role_cache() -> bool:
    if ROLE_ORDER.size() != EXPECTED_ROLES or ROLE_MAP.size() != EXPECTED_ROLES:
        _failures.append("reviewed_role_count_changed")
        return false
    for role: String in ROLE_ORDER:
        var pair: Array = ROLE_MAP[role]
        var source_idx := _source.find_bone(String(pair[0]))
        var target_idx := _target.find_bone(String(pair[1]))
        if source_idx < 0:
            _failures.append("source_bone_missing role=%s" % role)
        if target_idx < 0:
            _failures.append("target_bone_missing role=%s" % role)
        _source_indices[role] = source_idx
        _target_indices[role] = target_idx
    return _failures.is_empty()

func _capture_target_rest_geometry() -> void:
    _target.reset_bone_poses()
    _target.force_update_all_bone_transforms()
    for role: String in ROLE_ORDER:
        var idx := int(_target_indices[role])
        _target_rest_positions[role] = _target.get_bone_global_pose(idx).origin
        var parent_idx := _target.get_bone_parent(idx)
        if parent_idx >= 0:
            _target_rest_segment_lengths[role] = _target.get_bone_global_pose(idx).origin.distance_to(_target.get_bone_global_pose(parent_idx).origin)
        else:
            _target_rest_segment_lengths[role] = 0.0

func _measure_clip(clip: String) -> Dictionary:
    var animation_name := _resolve_animation_name(_player, clip)
    if animation_name.is_empty():
        _failures.append("clip_missing=%s" % clip)
        return {}
    var animation := _player.get_animation(animation_name)
    if animation == null or animation.length <= 0.0:
        _failures.append("clip_invalid=%s" % clip)
        return {}
    var sample_count := maxi(MIN_SAMPLES, int(ceil(animation.length * SAMPLE_RATE_HZ)))
    var max_excess := 0.0
    var max_segment_error := 0.0
    var max_displacement := 0.0
    var worst_endpoint := ""
    var worst_time_s := 0.0
    for sample_idx: int in range(sample_count):
        var time_s := minf(animation.length - 0.00001, animation.length * float(sample_idx) / float(sample_count))
        _sample_source(animation_name, time_s)
        var deltas := _apply_combined_pose()
        _target.force_update_all_bone_transforms()
        max_segment_error = maxf(max_segment_error, _measure_segment_length_error())
        for endpoint: String in ROLE_ORDER:
            var current := _target.get_bone_global_pose(int(_target_indices[endpoint])).origin
            var rest_position: Vector3 = _target_rest_positions[endpoint]
            var displacement := current.distance_to(rest_position)
            var bound := _combined_endpoint_bound(endpoint, deltas)
            var excess := maxf(0.0, displacement - bound)
            if displacement > max_displacement:
                max_displacement = displacement
            if excess > max_excess:
                max_excess = excess
                worst_endpoint = endpoint
                worst_time_s = time_s
    _target.reset_bone_poses()
    _target.force_update_all_bone_transforms()
    return {
        "animation_name": animation_name,
        "sample_count": sample_count,
        "max_target_pivot_displacement_m": max_displacement,
        "max_combined_bound_excess_m": max_excess,
        "max_segment_length_error_m": max_segment_error,
        "worst_endpoint_role": worst_endpoint,
        "worst_time_s": worst_time_s
    }

func _apply_combined_pose() -> Dictionary:
    _target.reset_bone_poses()
    var deltas: Dictionary = {}
    for role: String in ROLE_ORDER:
        var source_idx := int(_source_indices[role])
        var target_idx := int(_target_indices[role])
        var source_rest_q := _source.get_bone_rest(source_idx).basis.orthonormalized().get_rotation_quaternion().normalized()
        var source_pose_q := _source.get_bone_pose(source_idx).basis.orthonormalized().get_rotation_quaternion().normalized()
        var delta_q := (source_rest_q.inverse() * source_pose_q).normalized()
        var target_rest_q := _target.get_bone_rest(target_idx).basis.orthonormalized().get_rotation_quaternion().normalized()
        _target.set_bone_pose_rotation(target_idx, (target_rest_q * delta_q).normalized())
        deltas[role] = delta_q
    return deltas

func _combined_endpoint_bound(endpoint: String, deltas: Dictionary) -> float:
    var endpoint_idx := int(_target_indices[endpoint])
    var endpoint_rest: Vector3 = _target_rest_positions[endpoint]
    var total_bound := 0.0
    for joint_role: String in ROLE_ORDER:
        var joint_idx := int(_target_indices[joint_role])
        if joint_idx == endpoint_idx or not _is_descendant_or_same(endpoint_idx, joint_idx):
            continue
        var joint_rest: Vector3 = _target_rest_positions[joint_role]
        var radius := endpoint_rest.distance_to(joint_rest)
        var delta_q: Quaternion = deltas.get(joint_role, Quaternion.IDENTITY)
        var angle := Quaternion.IDENTITY.angle_to(delta_q)
        total_bound += 2.0 * radius * sin(angle * 0.5)
    return total_bound

func _measure_segment_length_error() -> float:
    var max_error := 0.0
    for role: String in ROLE_ORDER:
        if role == "hips":
            continue
        var idx := int(_target_indices[role])
        var parent_idx := _target.get_bone_parent(idx)
        if parent_idx < 0:
            continue
        var actual := _target.get_bone_global_pose(idx).origin.distance_to(_target.get_bone_global_pose(parent_idx).origin)
        var expected := float(_target_rest_segment_lengths[role])
        max_error = maxf(max_error, absf(actual - expected))
    return max_error

func _is_descendant_or_same(candidate_idx: int, ancestor_idx: int) -> bool:
    var cursor := candidate_idx
    while cursor >= 0:
        if cursor == ancestor_idx:
            return true
        cursor = _target.get_bone_parent(cursor)
    return false

func _sample_source(animation_name: String, time_s: float) -> void:
    _player.play(animation_name)
    _player.pause()
    _player.seek(time_s, true)
    _player.advance(0.0)
    _source.force_update_all_bone_transforms()

func _resolve_animation_name(player: AnimationPlayer, token: String) -> String:
    var wanted := token.to_lower()
    for animation_name in player.get_animation_list():
        var raw := String(animation_name)
        var leaf := raw.get_slice("/", raw.get_slice_count("/") - 1)
        if leaf.to_lower() == wanted:
            return raw
    return ""

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null

func _find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer
    for child in node.get_children():
        var found := _find_animation_player(child)
        if found != null:
            return found
    return null

func _write_result(result: Dictionary) -> void:
    var file := FileAccess.open("res://gate8_variant01_cross_chain_kinematic_diagnostic_result.json", FileAccess.WRITE)
    if file == null:
        _failures.append("result_file_open_failed")
        return
    file.store_string(JSON.stringify(result, "\t"))
    file.close()

func _finish(_result: Dictionary) -> void:
    if _failures.is_empty():
        quit(0)
    for failure: String in _failures:
        push_error(failure)
    quit(1)
