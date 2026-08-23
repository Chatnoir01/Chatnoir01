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
var _proxy_skeleton: Skeleton3D
var _source_player: AnimationPlayer
var _modifier: RetargetModifier3D
var _camera: Camera3D
var _ground: MeshInstance3D
var _target_meshes: Array[MeshInstance3D] = []
var _source_tracks_remapped := 0
var _source_bones_renamed := 0
var _target_names_unchanged := true
var _resolved_target_mesh_bindings := 0
var _proxy_bones := 0

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    if ROLE_ORDER.size() != 22 or ROLE_PAIRS.size() != 22:
        _failures.append("reviewed_role_count_changed")
        _finish()
        return

    root.size = Vector2i(1280, 720)
    _build_world()
    if not await _load_characters():
        _finish()
        return

    var target_snapshot := _snapshot_target_names()
    _source_tracks_remapped = _remap_source_animation_tracks()
    _source_bones_renamed = _rename_source_bones()
    _verify_target_names(target_snapshot)

    if _source_tracks_remapped <= 0:
        _failures.append("source_animation_tracks_not_remapped")
    if _source_bones_renamed != ROLE_ORDER.size():
        _failures.append("source_bone_rename_count=%d expected=%d" % [_source_bones_renamed, ROLE_ORDER.size()])
    if not _target_names_unchanged:
        _failures.append("target_bone_names_changed")
    if not _failures.is_empty():
        _finish()
        return

    _source_player.stop()
    if _source_player.has_method("clear_caches"):
        _source_player.call("clear_caches")

    var source_motion := _measure_source_motion()
    for clip: String in CLIPS:
        var movement := float(source_motion.get(clip, 0.0))
        if movement < MIN_SOURCE_ANIMATION_MOTION_M:
            _failures.append("source_animation_lost_after_runtime_remap clip=%s motion=%.5f" % [clip, movement])

    if not await _setup_native_modifier_proxy():
        _finish()
        return

    var results: Dictionary = {}
    for clip: String in CLIPS:
        results[clip] = await _measure_clip(clip)

    var result := {
        "format": "grand-bruxelles-gate8-variant01-native-retarget-ab-result-v1",
        "engine_version": Engine.get_version_info().get("string", "unknown"),
        "candidate_variant": 1,
        "retarget_method": "RetargetModifier3D_source_canonicalized_to_target_native_names",
        "reviewed_roles": ROLE_ORDER.size(),
        "source_bones_renamed": _source_bones_renamed,
        "source_animation_tracks_remapped": _source_tracks_remapped,
        "target_bone_names_unchanged": _target_names_unchanged,
        "resolved_target_mesh_bindings": _resolved_target_mesh_bindings,
        "proxy_bone_count": _proxy_bones,
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
    print("GATE8_NATIVE_RETARGET_AB candidate=01 clips=2 failures=%d source_renamed=%d target_names_unchanged=%s bindings=%d proxy_bones=%d alias_selected=false production_authorized=false" % [
        _failures.size(), _source_bones_renamed, str(_target_names_unchanged), _resolved_target_mesh_bindings, _proxy_bones
    ])
    _finish()

func _build_world() -> void:
    _world = Node3D.new()
    _world.name = "Gate8NativeRetargetABWorld"
    root.add_child(_world)

    var world_environment := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.16, 0.18, 0.21, 1.0)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.78, 0.80, 0.84, 1.0)
    environment.ambient_light_energy = 1.05
    world_environment.environment = environment
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
    _source_player = _find_animation_player(_source_instance)
    if _source_skeleton == null:
        _failures.append("source_skeleton_missing")
    if _target_skeleton == null:
        _failures.append("target_skeleton_missing")
    if _source_player == null:
        _failures.append("source_animation_player_missing_required_clips")
    if not _failures.is_empty():
        return false

    # The source mesh is irrelevant to the witness. Remove it before source bone
    # renames so its named Skin binds can never become stale or pollute the logs.
    for source_mesh: MeshInstance3D in _find_meshes(_source_instance):
        source_mesh.queue_free()
    await process_frame

    _target_meshes = _find_meshes(_target_instance)
    if _target_meshes.is_empty():
        _failures.append("target_meshes_missing")

    for role: String in ROLE_ORDER:
        var pair: Array = ROLE_PAIRS[role]
        if _source_skeleton.find_bone(String(pair[0])) < 0:
            _failures.append("source_bone_missing role=%s" % role)
        if _target_skeleton.find_bone(String(pair[1])) < 0:
            _failures.append("target_bone_missing role=%s" % role)

    _resolved_target_mesh_bindings = 0
    for target_mesh: MeshInstance3D in _target_meshes:
        if target_mesh.get_node_or_null(target_mesh.skeleton) == _target_skeleton:
            _resolved_target_mesh_bindings += 1
    if _resolved_target_mesh_bindings != _target_meshes.size():
        _failures.append("original_target_mesh_binding_resolution=%d expected=%d" % [_resolved_target_mesh_bindings, _target_meshes.size()])

    return _failures.is_empty()

func _snapshot_target_names() -> Dictionary:
    var snapshot: Dictionary = {}
    for role: String in ROLE_ORDER:
        var target_name := String((ROLE_PAIRS[role] as Array)[1])
        var target_idx := _target_skeleton.find_bone(target_name)
        snapshot[role] = {
            "index": target_idx,
            "name": _target_skeleton.get_bone_name(target_idx)
        }
    return snapshot

func _verify_target_names(snapshot: Dictionary) -> void:
    for role: String in ROLE_ORDER:
        var row: Dictionary = snapshot[role]
        var target_idx := int(row["index"])
        if target_idx < 0 or target_idx >= _target_skeleton.get_bone_count():
            _target_names_unchanged = false
            return
        if _target_skeleton.get_bone_name(target_idx) != StringName(row["name"]):
            _target_names_unchanged = false
            return

func _remap_source_animation_tracks() -> int:
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

func _rename_source_bones() -> int:
    var count := 0
    for role: String in ROLE_ORDER:
        var pair: Array = ROLE_PAIRS[role]
        var source_name := String(pair[0])
        var target_name := String(pair[1])
        if _source_skeleton.find_bone(target_name) >= 0:
            _failures.append("source_target_name_collision role=%s name=%s" % [role, target_name])
            continue
        var source_idx := _source_skeleton.find_bone(source_name)
        if source_idx < 0:
            _failures.append("source_bone_missing_before_rename role=%s" % role)
            continue
        _source_skeleton.set_bone_name(source_idx, target_name)
        if _source_skeleton.get_bone_name(source_idx) == StringName(target_name):
            count += 1
    return count

func _measure_source_motion() -> Dictionary:
    var motion: Dictionary = {}
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
        _source_player.seek(animation.length * 0.12, true)
        _source_player.advance(0.0)
        _source_skeleton.force_update_all_bone_transforms()
        var first := _source_bone_position("left_foot")

        _source_player.seek(animation.length * 0.48, true)
        _source_player.advance(0.0)
        _source_skeleton.force_update_all_bone_transforms()
        var second := _source_bone_position("left_foot")

        motion[clip] = first.distance_to(second)
        _source_player.stop()
    return motion

func _setup_native_modifier_proxy() -> bool:
    _modifier = RetargetModifier3D.new()
    _modifier.name = "Gate8NativeRetargetModifier"
    _modifier.set_use_global_pose(false)
    _modifier.set_position_enabled(false)
    _modifier.set_rotation_enabled(true)
    _modifier.set_scale_enabled(false)
    _source_skeleton.add_child(_modifier)

    _proxy_skeleton = _clone_target_skeleton()
    _modifier.add_child(_proxy_skeleton)
    _modifier.set_profile(_build_profile())
    await process_frame

    _proxy_bones = _proxy_skeleton.get_bone_count()
    if _proxy_bones != _target_skeleton.get_bone_count():
        _failures.append("proxy_bone_count=%d target=%d" % [_proxy_bones, _target_skeleton.get_bone_count()])
    if _proxy_skeleton.get_parent() != _modifier:
        _failures.append("proxy_not_modifier_child")
    if _target_skeleton.get_parent() == _modifier:
        _failures.append("real_target_reparented_forbidden")

    for role: String in ROLE_ORDER:
        var target_name := String((ROLE_PAIRS[role] as Array)[1])
        if _source_skeleton.find_bone(target_name) < 0:
            _failures.append("native_source_common_bone_missing role=%s" % role)
        if _proxy_skeleton.find_bone(target_name) < 0:
            _failures.append("native_proxy_common_bone_missing role=%s" % role)
        if _target_skeleton.find_bone(target_name) < 0:
            _failures.append("native_target_common_bone_missing role=%s" % role)

    return _failures.is_empty()

func _clone_target_skeleton() -> Skeleton3D:
    var proxy := Skeleton3D.new()
    proxy.name = "Gate8TargetRetargetProxy"
    proxy.set_motion_scale(_target_skeleton.get_motion_scale())

    for bone_idx: int in range(_target_skeleton.get_bone_count()):
        proxy.add_bone(String(_target_skeleton.get_bone_name(bone_idx)))

    for bone_idx: int in range(_target_skeleton.get_bone_count()):
        proxy.set_bone_parent(bone_idx, _target_skeleton.get_bone_parent(bone_idx))
        proxy.set_bone_rest(bone_idx, _target_skeleton.get_bone_rest(bone_idx))
        proxy.set_bone_enabled(bone_idx, _target_skeleton.is_bone_enabled(bone_idx))

    return proxy

func _build_profile() -> SkeletonProfile:
    var profile := SkeletonProfile.new()
    profile.set_bone_size(ROLE_ORDER.size())
    for role_idx: int in range(ROLE_ORDER.size()):
        var role := ROLE_ORDER[role_idx]
        var target_name := String((ROLE_PAIRS[role] as Array)[1])
        profile.set_bone_name(role_idx, target_name)
        var parent_role := String(PARENT_ROLE.get(role, ""))
        if not parent_role.is_empty():
            profile.set_bone_parent(role_idx, String((ROLE_PAIRS[parent_role] as Array)[1]))
        profile.set_required(role_idx, true)
    profile.set_root_bone("pelvis")
    profile.set_scale_base_bone("pelvis")
    return profile

func _measure_clip(clip: String) -> Dictionary:
    var animation_name := _resolve_animation_name(_source_player, clip)
    if animation_name.is_empty():
        _failures.append("clip_missing=%s" % clip)
        return {}
    var animation := _source_player.get_animation(animation_name)
    if animation == null or animation.length <= 0.0:
        _failures.append("clip_invalid=%s" % clip)
        return {}

    _reset_poses()
    var sample_count := maxi(MINIMUM_SAMPLES, int(ceil(animation.length * SAMPLE_RATE_HZ)))
    var dt := animation.length / float(sample_count)
    var left_positions: Array[Vector3] = []
    var right_positions: Array[Vector3] = []
    var corrections: Array[float] = []
    var torso_deltas: Array[float] = []

    for sample_idx: int in range(sample_count):
        var time_s := minf(animation.length - 0.00001, float(sample_idx) * dt)
        await _sample_native_pose(animation_name, time_s)
        var left := _target_bone_position("left_foot")
        var right := _target_bone_position("right_foot")
        left_positions.append(left)
        right_positions.append(right)
        corrections.append(GROUND_CLEARANCE_M - minf(left.y, right.y))
        torso_deltas.append(absf(_torso_bend(_source_skeleton) - _torso_bend(_target_skeleton)))

    var raw_ground_y := INF
    for sample_idx: int in range(left_positions.size()):
        raw_ground_y = minf(raw_ground_y, minf(left_positions[sample_idx].y, right_positions[sample_idx].y))

    var contact_limit := raw_ground_y + CONTACT_HEIGHT_WINDOW_M
    var left_slide := _contact_slide(left_positions, contact_limit, dt)
    var right_slide := _contact_slide(right_positions, contact_limit, dt)
    var contacts := int(left_slide.get("samples", 0)) + int(right_slide.get("samples", 0))
    if contacts <= 0:
        _failures.append("no_contact_samples clip=%s" % clip)

    var correction_min := _array_min(corrections)
    var correction_max := _array_max(corrections)
    var correction_span := correction_max - correction_min
    var correction_step := _max_adjacent_delta(corrections)
    var torso_mean := _array_mean(torso_deltas)
    var torso_peak := _array_max(torso_deltas)

    _gate(clip, "ground_correction_span", correction_span, MAX_GROUND_CORRECTION_SPAN_M)
    _gate(clip, "ground_correction_step", correction_step, MAX_GROUND_CORRECTION_STEP_M)
    _gate(clip, "torso_mean_delta", torso_mean, MAX_MEAN_TORSO_DELTA_DEG)
    _gate(clip, "torso_peak_delta", torso_peak, MAX_PEAK_TORSO_DELTA_DEG)

    var frame_path := await _capture(clip, animation_name, animation.length * 0.35)
    var mean_slide := (float(left_slide.get("mean_mps", 0.0)) + float(right_slide.get("mean_mps", 0.0))) * 0.5
    var peak_slide := maxf(float(left_slide.get("max_mps", 0.0)), float(right_slide.get("max_mps", 0.0)))

    print("GATE8_NATIVE_RETARGET_CLIP clip=%s samples=%d contacts=%d mean_slide_mps=%.4f peak_slide_mps=%.4f ground_span_m=%.4f ground_step_m=%.4f torso_mean_deg=%.3f torso_peak_deg=%.3f" % [
        clip, sample_count, contacts, mean_slide, peak_slide, correction_span, correction_step, torso_mean, torso_peak
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
    _proxy_skeleton.force_update_all_bone_transforms()
    _copy_proxy_rotations_to_target()
    _target_skeleton.force_update_all_bone_transforms()

func _copy_proxy_rotations_to_target() -> void:
    for role: String in ROLE_ORDER:
        var target_name := String((ROLE_PAIRS[role] as Array)[1])
        var proxy_idx := _proxy_skeleton.find_bone(target_name)
        var target_idx := _target_skeleton.find_bone(target_name)
        if proxy_idx < 0 or target_idx < 0:
            _failures.append("proxy_copy_bone_missing role=%s" % role)
            continue
        _target_skeleton.set_bone_pose_rotation(target_idx, _proxy_skeleton.get_bone_pose_rotation(proxy_idx))

func _reset_poses() -> void:
    for bone_idx: int in range(_proxy_skeleton.get_bone_count()):
        _proxy_skeleton.reset_bone_pose(bone_idx)
    for bone_idx: int in range(_target_skeleton.get_bone_count()):
        _target_skeleton.reset_bone_pose(bone_idx)
    _proxy_skeleton.force_update_all_bone_transforms()
    _target_skeleton.force_update_all_bone_transforms()

func _capture(clip: String, animation_name: String, sample_time: float) -> String:
    await _sample_native_pose(animation_name, sample_time)

    var foot_y := minf(_target_bone_position("left_foot").y, _target_bone_position("right_foot").y)
    var ground_world := _target_skeleton.to_global(Vector3(0.0, foot_y - GROUND_CLEARANCE_M, 0.0))
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
    if image == null or image.is_empty():
        _failures.append("capture_empty clip=%s" % clip)
        return ""
    if image.get_width() != 1280 or image.get_height() != 720:
        _failures.append("capture_size clip=%s got=%dx%d" % [clip, image.get_width(), image.get_height()])
        return ""

    var path := "res://gate8_variant01_native_%s.png" % clip.to_lower().replace("_", "-")
    if image.save_png(path) != OK:
        _failures.append("capture_save_failed clip=%s" % clip)
        return ""
    return path

func _source_bone_position(role: String) -> Vector3:
    var bone_name := String((ROLE_PAIRS[role] as Array)[1])
    var bone_idx := _source_skeleton.find_bone(bone_name)
    if bone_idx < 0:
        return Vector3.ZERO
    return _source_skeleton.get_bone_global_pose(bone_idx).origin

func _target_bone_position(role: String) -> Vector3:
    var bone_name := String((ROLE_PAIRS[role] as Array)[1])
    var bone_idx := _target_skeleton.find_bone(bone_name)
    if bone_idx < 0:
        return Vector3.ZERO
    return _target_skeleton.get_bone_global_pose(bone_idx).origin

func _torso_bend(skeleton: Skeleton3D) -> float:
    var spine_idx := skeleton.find_bone("spine_01")
    var chest_idx := skeleton.find_bone("spine_02")
    var neck_idx := skeleton.find_bone("neck_01")
    if spine_idx < 0 or chest_idx < 0 or neck_idx < 0:
        return 180.0

    var lower := skeleton.get_bone_global_pose(chest_idx).origin - skeleton.get_bone_global_pose(spine_idx).origin
    var upper := skeleton.get_bone_global_pose(neck_idx).origin - skeleton.get_bone_global_pose(chest_idx).origin
    if lower.length_squared() <= 0.000001 or upper.length_squared() <= 0.000001:
        return 180.0
    return rad_to_deg(lower.normalized().angle_to(upper.normalized()))

func _contact_slide(positions: Array[Vector3], contact_limit: float, dt: float) -> Dictionary:
    var speeds: Array[float] = []
    for sample_idx: int in range(1, positions.size()):
        var previous := positions[sample_idx - 1]
        var current := positions[sample_idx]
        if previous.y > contact_limit or current.y > contact_limit:
            continue
        var planar_distance := Vector2(current.x - previous.x, current.z - previous.z).length()
        speeds.append(planar_distance / maxf(dt, 0.000001))
    return {
        "samples": speeds.size(),
        "mean_mps": _array_mean(speeds),
        "max_mps": _array_max(speeds)
    }

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D
    for child: Node in node.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null

func _find_animation_player(node: Node) -> AnimationPlayer:
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
        var found := _find_animation_player(child)
        if found != null:
            return found
    return null

func _find_meshes(node: Node) -> Array[MeshInstance3D]:
    var meshes: Array[MeshInstance3D] = []
    if node is MeshInstance3D:
        meshes.append(node as MeshInstance3D)
    for child: Node in node.get_children():
        meshes.append_array(_find_meshes(child))
    return meshes

func _resolve_animation_name(player: AnimationPlayer, token: String) -> String:
    for raw_name: StringName in player.get_animation_list():
        var animation_name := String(raw_name)
        if animation_name == token or animation_name.ends_with("/%s" % token):
            return animation_name
    return ""

func _gate(clip: String, key: String, value: float, limit: float) -> void:
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
    var minimum := INF
    for value: float in values:
        minimum = minf(minimum, value)
    return minimum

func _array_max(values: Array[float]) -> float:
    if values.is_empty():
        return 0.0
    var maximum := -INF
    for value: float in values:
        maximum = maxf(maximum, value)
    return maximum

func _max_adjacent_delta(values: Array[float]) -> float:
    var maximum := 0.0
    for value_idx: int in range(1, values.size()):
        maximum = maxf(maximum, absf(values[value_idx] - values[value_idx - 1]))
    return maximum

func _write_result(result: Dictionary) -> void:
    var file := FileAccess.open("res://gate8_variant01_native_retarget_ab_result.json", FileAccess.WRITE)
    if file == null:
        _failures.append("result_file_open_failed")
        return
    file.store_string(JSON.stringify(result, "  "))
    file.close()

func _finish() -> void:
    if _failures.is_empty():
        print("GATE8_NATIVE_RETARGET_AB_OK candidate=01 clips=Jog_Fwd,Sprint alias_selected=false production_authorized=false")
        quit(0)
        return
    for failure: String in _failures:
        push_error("GATE8_NATIVE_RETARGET_AB_FAIL %s" % failure)
    quit(1)
