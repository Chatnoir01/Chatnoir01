extends SceneTree

const SOURCE_SCENE := "res://assets/animation_source.glb"
const TARGET_SCENE := "res://assets/npc_gate_01.glb"
const CLIPS: Array[String] = ["Jog_Fwd", "Sprint"]
const SAMPLE_RATE_HZ := 60.0
const MIN_SAMPLES := 40
const CONTACT_WINDOW_M := 0.04
const MIN_TARGET_POSE_DELTA_DEG := 5.0
const SETTLE_FRAMES := 1
const ROLE_PAIRS := {
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
    "right_toe": ["DEF-toe.R", "ball_r"],
}
const ROLE_PARENT := {
    "hips": "",
    "spine": "hips",
    "chest": "spine",
    "upper_chest": "chest",
    "neck": "upper_chest",
    "head": "neck",
    "left_shoulder": "upper_chest",
    "left_upper_arm": "left_shoulder",
    "left_forearm": "left_upper_arm",
    "left_hand": "left_forearm",
    "right_shoulder": "upper_chest",
    "right_upper_arm": "right_shoulder",
    "right_forearm": "right_upper_arm",
    "right_hand": "right_forearm",
    "left_upper_leg": "hips",
    "left_lower_leg": "left_upper_leg",
    "left_foot": "left_lower_leg",
    "left_toe": "left_foot",
    "right_upper_leg": "hips",
    "right_lower_leg": "right_upper_leg",
    "right_foot": "right_lower_leg",
    "right_toe": "right_foot",
}
const MOTION_ROLES: Array[String] = [
    "hips", "chest", "left_upper_arm", "right_upper_arm",
    "left_upper_leg", "right_upper_leg", "left_lower_leg", "right_lower_leg",
]

var _failures: Array[String] = []
var _source_real: Skeleton3D
var _source_probe: Skeleton3D
var _target_probe: Skeleton3D
var _player: AnimationPlayer
var _source_role_indices: Dictionary = {}
var _source_probe_role_indices: Dictionary = {}
var _target_probe_role_indices: Dictionary = {}

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var source_scene := _instantiate(SOURCE_SCENE)
    var target_scene := _instantiate(TARGET_SCENE)
    if source_scene == null or target_scene == null:
        _finish({})
        return
    root.add_child(source_scene)
    root.add_child(target_scene)
    await process_frame
    _source_real = _find_skeleton(source_scene)
    var target_real := _find_skeleton(target_scene)
    _player = _find_player_with_clips(source_scene)
    if _source_real == null or target_real == null or _player == null:
        _failures.append("required_source_target_or_player_missing")
        _finish({})
        return

    _source_probe = _clone_skeleton_data(_source_real)
    _target_probe = _clone_skeleton_data(target_real)
    _source_probe.name = "CanonicalAnimatedSource"
    _target_probe.name = "CanonicalRetargetTarget"
    root.add_child(_source_probe)
    source_scene.visible = false
    target_scene.visible = false

    var source_renamed := _canonicalize(_source_probe, 0)
    var target_renamed := _canonicalize(_target_probe, 1)
    _cache_role_indices()
    if not _failures.is_empty():
        _finish({})
        return

    var profile := _build_profile()
    var modifier := RetargetModifier3D.new()
    modifier.name = "NativeRetargetAB"
    modifier.set_use_global_pose(false)
    modifier.set_position_enabled(false)
    modifier.set_rotation_enabled(true)
    modifier.set_scale_enabled(false)
    _source_probe.add_child(modifier)
    modifier.add_child(_target_probe)
    modifier.set_profile(profile)
    await _settle()

    var clip_results := {}
    for clip in CLIPS:
        clip_results[clip] = await _measure_clip(clip)

    var result := {
        "format": "grand-bruxelles-gate8-variant01-native-modifier-ab-v2",
        "engine_version": Engine.get_version_info().get("string", "unknown"),
        "candidate_variant": 1,
        "reviewed_roles": ROLE_PAIRS.size(),
        "source_renamed_roles": source_renamed,
        "target_renamed_roles": target_renamed,
        "stable_role_index_cache": true,
        "source_cached_roles": _source_role_indices.size(),
        "source_probe_cached_roles": _source_probe_role_indices.size(),
        "target_probe_cached_roles": _target_probe_role_indices.size(),
        "profile_bone_count": profile.bone_size,
        "native_modifier": true,
        "use_global_pose": modifier.is_using_global_pose(),
        "position_enabled": modifier.is_position_enabled(),
        "rotation_enabled": modifier.is_rotation_enabled(),
        "scale_enabled": modifier.is_scale_enabled(),
        "clips": clip_results,
        "run_alias_selected": "",
        "selection_state": "MEASURED_NATIVE_AB_REVIEW_REQUIRED" if _failures.is_empty() else "BLOCKED_NATIVE_AB_MEASUREMENT",
        "production_authorized": false,
        "activation_ready": false,
        "adoption_ready": false,
        "runtime_population_changed": false,
        "visual_approval_claimed": false,
        "failures": _failures,
    }
    _write_result(result)
    print("GATE8_NATIVE_AB clips=%d failures=%d cached_roles=%d alias_selected=false production_authorized=false" % [CLIPS.size(), _failures.size(), _target_probe_role_indices.size()])
    _finish(result)

func _cache_role_indices() -> void:
    for role_value in ROLE_PAIRS.keys():
        var role := String(role_value)
        var pair: Array = ROLE_PAIRS[role]
        var source_idx := _source_real.find_bone(String(pair[0]))
        var source_probe_idx := _source_probe.find_bone(_canonical(role))
        var target_probe_idx := _target_probe.find_bone(_canonical(role))
        if source_idx < 0:
            _failures.append("source_role_index_missing=%s" % role)
        else:
            _source_role_indices[role] = source_idx
        if source_probe_idx < 0:
            _failures.append("source_probe_role_index_missing=%s" % role)
        else:
            _source_probe_role_indices[role] = source_probe_idx
        if target_probe_idx < 0:
            _failures.append("target_probe_role_index_missing=%s" % role)
        else:
            _target_probe_role_indices[role] = target_probe_idx
    if _source_role_indices.size() != ROLE_PAIRS.size() or _source_probe_role_indices.size() != ROLE_PAIRS.size() or _target_probe_role_indices.size() != ROLE_PAIRS.size():
        _failures.append("role_index_cache_incomplete source=%d source_probe=%d target_probe=%d expected=%d" % [_source_role_indices.size(), _source_probe_role_indices.size(), _target_probe_role_indices.size(), ROLE_PAIRS.size()])

func _measure_clip(token: String) -> Dictionary:
    var animation_name := _resolve_animation_name(_player, token)
    if animation_name.is_empty():
        _failures.append("clip_missing=%s" % token)
        return {}
    var animation := _player.get_animation(animation_name)
    if animation == null or animation.length <= 0.0:
        _failures.append("clip_invalid=%s" % token)
        return {}
    var sample_count := maxi(MIN_SAMPLES, int(ceil(animation.length * SAMPLE_RATE_HZ)))
    var dt := animation.length / float(sample_count)
    var left_positions: Array[Vector3] = []
    var right_positions: Array[Vector3] = []
    var min_ground_y := INF
    var max_motion_delta_deg := 0.0
    _player.play(animation_name)
    for sample_index in range(sample_count):
        var t := minf(animation.length - 0.00001, float(sample_index) * dt)
        _player.seek(t, true)
        _player.advance(0.0)
        _source_real.force_update_all_bone_transforms()
        _copy_reviewed_pose_to_probe()
        _source_probe.force_update_all_bone_transforms()
        await _settle()
        _target_probe.force_update_all_bone_transforms()
        var left := _target_bone_position("left_foot")
        var right := _target_bone_position("right_foot")
        left_positions.append(left)
        right_positions.append(right)
        min_ground_y = minf(min_ground_y, minf(left.y, right.y))
        max_motion_delta_deg = maxf(max_motion_delta_deg, _target_motion_delta_deg())
    _player.stop()
    if left_positions.size() < MIN_SAMPLES:
        _failures.append("insufficient_samples clip=%s samples=%d" % [token, left_positions.size()])
        return {}
    if max_motion_delta_deg < MIN_TARGET_POSE_DELTA_DEG:
        _failures.append("native_target_motion_too_small clip=%s peak_deg=%.3f" % [token, max_motion_delta_deg])
    var contact_limit := min_ground_y + CONTACT_WINDOW_M
    var left_slide := _contact_metrics(left_positions, contact_limit, dt)
    var right_slide := _contact_metrics(right_positions, contact_limit, dt)
    var contacts := int(left_slide["samples"]) + int(right_slide["samples"])
    if contacts <= 0:
        _failures.append("no_contact_samples clip=%s" % token)
    var correction_min := INF
    var correction_max := -INF
    for i in range(left_positions.size()):
        var correction := -minf(left_positions[i].y, right_positions[i].y)
        correction_min = minf(correction_min, correction)
        correction_max = maxf(correction_max, correction)
    var ground_span := correction_max - correction_min
    var mean_slide := (float(left_slide["mean_mps"]) + float(right_slide["mean_mps"])) * 0.5
    var peak_slide := maxf(float(left_slide["max_mps"]), float(right_slide["max_mps"]))
    var strikes := int(left_slide["strikes"]) + int(right_slide["strikes"])
    var cadence_spm := float(strikes) * 60.0 / animation.length
    print("GATE8_NATIVE_AB_CLIP clip=%s duration=%.4f samples=%d contacts=%d cadence_spm=%.2f mean_slide_mps=%.4f peak_slide_mps=%.4f ground_span_m=%.4f peak_pose_delta_deg=%.3f" % [token, animation.length, sample_count, contacts, cadence_spm, mean_slide, peak_slide, ground_span, max_motion_delta_deg])
    return {
        "animation_name": animation_name,
        "duration_s": animation.length,
        "sample_count": sample_count,
        "contact_samples": contacts,
        "foot_strikes": strikes,
        "cadence_spm": cadence_spm,
        "mean_contact_slide_mps": mean_slide,
        "peak_contact_slide_mps": peak_slide,
        "ground_correction_span_m": ground_span,
        "peak_target_pose_delta_deg": max_motion_delta_deg,
    }

func _copy_reviewed_pose_to_probe() -> void:
    for role_value in ROLE_PAIRS.keys():
        var role := String(role_value)
        var source_idx := int(_source_role_indices[role])
        var probe_idx := int(_source_probe_role_indices[role])
        _source_probe.set_bone_pose_position(probe_idx, _source_real.get_bone_pose_position(source_idx))
        _source_probe.set_bone_pose_rotation(probe_idx, _source_real.get_bone_pose_rotation(source_idx))
        _source_probe.set_bone_pose_scale(probe_idx, _source_real.get_bone_pose_scale(source_idx))

func _target_motion_delta_deg() -> float:
    var peak := 0.0
    for role in MOTION_ROLES:
        var idx := int(_target_probe_role_indices[role])
        peak = maxf(peak, rad_to_deg(_target_probe.get_bone_rest(idx).basis.get_rotation_quaternion().angle_to(_target_probe.get_bone_pose_rotation(idx))))
    return peak

func _target_bone_position(role: String) -> Vector3:
    if not _target_probe_role_indices.has(role):
        _failures.append("target_bone_index_uncached=%s" % role)
        return Vector3.ZERO
    return _target_probe.get_bone_global_pose(int(_target_probe_role_indices[role])).origin

func _contact_metrics(rows: Array[Vector3], contact_limit: float, dt: float) -> Dictionary:
    var samples := 0
    var strikes := 0
    var sum_speed := 0.0
    var max_speed := 0.0
    var was_contact := false
    for i in range(1, rows.size()):
        var contact := rows[i].y <= contact_limit
        if contact and not was_contact:
            strikes += 1
        if contact and rows[i - 1].y <= contact_limit:
            var delta := rows[i] - rows[i - 1]
            delta.y = 0.0
            var speed := delta.length() / dt
            samples += 1
            sum_speed += speed
            max_speed = maxf(max_speed, speed)
        was_contact = contact
    return {"samples": samples, "strikes": strikes, "mean_mps": sum_speed / float(samples) if samples > 0 else 0.0, "max_mps": max_speed}

func _find_player_with_clips(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        var player := node as AnimationPlayer
        if not _resolve_animation_name(player, CLIPS[0]).is_empty() and not _resolve_animation_name(player, CLIPS[1]).is_empty():
            return player
    for child in node.get_children():
        var found := _find_player_with_clips(child)
        if found != null:
            return found
    return null

func _resolve_animation_name(player: AnimationPlayer, token: String) -> String:
    for name_value in player.get_animation_list():
        var name := String(name_value)
        if name.split("/")[-1] == token:
            return name
    return ""

func _clone_skeleton_data(real: Skeleton3D) -> Skeleton3D:
    var clone := Skeleton3D.new()
    clone.motion_scale = real.motion_scale
    for idx in range(real.get_bone_count()):
        clone.add_bone(real.get_bone_name(idx))
        clone.set_bone_rest(idx, real.get_bone_rest(idx))
        clone.set_bone_pose_position(idx, real.get_bone_pose_position(idx))
        clone.set_bone_pose_rotation(idx, real.get_bone_pose_rotation(idx))
        clone.set_bone_pose_scale(idx, real.get_bone_pose_scale(idx))
    for idx in range(real.get_bone_count()):
        clone.set_bone_parent(idx, real.get_bone_parent(idx))
    return clone

func _canonicalize(skeleton: Skeleton3D, side: int) -> int:
    var renamed := 0
    for role_value in ROLE_PAIRS.keys():
        var role := String(role_value)
        var pair: Array = ROLE_PAIRS[role]
        var idx := skeleton.find_bone(String(pair[side]))
        if idx < 0:
            _failures.append("bone_missing side=%d role=%s" % [side, role])
            continue
        skeleton.set_bone_name(idx, _canonical(role))
        if skeleton.get_bone_name(idx) == _canonical(role):
            renamed += 1
    return renamed

func _build_profile() -> SkeletonProfile:
    var profile := SkeletonProfile.new()
    profile.bone_size = ROLE_PAIRS.size()
    var i := 0
    for role_value in ROLE_PAIRS.keys():
        var role := String(role_value)
        profile.set_bone_name(i, _canonical(role))
        var parent_role := String(ROLE_PARENT[role])
        if not parent_role.is_empty():
            profile.set_bone_parent(i, _canonical(parent_role))
        profile.set_required(i, true)
        i += 1
    profile.root_bone = _canonical("hips")
    profile.scale_base_bone = _canonical("hips")
    return profile

func _canonical(role: String) -> String:
    return "gb_humanoid_%s" % role

func _settle() -> void:
    for _i in range(SETTLE_FRAMES):
        await process_frame

func _instantiate(path: String) -> Node3D:
    var packed := load(path) as PackedScene
    if packed == null:
        _failures.append("scene_load_failed=%s" % path)
        return null
    return packed.instantiate() as Node3D

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null

func _write_result(result: Dictionary) -> void:
    var file := FileAccess.open("res://gate8_variant01_native_modifier_ab_result.json", FileAccess.WRITE)
    if file == null:
        _failures.append("result_file_open_failed")
        return
    file.store_string(JSON.stringify(result, "  "))
    file.close()

func _finish(_result: Dictionary) -> void:
    if _failures.is_empty():
        print("GATE8_NATIVE_AB_OK measured=true stable_role_indices=true alias_selected=false production_authorized=false")
        quit(0)
        return
    for failure in _failures:
        push_error("GATE8_NATIVE_AB_FAIL %s" % failure)
    quit(1)
