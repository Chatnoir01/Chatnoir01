extends SceneTree

const SOURCE_SCENE := "res://assets/animation_source.glb"
const TARGET_SCENE := "res://assets/npc_gate_01.glb"
const CLIPS: Array[String] = ["Jog_Fwd", "Sprint"]
const SAMPLE_RATE_HZ := 120.0
const MINIMUM_SAMPLES := 80
const GROUND_CLEARANCE_M := 0.02
const CONTACT_HEIGHT_WINDOW_M := 0.04
const MAX_GROUND_CORRECTION_SPAN_M := 0.18
const MAX_GROUND_CORRECTION_STEP_M := 0.08
const MAX_MEAN_TORSO_DELTA_DEG := 15.0
const MAX_PEAK_TORSO_DELTA_DEG := 30.0
const MAX_POSE_APPLICATION_ERROR_DEG := 0.05
const MAX_TARGET_BONE_LENGTH_ERROR_M := 0.0001
const TARGET_TO_SOURCE_LEG_RATIO := 0.966563730398298

const BONE_MAP := {
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

# Explicit parent-before-child order. This is part of the solver contract: every
# non-hips child origin is rebuilt from the already-posed target parent and the
# target's own local rest vector, so target bone lengths cannot stretch.
const ROLE_ORDER: Array[String] = [
    "hips",
    "spine", "chest", "upper_chest", "neck", "head",
    "left_shoulder", "left_upper_arm", "left_forearm", "left_hand",
    "right_shoulder", "right_upper_arm", "right_forearm", "right_hand",
    "left_upper_leg", "left_lower_leg", "left_foot", "left_toe",
    "right_upper_leg", "right_lower_leg", "right_foot", "right_toe"
]

var _failures: Array[String] = []
var _world: Node3D
var _source_instance: Node3D
var _target_instance: Node3D
var _source_skeleton: Skeleton3D
var _target_skeleton: Skeleton3D
var _source_player: AnimationPlayer
var _camera: Camera3D

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    _validate_static_mapping()
    _regression_model_space_global_rest_identity()
    _regression_target_bone_length_preservation()
    if not _failures.is_empty():
        _finish({})
        return

    root.size = Vector2i(1280, 720)
    _build_world()
    if not await _load_characters():
        _finish({})
        return

    var results: Dictionary = {}
    for clip: String in CLIPS:
        results[clip] = await _measure_clip(clip)

    var result := {
        "format": "grand-bruxelles-gate8-variant01-retarget-ab-result-v5",
        "engine_version": Engine.get_version_info().get("string", "unknown"),
        "candidate_variant": 1,
        "retarget_method": "godot_4_7_rotation_formula_hips_translation_only",
        "retarget_solver_revision": "model_space_global_rotation_target_lengths_v7",
        "reviewed_bonemap_roles": BONE_MAP.size(),
        "target_to_source_leg_ratio": TARGET_TO_SOURCE_LEG_RATIO,
        "rotation_enabled_for_all_mapped_roles": true,
        "translation_enabled_roles": ["hips"],
        "non_hips_target_positions_preserved_at_rest": true,
        "target_bone_lengths_preserved": true,
        "scale_enabled": false,
        "clips": results,
        "run_alias_selected": "",
        "selection_state": "MEASURED_REVIEW_REQUIRED",
        "retarget_experiment_applied": true,
        "production_authorized": false,
        "activation_ready": false,
        "adoption_ready": false,
        "runtime_population_changed": false,
        "visual_approval_claimed": false,
        "failures": _failures
    }
    _write_result(result)
    print("GATE8_VARIANT01_RETARGET_AB candidate=01 clips=2 failures=%d solver=model_space_global_rotation_target_lengths_v7 alias_selected=false production_authorized=false" % _failures.size())
    _finish(result)

func _build_world() -> void:
    _world = Node3D.new()
    _world.name = "RetargetABWorld"
    root.add_child(_world)

    var world_environment := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.16, 0.18, 0.21, 1.0)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.78, 0.80, 0.84, 1.0)
    env.ambient_light_energy = 1.05
    world_environment.environment = env
    _world.add_child(world_environment)

    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
    light.light_energy = 1.25
    light.shadow_enabled = true
    _world.add_child(light)

    var ground := MeshInstance3D.new()
    ground.name = "Ground"
    var plane := PlaneMesh.new()
    plane.size = Vector2(8.0, 8.0)
    ground.mesh = plane
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.30, 0.31, 0.32, 1.0)
    material.roughness = 0.92
    ground.material_override = material
    _world.add_child(ground)

    _camera = Camera3D.new()
    _camera.name = "WitnessCamera"
    _camera.fov = 58.0
    _camera.current = true
    _camera.look_at_from_position(Vector3(2.9, 1.45, 4.15), Vector3(0.0, 0.92, 0.0), Vector3.UP)
    _world.add_child(_camera)

func _load_characters() -> bool:
    var source_packed := load(SOURCE_SCENE) as PackedScene
    var target_packed := load(TARGET_SCENE) as PackedScene
    if source_packed == null or target_packed == null:
        _failures.append("source_or_target_scene_load_failed")
        return false

    _source_instance = source_packed.instantiate() as Node3D
    _target_instance = target_packed.instantiate() as Node3D
    if _source_instance == null or _target_instance == null:
        _failures.append("source_or_target_instance_not_node3d")
        return false

    _source_instance.name = "SourceAnimationRig"
    _source_instance.visible = false
    _target_instance.name = "Gate8Variant01Target"
    _world.add_child(_source_instance)
    _world.add_child(_target_instance)
    await process_frame

    _source_skeleton = _find_skeleton(_source_instance)
    _target_skeleton = _find_skeleton(_target_instance)
    _source_player = _find_animation_player_with_clips(_source_instance)
    if _source_skeleton == null:
        _failures.append("source_skeleton_missing")
    if _target_skeleton == null:
        _failures.append("target_skeleton_missing")
    if _source_player == null:
        _failures.append("source_animation_player_missing_required_clips")
    if not _failures.is_empty():
        return false

    _validate_mapping_against_skeletons()
    _validate_target_parent_order()
    return _failures.is_empty()

func _measure_clip(clip_token: String) -> Dictionary:
    var animation_name := _resolve_animation_name(_source_player, clip_token)
    if animation_name.is_empty():
        _failures.append("clip_missing=%s" % clip_token)
        return {}
    var animation := _source_player.get_animation(animation_name)
    if animation == null or animation.length <= 0.0:
        _failures.append("clip_invalid=%s" % clip_token)
        return {}

    var sample_count := maxi(MINIMUM_SAMPLES, int(ceil(animation.length * SAMPLE_RATE_HZ)))
    var dt := animation.length / float(sample_count)
    var left_positions: Array[Vector3] = []
    var right_positions: Array[Vector3] = []
    var torso_deltas: Array[float] = []
    var corrections: Array[float] = []
    var application_errors: Array[float] = []
    var length_errors: Array[float] = []
    var source_non_hips_translation: Array[float] = []

    _source_player.play(animation_name)
    for sample_index: int in range(sample_count):
        var time_s := minf(animation.length - 0.00001, float(sample_index) * dt)
        _source_player.seek(time_s, true)
        _source_player.advance(0.0)
        _source_skeleton.force_update_all_bone_transforms()
        _reset_target_pose()
        var transfer := _apply_retarget_pose()
        application_errors.append(float(transfer.get("application_error_deg", 0.0)))
        length_errors.append(float(transfer.get("target_bone_length_error_m", 0.0)))
        source_non_hips_translation.append(float(transfer.get("max_non_hips_source_translation_m", 0.0)))

        var left := _target_bone_global_position("left_foot")
        var right := _target_bone_global_position("right_foot")
        left_positions.append(left)
        right_positions.append(right)
        corrections.append(GROUND_CLEARANCE_M - minf(left.y, right.y))

        var source_bend := _torso_bend_pose(_source_skeleton, true)
        var target_bend := _torso_bend_pose(_target_skeleton, false)
        torso_deltas.append(absf(source_bend - target_bend))

    _source_player.stop()

    if left_positions.size() < MINIMUM_SAMPLES or right_positions.size() != left_positions.size():
        _failures.append("insufficient_samples clip=%s samples=%d" % [clip_token, left_positions.size()])
        return {}

    var raw_ground_y := INF
    for idx: int in range(left_positions.size()):
        raw_ground_y = minf(raw_ground_y, minf(left_positions[idx].y, right_positions[idx].y))
    var contact_limit := raw_ground_y + CONTACT_HEIGHT_WINDOW_M
    var left_slide := _contact_slide_metrics(left_positions, contact_limit, dt)
    var right_slide := _contact_slide_metrics(right_positions, contact_limit, dt)
    var combined_contacts := int(left_slide.get("samples", 0)) + int(right_slide.get("samples", 0))
    if combined_contacts <= 0:
        _failures.append("no_contact_samples clip=%s" % clip_token)

    var correction_min := _array_min(corrections)
    var correction_max := _array_max(corrections)
    var correction_span := correction_max - correction_min
    var correction_step_max := _max_adjacent_delta(corrections)
    var torso_mean := _array_mean(torso_deltas)
    var torso_peak := _array_max(torso_deltas)
    var application_error_max := _array_max(application_errors)
    var target_length_error_max := _array_max(length_errors)
    var source_non_hips_translation_max := _array_max(source_non_hips_translation)

    _gate_metric(clip_token, "ground_correction_span", correction_span, MAX_GROUND_CORRECTION_SPAN_M)
    _gate_metric(clip_token, "ground_correction_step", correction_step_max, MAX_GROUND_CORRECTION_STEP_M)
    _gate_metric(clip_token, "torso_mean_delta", torso_mean, MAX_MEAN_TORSO_DELTA_DEG)
    _gate_metric(clip_token, "torso_peak_delta", torso_peak, MAX_PEAK_TORSO_DELTA_DEG)
    _gate_metric(clip_token, "pose_application_error", application_error_max, MAX_POSE_APPLICATION_ERROR_DEG)
    _gate_metric(clip_token, "target_bone_length_error", target_length_error_max, MAX_TARGET_BONE_LENGTH_ERROR_M)

    var frame_path := await _capture_clip_frame(clip_token, animation_name, animation.length * 0.35)
    var mean_slide := (float(left_slide.get("mean_mps", 0.0)) + float(right_slide.get("mean_mps", 0.0))) * 0.5
    var peak_slide := maxf(float(left_slide.get("max_mps", 0.0)), float(right_slide.get("max_mps", 0.0)))
    if not is_finite(mean_slide) or not is_finite(peak_slide):
        _failures.append("non_finite_slide_metric clip=%s" % clip_token)

    print("GATE8_RETARGET_CLIP clip=%s duration=%.4f samples=%d contacts=%d mean_slide_mps=%.4f peak_slide_mps=%.4f ground_span_m=%.4f ground_step_m=%.4f torso_mean_deg=%.3f torso_peak_deg=%.3f application_error_deg=%.5f target_length_error_m=%.6f source_non_hips_translation_max_m=%.5f" % [
        clip_token, animation.length, sample_count, combined_contacts, mean_slide, peak_slide,
        correction_span, correction_step_max, torso_mean, torso_peak, application_error_max, target_length_error_max, source_non_hips_translation_max
    ])

    return {
        "animation_name": animation_name,
        "duration_s": animation.length,
        "sample_count": sample_count,
        "sample_rate_hz_effective": float(sample_count) / animation.length,
        "raw_ground_y": raw_ground_y,
        "ground_correction_min_m": correction_min,
        "ground_correction_max_m": correction_max,
        "ground_correction_span_m": correction_span,
        "ground_correction_max_step_m": correction_step_max,
        "left_contact_samples": int(left_slide.get("samples", 0)),
        "right_contact_samples": int(right_slide.get("samples", 0)),
        "mean_contact_slide_mps": mean_slide,
        "peak_contact_slide_mps": peak_slide,
        "mean_torso_bend_delta_deg": torso_mean,
        "peak_torso_bend_delta_deg": torso_peak,
        "max_pose_application_error_deg": application_error_max,
        "max_target_bone_length_error_m": target_length_error_max,
        "max_non_hips_source_translation_m": source_non_hips_translation_max,
        "frame_path": frame_path,
        "frame_width": 1280,
        "frame_height": 720
    }

func _apply_retarget_pose() -> Dictionary:
    var max_error := 0.0
    var max_length_error := 0.0
    var max_non_hips_source_translation := 0.0

    for role: String in ROLE_ORDER:
        var source_idx := _source_index(role)
        var target_idx := _target_index(role)
        if source_idx < 0 or target_idx < 0:
            continue

        var source_pose := _source_skeleton.get_bone_pose(source_idx)
        var source_rest := _source_skeleton.get_bone_rest(source_idx)
        var source_global_pose := _source_skeleton.get_bone_global_pose(source_idx)
        var source_global_rest := _source_skeleton.get_bone_global_rest(source_idx)
        var target_rest := _target_skeleton.get_bone_rest(target_idx)
        var target_global_rest := _target_skeleton.get_bone_global_rest(target_idx)

        var desired_basis := _model_space_target_basis(source_global_pose.basis, source_global_rest.basis, target_global_rest.basis)
        var desired_origin: Vector3
        if role == "hips":
            var source_parent := _source_skeleton.get_bone_parent(source_idx)
            var target_parent := _target_skeleton.get_bone_parent(target_idx)
            var source_parent_rest_basis := Basis.IDENTITY
            var target_parent_rest_basis := Basis.IDENTITY
            if source_parent >= 0:
                source_parent_rest_basis = _source_skeleton.get_bone_global_rest(source_parent).basis
            if target_parent >= 0:
                target_parent_rest_basis = _target_skeleton.get_bone_global_rest(target_parent).basis
            var root_alignment := (target_parent_rest_basis * source_parent_rest_basis.inverse()).orthonormalized()
            desired_origin = target_global_rest.origin + root_alignment * ((source_global_pose.origin - source_global_rest.origin) * TARGET_TO_SOURCE_LEG_RATIO)
        else:
            var target_parent_idx := _target_skeleton.get_bone_parent(target_idx)
            if target_parent_idx < 0:
                _failures.append("mapped_non_hips_parent_missing role=%s" % role)
                continue
            var target_parent_global_pose := _target_skeleton.get_bone_global_pose(target_parent_idx)
            desired_origin = target_parent_global_pose * target_rest.origin
            max_non_hips_source_translation = maxf(max_non_hips_source_translation, source_pose.origin.distance_to(source_rest.origin))

        var desired_global := Transform3D(desired_basis, desired_origin)
        _target_skeleton.set_bone_global_pose(target_idx, desired_global)
        var applied_global := _target_skeleton.get_bone_global_pose(target_idx)
        var desired_q := desired_basis.orthonormalized().get_rotation_quaternion().normalized()
        var applied_q := applied_global.basis.orthonormalized().get_rotation_quaternion().normalized()
        max_error = maxf(max_error, rad_to_deg(desired_q.angle_to(applied_q)))

        if role != "hips":
            var parent_idx := _target_skeleton.get_bone_parent(target_idx)
            var parent_origin := _target_skeleton.get_bone_global_pose(parent_idx).origin
            var expected_length := target_rest.origin.length()
            var applied_length := applied_global.origin.distance_to(parent_origin)
            max_length_error = maxf(max_length_error, absf(applied_length - expected_length))

    _target_skeleton.force_update_all_bone_transforms()
    return {
        "application_error_deg": max_error,
        "target_bone_length_error_m": max_length_error,
        "max_non_hips_source_translation_m": max_non_hips_source_translation
    }

func _model_space_target_basis(source_global_pose_basis: Basis, source_global_rest_basis: Basis, target_global_rest_basis: Basis) -> Basis:
    var source_global_delta := (source_global_pose_basis * source_global_rest_basis.inverse()).orthonormalized()
    return (source_global_delta * target_global_rest_basis).orthonormalized()

func _regression_model_space_global_rest_identity() -> void:
    var source_rest_basis := Basis(Vector3(0.2, 0.9, 0.3).normalized(), 0.47)
    var target_rest_basis := Basis(Vector3(0.7, 0.1, 0.6).normalized(), -0.62)
    var result := _model_space_target_basis(source_rest_basis, source_rest_basis, target_rest_basis)
    var error_deg := rad_to_deg(result.get_rotation_quaternion().angle_to(target_rest_basis.get_rotation_quaternion()))
    if error_deg > 0.0001:
        _failures.append("regression_model_space_rest_identity_failed rotation=%.6f" % error_deg)

func _regression_target_bone_length_preservation() -> void:
    var parent_pose := Transform3D(Basis(Vector3.UP, 0.83), Vector3(1.2, 0.7, -0.4))
    var child_rest_origin := Vector3(0.08, 0.42, -0.03)
    var child_origin := parent_pose * child_rest_origin
    var actual := child_origin.distance_to(parent_pose.origin)
    var expected := child_rest_origin.length()
    if absf(actual - expected) > 0.000001:
        _failures.append("regression_target_bone_length_failed actual=%.8f expected=%.8f" % [actual, expected])

func _capture_clip_frame(clip_token: String, animation_name: String, sample_time: float) -> String:
    _target_instance.position = Vector3.ZERO
    _source_player.play(animation_name)
    _source_player.seek(sample_time, true)
    _source_player.advance(0.0)
    _source_skeleton.force_update_all_bone_transforms()
    _reset_target_pose()
    _apply_retarget_pose()
    var left := _target_bone_global_position("left_foot")
    var right := _target_bone_global_position("right_foot")
    _target_instance.position.y = GROUND_CLEARANCE_M - minf(left.y, right.y)
    await process_frame
    await process_frame
    RenderingServer.force_draw(false)
    await process_frame
    var image := root.get_texture().get_image()
    var normalized := clip_token.to_lower().replace("_", "-")
    var path := "res://gate8_variant01_%s.png" % normalized
    if image == null or image.is_empty():
        _failures.append("capture_empty clip=%s" % clip_token)
        return ""
    if image.get_width() != 1280 or image.get_height() != 720:
        _failures.append("capture_size clip=%s got=%dx%d" % [clip_token, image.get_width(), image.get_height()])
        return ""
    var err := image.save_png(path)
    if err != OK:
        _failures.append("capture_save_failed clip=%s error=%d" % [clip_token, err])
        return ""
    _target_instance.position = Vector3.ZERO
    _source_player.stop()
    return path

func _reset_target_pose() -> void:
    for idx: int in range(_target_skeleton.get_bone_count()):
        _target_skeleton.reset_bone_pose(idx)
    _target_skeleton.force_update_all_bone_transforms()

func _contact_slide_metrics(positions: Array[Vector3], contact_limit_y: float, dt: float) -> Dictionary:
    var speeds: Array[float] = []
    for idx: int in range(1, positions.size()):
        var previous := positions[idx - 1]
        var current := positions[idx]
        if previous.y > contact_limit_y or current.y > contact_limit_y:
            continue
        var planar := Vector2(current.x - previous.x, current.z - previous.z).length()
        speeds.append(planar / maxf(dt, 0.000001))
    return {"samples": speeds.size(), "mean_mps": _array_mean(speeds), "max_mps": _array_max(speeds)}

func _torso_bend_pose(skeleton: Skeleton3D, source: bool) -> float:
    var spine_idx := _source_index("spine") if source else _target_index("spine")
    var chest_idx := _source_index("chest") if source else _target_index("chest")
    var neck_idx := _source_index("neck") if source else _target_index("neck")
    if spine_idx < 0 or chest_idx < 0 or neck_idx < 0:
        return 180.0
    var spine := skeleton.get_bone_global_pose(spine_idx).origin
    var chest := skeleton.get_bone_global_pose(chest_idx).origin
    var neck := skeleton.get_bone_global_pose(neck_idx).origin
    var lower := chest - spine
    var upper := neck - chest
    if lower.length_squared() <= 0.000001 or upper.length_squared() <= 0.000001:
        return 180.0
    return rad_to_deg(lower.normalized().angle_to(upper.normalized()))

func _target_bone_global_position(role: String) -> Vector3:
    var idx := _target_index(role)
    return Vector3.ZERO if idx < 0 else _target_skeleton.get_bone_global_pose(idx).origin

func _source_index(role: String) -> int:
    var pair: Array = BONE_MAP.get(role, [])
    return -1 if pair.size() < 2 else _source_skeleton.find_bone(String(pair[0]))

func _target_index(role: String) -> int:
    var pair: Array = BONE_MAP.get(role, [])
    return -1 if pair.size() < 2 else _target_skeleton.find_bone(String(pair[1]))

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D
    for child: Node in node.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null

func _find_animation_player_with_clips(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        var player := node as AnimationPlayer
        var has_all := true
        for clip: String in CLIPS:
            if _resolve_animation_name(player, clip).is_empty():
                has_all = false
                break
        if has_all:
            return player
    for child: Node in node.get_children():
        var found := _find_animation_player_with_clips(child)
        if found != null:
            return found
    return null

func _resolve_animation_name(player: AnimationPlayer, token: String) -> String:
    for raw_name: StringName in player.get_animation_list():
        var name := String(raw_name)
        if name == token or name.ends_with("/%s" % token):
            return name
    return ""

func _validate_static_mapping() -> void:
    if BONE_MAP.size() != 22:
        _failures.append("reviewed_bonemap_role_count=%d expected=22" % BONE_MAP.size())
    if ROLE_ORDER.size() != 22:
        _failures.append("role_order_count=%d expected=22" % ROLE_ORDER.size())
    var source_seen := {}
    var target_seen := {}
    var role_seen := {}
    for role: String in ROLE_ORDER:
        if role_seen.has(role):
            _failures.append("duplicate_order_role=%s" % role)
        role_seen[role] = true
        if not BONE_MAP.has(role):
            _failures.append("ordered_role_not_mapped=%s" % role)
    for role_value: Variant in BONE_MAP.keys():
        var role := String(role_value)
        if not role_seen.has(role):
            _failures.append("mapped_role_not_ordered=%s" % role)
        var pair: Array = BONE_MAP[role]
        if pair.size() != 2:
            _failures.append("mapping_pair_invalid role=%s" % role)
            continue
        var source_name := String(pair[0])
        var target_name := String(pair[1])
        if source_name.is_empty() or target_name.is_empty():
            _failures.append("mapping_empty role=%s" % role)
        if source_seen.has(source_name):
            _failures.append("duplicate_source_bone=%s" % source_name)
        if target_seen.has(target_name):
            _failures.append("duplicate_target_bone=%s" % target_name)
        source_seen[source_name] = true
        target_seen[target_name] = true
    if String((BONE_MAP["upper_chest"] as Array)[1]) != "spine_03":
        _failures.append("reviewed_upper_chest_drift")
    if String((BONE_MAP["left_shoulder"] as Array)[1]) != "clavicle_l" or String((BONE_MAP["right_shoulder"] as Array)[1]) != "clavicle_r":
        _failures.append("reviewed_clavicle_mapping_drift")
    if String((BONE_MAP["left_toe"] as Array)[1]) != "ball_l" or String((BONE_MAP["right_toe"] as Array)[1]) != "ball_r":
        _failures.append("reviewed_toe_mapping_drift")

func _validate_mapping_against_skeletons() -> void:
    for role_value: Variant in BONE_MAP.keys():
        var role := String(role_value)
        if _source_index(role) < 0:
            _failures.append("source_bone_missing role=%s" % role)
        if _target_index(role) < 0:
            _failures.append("target_bone_missing role=%s" % role)

func _validate_target_parent_order() -> void:
    var order_index := {}
    for i: int in range(ROLE_ORDER.size()):
        order_index[ROLE_ORDER[i]] = i
    var target_role_by_index := {}
    for role_value: Variant in BONE_MAP.keys():
        var role := String(role_value)
        var idx := _target_index(role)
        if idx >= 0:
            target_role_by_index[idx] = role
    for role: String in ROLE_ORDER:
        if role == "hips":
            continue
        var idx := _target_index(role)
        var parent_idx := _target_skeleton.get_bone_parent(idx)
        if not target_role_by_index.has(parent_idx):
            _failures.append("mapped_parent_not_mapped role=%s parent=%s" % [role, _target_skeleton.get_bone_name(parent_idx) if parent_idx >= 0 else "none"])
            continue
        var parent_role := String(target_role_by_index[parent_idx])
        if int(order_index[parent_role]) >= int(order_index[role]):
            _failures.append("mapped_parent_order_invalid role=%s parent_role=%s" % [role, parent_role])

func _gate_metric(clip: String, key: String, value: float, limit: float) -> void:
    if value > limit:
        _failures.append("%s clip=%s value=%.4f limit=%.4f" % [key, clip, value, limit])

func _array_mean(values: Array[float]) -> float:
    if values.is_empty():
        return 0.0
    var total := 0.0
    for value: float in values:
        total += value
    return total / float(values.size())

func _array_min(values: Array[float]) -> float:
    if values.is_empty():
        return 0.0
    var result := INF
    for value: float in values:
        result = minf(result, value)
    return result

func _array_max(values: Array[float]) -> float:
    if values.is_empty():
        return 0.0
    var result := -INF
    for value: float in values:
        result = maxf(result, value)
    return result

func _max_adjacent_delta(values: Array[float]) -> float:
    var result := 0.0
    for idx: int in range(1, values.size()):
        result = maxf(result, absf(values[idx] - values[idx - 1]))
    return result

func _write_result(result: Dictionary) -> void:
    var file := FileAccess.open("res://gate8_variant01_retarget_ab_result.json", FileAccess.WRITE)
    if file == null:
        _failures.append("result_file_open_failed")
        return
    file.store_string(JSON.stringify(result, "  "))
    file.close()

func _finish(_result: Dictionary) -> void:
    if _failures.is_empty():
        print("GATE8_VARIANT01_RETARGET_AB_OK candidate=01 clips=Jog_Fwd,Sprint solver=model_space_global_rotation_target_lengths_v7 alias_selected=false production_authorized=false")
        quit(0)
        return
    for failure: String in _failures:
        push_error("GATE8_VARIANT01_RETARGET_AB_FAIL %s" % failure)
    quit(1)
