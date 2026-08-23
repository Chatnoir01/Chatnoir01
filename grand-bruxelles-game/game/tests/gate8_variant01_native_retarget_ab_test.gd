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
const MIN_SOURCE_ANIMATION_MOTION_M := 0.02

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
    "right_toe": ["DEF-toe.R", "ball_r"]
}

const ROLE_ORDER: Array[String] = [
    "hips",
    "spine", "chest", "upper_chest", "neck", "head",
    "left_shoulder", "left_upper_arm", "left_forearm", "left_hand",
    "right_shoulder", "right_upper_arm", "right_forearm", "right_hand",
    "left_upper_leg", "left_lower_leg", "left_foot", "left_toe",
    "right_upper_leg", "right_lower_leg", "right_foot", "right_toe"
]

const PARENT_ROLE := {
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
    "right_toe": "right_foot"
}

var _failures: Array[String] = []
var _world: Node3D
var _source_instance: Node3D
var _target_instance: Node3D
var _source_skeleton: Skeleton3D
var _target_skeleton: Skeleton3D
var _source_player: AnimationPlayer
var _modifier: RetargetModifier3D
var _camera: Camera3D
var _ground: MeshInstance3D
var _target_meshes: Array[MeshInstance3D] = []
var _source_tracks_remapped := 0
var _source_bones_renamed := 0
var _target_names_unchanged := true
var _resolved_target_mesh_bindings := 0

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    if ROLE_PAIRS.size() != 22 or ROLE_ORDER.size() != 22:
        _failures.append("reviewed_role_count_changed pairs=%d order=%d" % [ROLE_PAIRS.size(), ROLE_ORDER.size()])
        _finish({})
        return

    root.size = Vector2i(1280, 720)
    _build_world()
    if not await _load_characters():
        _finish({})
        return

    var target_name_snapshot := _snapshot_target_names()
    _source_tracks_remapped = _remap_source_animation_tracks_to_target_names()
    _source_bones_renamed = _rename_source_bones_to_target_names()
    _verify_target_names_unchanged(target_name_snapshot)

    if _source_tracks_remapped <= 0:
        _failures.append("source_animation_tracks_not_remapped")
    if _source_bones_renamed != ROLE_PAIRS.size():
        _failures.append("source_bone_rename_count=%d expected=%d" % [_source_bones_renamed, ROLE_PAIRS.size()])
    if not _target_names_unchanged:
        _failures.append("target_bone_names_changed")
    if not _failures.is_empty():
        _finish({})
        return

    _source_player.stop()
    if _source_player.has_method("clear_caches"):
        _source_player.call("clear_caches")

    var source_motion := _measure_source_animation_motion()
    for clip: String in CLIPS:
        var movement := float(source_motion.get(clip, 0.0))
        if movement < MIN_SOURCE_ANIMATION_MOTION_M:
            _failures.append("source_animation_lost_after_runtime_remap clip=%s motion=%.5f" % [clip, movement])

    if not _setup_native_modifier():
        _finish({})
        return

    var results: Dictionary = {}
    for clip: String in CLIPS:
        results[clip] = await _measure_clip(clip)

    var result := {
        "format": "grand-bruxelles-gate8-variant01-native-retarget-ab-result-v1",
        "engine_version": Engine.get_version_info().get("string", "unknown"),
        "candidate_variant": 1,
        "retarget_method": "RetargetModifier3D_source_canonicalized_to_target_native_names",
        "reviewed_roles": ROLE_PAIRS.size(),
        "source_bones_renamed": _source_bones_renamed,
        "source_animation_tracks_remapped": _source_tracks_remapped,
        "target_bone_names_unchanged": _target_names_unchanged,
        "resolved_target_mesh_bindings": _resolved_target_mesh_bindings,
        "source_animation_motion_m": source_motion,
        "modifier": {
            "use_global_pose": _modifier.is_using_global_pose(),
            "position_enabled": _modifier.is_position_enabled(),
            "rotation_enabled": _modifier.is_rotation_enabled(),
            "scale_enabled": _modifier.is_scale_enabled(),
            "profile_bone_count": _modifier.get_profile().get_bone_size()
        },
        "clips": results,
        "run_alias_selected": "",
        "selection_state": "NATIVE_AB_MEASURED_REVIEW_REQUIRED",
        "production_authorized": false,
        "activation_ready": false,
        "adoption_ready": false,
        "runtime_population_changed": false,
        "visual_approval_claimed": false,
        "source_asset_modified": false,
        "target_asset_modified": false,
        "failures": _failures
    }
    _write_result(result)
    print("GATE8_NATIVE_RETARGET_AB candidate=01 clips=2 failures=%d source_renamed=%d target_names_unchanged=%s bindings=%d alias_selected=false production_authorized=false" % [
        _failures.size(), _source_bones_renamed, str(_target_names_unchanged), _resolved_target_mesh_bindings
    ])
    _finish(result)

func _build_world() -> void:
    _world = Node3D.new()
    _world.name = "Gate8NativeABWorld"
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

    _ground = MeshInstance3D.new()
    _ground.name = "Ground"
    var plane := PlaneMesh.new()
    plane.size = Vector2(8.0, 8.0)
    _ground.mesh = plane
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.30, 0.31, 0.32, 1.0)
    material.roughness = 0.92
    _ground.material_override = material
    _world.add_child(_ground)

    _camera = Camera3D.new()
    _camera.name = "WitnessCamera"
    _camera.fov = 58.0
    _camera.current = true
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

    for mesh: MeshInstance3D in _find_meshes(_source_instance):
        mesh.visible = false
    _target_meshes = _find_meshes(_target_instance)
    if _target_meshes.is_empty():
        _failures.append("target_meshes_missing")

    for role: String in ROLE_ORDER:
        var pair: Array = ROLE_PAIRS[role]
        if _source_skeleton.find_bone(String(pair[0])) < 0:
            _failures.append("source_bone_missing role=%s bone=%s" % [role, String(pair[0])])
        if _target_skeleton.find_bone(String(pair[1])) < 0:
            _failures.append("target_bone_missing role=%s bone=%s" % [role, String(pair[1])])
    return _failures.is_empty()

func _snapshot_target_names() -> Dictionary:
    var snapshot := {}
    for role: String in ROLE_ORDER:
        var target_name := String((ROLE_PAIRS[role] as Array)[1])
        var idx := _target_skeleton.find_bone(target_name)
        snapshot[role] = {"index": idx, "name": _target_skeleton.get_bone_name(idx)}
    return snapshot

func _verify_target_names_unchanged(snapshot: Dictionary) -> void:
    for role: String in ROLE_ORDER:
        var row: Dictionary = snapshot[role]
        var idx := int(row["index"])
        if idx < 0 or idx >= _target_skeleton.get_bone_count():
            _target_names_unchanged = false
            return
        if _target_skeleton.get_bone_name(idx) != StringName(row["name"]):
            _target_names_unchanged = false
            return

func _remap_source_animation_tracks_to_target_names() -> int:
    var count := 0
    for raw_animation_name: StringName in _source_player.get_animation_list():
        var animation := _source_player.get_animation(raw_animation_name)
        if animation == null:
            continue
        for track_idx: int in range(animation.get_track_count()):
            var before := String(animation.track_get_path(track_idx))
            var after := before
            for role: String in ROLE_ORDER:
                var pair: Array = ROLE_PAIRS[role]
                after = after.replace(":%s" % String(pair[0]), ":%s" % String(pair[1]))
            if after != before:
                animation.track_set_path(track_idx, NodePath(after))
                count += 1
    return count

func _rename_source_bones_to_target_names() -> int:
    var renamed := 0
    for role: String in ROLE_ORDER:
        var pair: Array = ROLE_PAIRS[role]
        var source_name := String(pair[0])
        var target_name := String(pair[1])
        if _source_skeleton.find_bone(target_name) >= 0:
            _failures.append("source_target_name_collision role=%s name=%s" % [role, target_name])
            continue
        var idx := _source_skeleton.find_bone(source_name)
        if idx < 0:
            _failures.append("source_bone_missing_before_rename role=%s bone=%s" % [role, source_name])
            continue
        _source_skeleton.set_bone_name(idx, target_name)
        if _source_skeleton.get_bone_name(idx) != StringName(target_name):
            _failures.append("source_bone_rename_failed role=%s" % role)
            continue
        renamed += 1
    return renamed

func _measure_source_animation_motion() -> Dictionary:
    var motion := {}
    for clip: String in CLIPS:
        var animation_name := _resolve_animation_name(_source_player, clip)
        if animation_name.is_empty():
            motion[clip] = 0.0
            continue
        var animation := _source_player.get_animation(animation_name)
        if animation == null or animation.length <= 0.0:
            motion[clip] = 0.0
            continue
        _source_player.play(animation_name)
        _source_player.seek(minf(animation.length * 0.12, animation.length - 0.0001), true)
        _source_player.advance(0.0)
        _source_skeleton.force_update_all_bone_transforms()
        var a := _source_bone_position("left_foot")
        _source_player.seek(minf(animation.length * 0.48, animation.length - 0.0001), true)
        _source_player.advance(0.0)
        _source_skeleton.force_update_all_bone_transforms()
        var b := _source_bone_position("left_foot")
        motion[clip] = a.distance_to(b)
        _source_player.stop()
    return motion

func _setup_native_modifier() -> bool:
    var profile := _build_profile()
    if profile == null or profile.get_bone_size() != ROLE_ORDER.size():
        _failures.append("native_profile_invalid")
        return false

    _modifier = RetargetModifier3D.new()
    _modifier.name = "Gate8NativeRetargetModifier"
    _modifier.set_use_global_pose(false)
    _modifier.set_position_enabled(false)
    _modifier.set_rotation_enabled(true)
    _modifier.set_scale_enabled(false)
    _source_skeleton.add_child(_modifier)

    _target_skeleton.reparent(_modifier, true)
    _modifier.set_profile(profile)
    await process_frame

    if _target_skeleton.get_parent() != _modifier:
        _failures.append("target_skeleton_not_direct_modifier_child")
    if _modifier.is_using_global_pose():
        _failures.append("native_modifier_global_pose_enabled")
    if _modifier.is_position_enabled():
        _failures.append("native_modifier_position_enabled")
    if not _modifier.is_rotation_enabled():
        _failures.append("native_modifier_rotation_disabled")
    if _modifier.is_scale_enabled():
        _failures.append("native_modifier_scale_enabled")

    _resolved_target_mesh_bindings = 0
    for mesh: MeshInstance3D in _target_meshes:
        mesh.skeleton = mesh.get_path_to(_target_skeleton)
        if mesh.get_node_or_null(mesh.skeleton) == _target_skeleton:
            _resolved_target_mesh_bindings += 1
    if _resolved_target_mesh_bindings != _target_meshes.size():
        _failures.append("target_mesh_binding_resolution=%d expected=%d" % [_resolved_target_mesh_bindings, _target_meshes.size()])

    var common := 0
    for role: String in ROLE_ORDER:
        var target_name := String((ROLE_PAIRS[role] as Array)[1])
        if _source_skeleton.find_bone(target_name) >= 0 and _target_skeleton.find_bone(target_name) >= 0:
            common += 1
    if common != ROLE_ORDER.size():
        _failures.append("native_common_bone_names=%d expected=%d" % [common, ROLE_ORDER.size()])
    return _failures.is_empty()

func _build_profile() -> SkeletonProfile:
    var profile := SkeletonProfile.new()
    profile.set_bone_size(ROLE_ORDER.size())
    for idx: int in range(ROLE_ORDER.size()):
        var role := ROLE_ORDER[idx]
        var target_name := String((ROLE_PAIRS[role] as Array)[1])
        profile.set_bone_name(idx, target_name)
        var parent_role := String(PARENT_ROLE.get(role, ""))
        if not parent_role.is_empty():
            profile.set_bone_parent(idx, String((ROLE_PAIRS[parent_role] as Array)[1]))
        profile.set_required(idx, true)
    profile.set_root_bone(String((ROLE_PAIRS["hips"] as Array)[1]))
    profile.set_scale_base_bone(String((ROLE_PAIRS["hips"] as Array)[1]))
    return profile

func _measure_clip(clip_token: String) -> Dictionary:
    var animation_name := _resolve_animation_name(_source_player, clip_token)
    if animation_name.is_empty():
        _failures.append("clip_missing=%s" % clip_token)
        return {}
    var animation := _source_player.get_animation(animation_name)
    if animation == null or animation.length <= 0.0:
        _failures.append("clip_invalid=%s" % clip_token)
        return {}

    _reset_target_pose()
    var sample_count := maxi(MINIMUM_SAMPLES, int(ceil(animation.length * SAMPLE_RATE_HZ)))
    var dt := animation.length / float(sample_count)
    var left_positions: Array[Vector3] = []
    var right_positions: Array[Vector3] = []
    var torso_deltas: Array[float] = []
    var corrections: Array[float] = []

    for sample_index: int in range(sample_count):
        var time_s := minf(animation.length - 0.00001, float(sample_index) * dt)
        await _sample_native_pose(animation_name, time_s)
        var left := _target_bone_position("left_foot")
        var right := _target_bone_position("right_foot")
        left_positions.append(left)
        right_positions.append(right)
        corrections.append(GROUND_CLEARANCE_M - minf(left.y, right.y))
        torso_deltas.append(absf(_torso_bend(_source_skeleton) - _torso_bend(_target_skeleton)))

    if left_positions.size() < MINIMUM_SAMPLES:
        _failures.append("insufficient_samples clip=%s samples=%d" % [clip_token, left_positions.size()])
        return {}

    var raw_ground_y := INF
    for idx: int in range(left_positions.size()):
        raw_ground_y = minf(raw_ground_y, minf(left_positions[idx].y, right_positions[idx].y))
    var contact_limit := raw_ground_y + CONTACT_HEIGHT_WINDOW_M
    var left_slide := _contact_slide_metrics(left_positions, contact_limit, dt)
    var right_slide := _contact_slide_metrics(right_positions, contact_limit, dt)
    var contacts := int(left_slide.get("samples", 0)) + int(right_slide.get("samples", 0))
    if contacts <= 0:
        _failures.append("no_contact_samples clip=%s" % clip_token)

    var correction_min := _array_min(corrections)
    var correction_max := _array_max(corrections)
    var correction_span := correction_max - correction_min
    var correction_step := _max_adjacent_delta(corrections)
    var torso_mean := _array_mean(torso_deltas)
    var torso_peak := _array_max(torso_deltas)

    _gate_metric(clip_token, "ground_correction_span", correction_span, MAX_GROUND_CORRECTION_SPAN_M)
    _gate_metric(clip_token, "ground_correction_step", correction_step, MAX_GROUND_CORRECTION_STEP_M)
    _gate_metric(clip_token, "torso_mean_delta", torso_mean, MAX_MEAN_TORSO_DELTA_DEG)
    _gate_metric(clip_token, "torso_peak_delta", torso_peak, MAX_PEAK_TORSO_DELTA_DEG)

    var frame_path := await _capture_clip_frame(clip_token, animation_name, animation.length * 0.35)
    var mean_slide := (float(left_slide.get("mean_mps", 0.0)) + float(right_slide.get("mean_mps", 0.0))) * 0.5
    var peak_slide := maxf(float(left_slide.get("max_mps", 0.0)), float(right_slide.get("max_mps", 0.0)))
    if not is_finite(mean_slide) or not is_finite(peak_slide):
        _failures.append("non_finite_slide_metric clip=%s" % clip_token)

    print("GATE8_NATIVE_RETARGET_CLIP clip=%s samples=%d contacts=%d mean_slide_mps=%.4f peak_slide_mps=%.4f ground_span_m=%.4f ground_step_m=%.4f torso_mean_deg=%.3f torso_peak_deg=%.3f" % [
        clip_token, sample_count, contacts, mean_slide, peak_slide, correction_span, correction_step, torso_mean, torso_peak
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
        "ground_correction_max_step_m": correction_step,
        "left_contact_samples": int(left_slide.get("samples", 0)),
        "right_contact_samples": int(right_slide.get("samples", 0)),
        "mean_contact_slide_mps": mean_slide,
        "peak_contact_slide_mps": peak_slide,
        "mean_torso_bend_delta_deg": torso_mean,
        "peak_torso_bend_delta_deg": torso_peak,
        "frame_path": frame_path,
        "frame_width": 1280,
        "frame_height": 720
    }

func _sample_native_pose(animation_name: String, time_s: float) -> void:
    _source_player.play(animation_name)
    _source_player.pause()
    _source_player.seek(time_s, true)
    _source_player.advance(0.0)
    _source_skeleton.force_update_all_bone_transforms()
    await process_frame
    _source_skeleton.force_update_all_bone_transforms()
    _target_skeleton.force_update_all_bone_transforms()

func _capture_clip_frame(clip_token: String, animation_name: String, sample_time: float) -> String:
    await _sample_native_pose(animation_name, sample_time)
    var left_model := _target_bone_position("left_foot")
    var right_model := _target_bone_position("right_foot")
    var ground_model_y := minf(left_model.y, right_model.y) - GROUND_CLEARANCE_M
    var ground_world := _target_skeleton.to_global(Vector3(0.0, ground_model_y, 0.0))
    _ground.global_position.y = ground_world.y

    var pelvis_world := _target_skeleton.to_global(_target_bone_position("hips"))
    var head_world := _target_skeleton.to_global(_target_bone_position("head"))
    var center := (pelvis_world + head_world) * 0.5
    _camera.look_at_from_position(center + Vector3(2.9, 0.45, 4.15), center, Vector3.UP)

    await process_frame
    await process_frame
    RenderingServer.force_draw(false)
    await process_frame
    var image := root.get_texture().get_image()
    var normalized := clip_token.to_lower().replace("_", "-")
    var path := "res://gate8_variant01_native_%s.png" % normalized
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
    return path

func _reset_target_pose() -> void:
    for idx: int in range(_target_skeleton.get_bone_count()):
        _target_skeleton.reset_bone_pose(idx)
    _target_skeleton.force_update_all_bone_transforms()

func _source_bone_position(role: String) -> Vector3:
    var name := String((ROLE_PAIRS[role] as Array)[1])
    var idx := _source_skeleton.find_bone(name)
    return Vector3.ZERO if idx < 0 else _source_skeleton.get_bone_global_pose(idx).origin

func _target_bone_position(role: String) -> Vector3:
    var name := String((ROLE_PAIRS[role] as Array)[1])
    var idx := _target_skeleton.find_bone(name)
    return Vector3.ZERO if idx < 0 else _target_skeleton.get_bone_global_pose(idx).origin

func _torso_bend(skeleton: Skeleton3D) -> float:
    var spine_idx := skeleton.find_bone(String((ROLE_PAIRS["spine"] as Array)[1]))
    var chest_idx := skeleton.find_bone(String((ROLE_PAIRS["chest"] as Array)[1]))
    var neck_idx := skeleton.find_bone(String((ROLE_PAIRS["neck"] as Array)[1]))
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

func _find_meshes(node: Node) -> Array[MeshInstance3D]:
    var result: Array[MeshInstance3D] = []
    if node is MeshInstance3D:
        result.append(node as MeshInstance3D)
    for child: Node in node.get_children():
        result.append_array(_find_meshes(child))
    return result

func _resolve_animation_name(player: AnimationPlayer, token: String) -> String:
    for raw_name: StringName in player.get_animation_list():
        var name := String(raw_name)
        if name == token or name.ends_with("/%s" % token):
            return name
    return ""

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
    var file := FileAccess.open("res://gate8_variant01_native_retarget_ab_result.json", FileAccess.WRITE)
    if file == null:
        _failures.append("result_file_open_failed")
        return
    file.store_string(JSON.stringify(result, "  "))
    file.close()

func _finish(_result: Dictionary) -> void:
    if _failures.is_empty():
        print("GATE8_NATIVE_RETARGET_AB_OK candidate=01 clips=Jog_Fwd,Sprint alias_selected=false production_authorized=false")
        quit(0)
        return
    for failure: String in _failures:
        push_error("GATE8_NATIVE_RETARGET_AB_FAIL %s" % failure)
    quit(1)
