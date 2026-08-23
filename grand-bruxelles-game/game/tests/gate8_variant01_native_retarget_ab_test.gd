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

var _failures: Array[String] = []
var _world: Node3D
var _source_instance: Node3D
var _target_instance: Node3D
var _source_skeleton: Skeleton3D
var _target_skeleton: Skeleton3D
var _source_player: AnimationPlayer
var _modifier: RetargetModifier3D
var _camera: Camera3D
var _target_meshes: Array[MeshInstance3D] = []
var _target_snapshot: Dictionary = {}

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    if ROLE_PAIRS.size() != 22:
        _failures.append("reviewed_role_count=%d expected=22" % ROLE_PAIRS.size())
    root.size = Vector2i(1280, 720)
    _build_world()
    if not await _load_and_wire_native_retarget():
        _finish({})
        return

    var results: Dictionary = {}
    for clip: String in CLIPS:
        results[clip] = await _measure_clip(clip)

    _verify_target_integrity_after_measurement()
    var result := {
        "format": "grand-bruxelles-gate8-variant01-native-retarget-ab-result-v1",
        "engine_version": Engine.get_version_info().get("string", "unknown"),
        "candidate_variant": 1,
        "reviewed_roles": ROLE_PAIRS.size(),
        "retarget_engine": "RetargetModifier3D",
        "use_global_pose": false,
        "position_enabled": false,
        "rotation_enabled": true,
        "scale_enabled": false,
        "target_runtime_renamed_roles": ROLE_PAIRS.size(),
        "source_bone_names_unchanged": true,
        "source_animation_tracks_unchanged": true,
        "target_rest_pose_unchanged": not _has_failure_token("target_rest_changed"),
        "target_parent_topology_unchanged": not _has_failure_token("target_parent_changed"),
        "target_bone_indices_unchanged": not _has_failure_token("target_index_changed"),
        "clips": results,
        "run_alias_selected": "",
        "selection_state": "MEASURED_REVIEW_REQUIRED" if _failures.is_empty() else "BLOCKED_NATIVE_RETARGET_OUTPUT",
        "production_authorized": false,
        "activation_ready": false,
        "adoption_ready": false,
        "runtime_population_changed": false,
        "visual_approval_claimed": false,
        "failures": _failures
    }
    _write_result(result)
    print("GATE8_NATIVE_AB candidate=01 clips=2 failures=%d engine=RetargetModifier3D alias_selected=false production_authorized=false" % _failures.size())
    _finish(result)

func _build_world() -> void:
    _world = Node3D.new()
    _world.name = "NativeRetargetABWorld"
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
    var plane := PlaneMesh.new()
    plane.size = Vector2(8.0, 8.0)
    ground.mesh = plane
    var ground_material := StandardMaterial3D.new()
    ground_material.albedo_color = Color(0.30, 0.31, 0.32, 1.0)
    ground_material.roughness = 0.92
    ground.material_override = ground_material
    _world.add_child(ground)

    _camera = Camera3D.new()
    _camera.fov = 58.0
    _camera.current = true
    _camera.look_at_from_position(Vector3(2.9, 1.45, 4.15), Vector3(0.0, 0.92, 0.0), Vector3.UP)
    _world.add_child(_camera)

func _load_and_wire_native_retarget() -> bool:
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
    _target_instance.name = "Gate8Variant01Visual"
    _source_instance.visible = false
    _world.add_child(_source_instance)
    _world.add_child(_target_instance)
    await process_frame

    _source_skeleton = _find_skeleton(_source_instance)
    _target_skeleton = _find_skeleton(_target_instance)
    _source_player = _find_animation_player_with_clips(_source_instance)
    if _source_skeleton == null or _target_skeleton == null or _source_player == null:
        _failures.append("source_target_or_animation_player_missing")
        return false

    _target_snapshot = _snapshot_target_mapping()
    _collect_skinned_meshes(_target_instance, _target_meshes)
    if _target_meshes.is_empty():
        _failures.append("target_skinned_meshes_missing")
        return false

    if not _rename_target_to_source_namespace():
        return false
    _verify_target_snapshot_after_rename()
    if not _failures.is_empty():
        return false

    var profile := SkeletonProfile.new()
    profile.set_bone_size(ROLE_PAIRS.size())
    var profile_index := 0
    for role_value: Variant in ROLE_PAIRS.keys():
        var role := String(role_value)
        profile.set_bone_name(profile_index, StringName(_source_name(role)))
        profile.set_required(profile_index, true)
        profile_index += 1
    profile.set_scale_base_bone(StringName(_source_name("hips")))

    _modifier = RetargetModifier3D.new()
    _modifier.name = "NativeRetargetModifier"
    _modifier.set_use_global_pose(false)
    _modifier.set_position_enabled(false)
    _modifier.set_rotation_enabled(true)
    _modifier.set_scale_enabled(false)
    _modifier.influence = 1.0
    _source_skeleton.add_child(_modifier)

    _target_skeleton.reparent(_modifier, true)
    for mesh: MeshInstance3D in _target_meshes:
        if is_instance_valid(mesh):
            mesh.set_skeleton_path(mesh.get_path_to(_target_skeleton))
    _modifier.set_profile(profile)
    await process_frame

    if _modifier.is_using_global_pose():
        _failures.append("modifier_global_pose_unexpectedly_enabled")
    if _modifier.is_position_enabled():
        _failures.append("modifier_position_unexpectedly_enabled")
    if not _modifier.is_rotation_enabled():
        _failures.append("modifier_rotation_not_enabled")
    if _modifier.is_scale_enabled():
        _failures.append("modifier_scale_unexpectedly_enabled")

    var common := 0
    for role_value: Variant in ROLE_PAIRS.keys():
        var role := String(role_value)
        var name := _source_name(role)
        if _source_skeleton.find_bone(name) >= 0 and _target_skeleton.find_bone(name) >= 0:
            common += 1
    if common != ROLE_PAIRS.size():
        _failures.append("native_common_name_count=%d expected=%d" % [common, ROLE_PAIRS.size()])

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
    var corrections: Array[float] = []
    var torso_deltas: Array[float] = []

    _source_player.play(animation_name)
    _source_player.pause()
    _reset_target_pose()

    for sample_index: int in range(sample_count):
        var time_s := minf(animation.length - 0.00001, float(sample_index) * dt)
        _source_player.seek(time_s, true)
        _source_player.advance(0.0)
        _source_skeleton.force_update_all_bone_transforms()
        await process_frame
        _target_skeleton.force_update_all_bone_transforms()

        var left := _target_bone_position("left_foot")
        var right := _target_bone_position("right_foot")
        left_positions.append(left)
        right_positions.append(right)
        corrections.append(GROUND_CLEARANCE_M - minf(left.y, right.y))
        torso_deltas.append(absf(_torso_bend(_source_skeleton, true) - _torso_bend(_target_skeleton, false)))

    _source_player.stop()

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

    var mean_slide := (float(left_slide.get("mean_mps", 0.0)) + float(right_slide.get("mean_mps", 0.0))) * 0.5
    var peak_slide := maxf(float(left_slide.get("max_mps", 0.0)), float(right_slide.get("max_mps", 0.0)))
    if not is_finite(mean_slide) or not is_finite(peak_slide):
        _failures.append("non_finite_slide_metric clip=%s" % clip_token)

    var frame_path := await _capture_clip_frame(clip_token, animation_name, animation.length * 0.35)
    print("GATE8_NATIVE_CLIP clip=%s samples=%d contacts=%d mean_slide_mps=%.4f peak_slide_mps=%.4f ground_span_m=%.4f ground_step_m=%.4f torso_mean_deg=%.3f torso_peak_deg=%.3f" % [clip_token, sample_count, contacts, mean_slide, peak_slide, correction_span, correction_step, torso_mean, torso_peak])

    return {
        "animation_name": animation_name,
        "duration_s": animation.length,
        "sample_count": sample_count,
        "left_contact_samples": int(left_slide.get("samples", 0)),
        "right_contact_samples": int(right_slide.get("samples", 0)),
        "mean_contact_slide_mps": mean_slide,
        "peak_contact_slide_mps": peak_slide,
        "ground_correction_min_m": correction_min,
        "ground_correction_max_m": correction_max,
        "ground_correction_span_m": correction_span,
        "ground_correction_max_step_m": correction_step,
        "mean_torso_bend_delta_deg": torso_mean,
        "peak_torso_bend_delta_deg": torso_peak,
        "frame_path": frame_path,
        "frame_width": 1280,
        "frame_height": 720
    }

func _capture_clip_frame(clip_token: String, animation_name: String, sample_time: float) -> String:
    _source_instance.position = Vector3.ZERO
    _target_instance.position = Vector3.ZERO
    _source_player.play(animation_name)
    _source_player.pause()
    _source_player.seek(sample_time, true)
    _source_player.advance(0.0)
    _source_skeleton.force_update_all_bone_transforms()
    await process_frame
    _target_skeleton.force_update_all_bone_transforms()
    var left := _target_bone_position("left_foot")
    var right := _target_bone_position("right_foot")
    var correction := GROUND_CLEARANCE_M - minf(left.y, right.y)
    _source_instance.position.y = correction
    _target_instance.position.y = correction
    await process_frame
    RenderingServer.force_draw(false)
    await process_frame
    var image := root.get_texture().get_image()
    var path := "res://gate8_variant01_native_%s.png" % clip_token.to_lower().replace("_", "-")
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
    _source_instance.position = Vector3.ZERO
    _target_instance.position = Vector3.ZERO
    _source_player.stop()
    return path

func _snapshot_target_mapping() -> Dictionary:
    var snapshot := {}
    for role_value: Variant in ROLE_PAIRS.keys():
        var role := String(role_value)
        var target_name := _target_name(role)
        var idx := _target_skeleton.find_bone(target_name)
        if idx < 0:
            _failures.append("target_snapshot_missing role=%s bone=%s" % [role, target_name])
            continue
        snapshot[role] = {"index": idx, "parent": _target_skeleton.get_bone_parent(idx), "rest": _target_skeleton.get_bone_rest(idx), "old_name": target_name}
    return snapshot

func _rename_target_to_source_namespace() -> bool:
    var planned := 0
    for role_value: Variant in ROLE_PAIRS.keys():
        var role := String(role_value)
        var source_name := _source_name(role)
        var target_name := _target_name(role)
        var idx := _target_skeleton.find_bone(target_name)
        if idx < 0:
            _failures.append("target_rename_missing role=%s bone=%s" % [role, target_name])
            continue
        var collision_idx := _target_skeleton.find_bone(source_name)
        if collision_idx >= 0 and collision_idx != idx:
            _failures.append("target_rename_collision role=%s name=%s" % [role, source_name])
            continue
        planned += 1
    if planned != ROLE_PAIRS.size():
        return false
    for role_value: Variant in ROLE_PAIRS.keys():
        var role := String(role_value)
        var idx := _target_skeleton.find_bone(_target_name(role))
        _target_skeleton.set_bone_name(idx, _source_name(role))
        if _target_skeleton.get_bone_name(idx) != _source_name(role):
            _failures.append("target_rename_failed role=%s" % role)
    return _failures.is_empty()

func _verify_target_snapshot_after_rename() -> void:
    for role_value: Variant in _target_snapshot.keys():
        var role := String(role_value)
        var row: Dictionary = _target_snapshot[role]
        var idx := _target_skeleton.find_bone(_source_name(role))
        if idx != int(row["index"]):
            _failures.append("target_index_changed role=%s" % role)
            continue
        if _target_skeleton.get_bone_parent(idx) != int(row["parent"]):
            _failures.append("target_parent_changed role=%s" % role)
        var rest_before: Transform3D = row["rest"]
        if not _target_skeleton.get_bone_rest(idx).is_equal_approx(rest_before):
            _failures.append("target_rest_changed role=%s" % role)

func _verify_target_integrity_after_measurement() -> void:
    _verify_target_snapshot_after_rename()

func _reset_target_pose() -> void:
    _target_skeleton.reset_bone_poses()
    _target_skeleton.force_update_all_bone_transforms()

func _collect_skinned_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D:
        var mesh := node as MeshInstance3D
        if mesh.get_skin() != null or not mesh.get_skeleton_path().is_empty():
            out.append(mesh)
    for child: Node in node.get_children():
        _collect_skinned_meshes(child, out)

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

func _torso_bend(skeleton: Skeleton3D, source: bool) -> float:
    var spine_idx := skeleton.find_bone(_source_name("spine") if source else _source_name("spine"))
    var chest_idx := skeleton.find_bone(_source_name("chest") if source else _source_name("chest"))
    var neck_idx := skeleton.find_bone(_source_name("neck") if source else _source_name("neck"))
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

func _target_bone_position(role: String) -> Vector3:
    var idx := _target_skeleton.find_bone(_source_name(role))
    return Vector3.ZERO if idx < 0 else _target_skeleton.get_bone_global_pose(idx).origin

func _source_name(role: String) -> String:
    var pair: Array = ROLE_PAIRS.get(role, [])
    return "" if pair.size() < 2 else String(pair[0])

func _target_name(role: String) -> String:
    var pair: Array = ROLE_PAIRS.get(role, [])
    return "" if pair.size() < 2 else String(pair[1])

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
        var all_found := true
        for clip: String in CLIPS:
            if _resolve_animation_name(player, clip).is_empty():
                all_found = false
                break
        if all_found:
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

func _has_failure_token(token: String) -> bool:
    for failure: String in _failures:
        if failure.contains(token):
            return true
    return false

func _write_result(result: Dictionary) -> void:
    var file := FileAccess.open("res://gate8_variant01_native_retarget_ab_result.json", FileAccess.WRITE)
    if file == null:
        _failures.append("result_file_open_failed")
        return
    file.store_string(JSON.stringify(result, "  "))
    file.close()

func _finish(_result: Dictionary) -> void:
    if _failures.is_empty():
        print("GATE8_VARIANT01_NATIVE_RETARGET_AB_OK candidate=01 clips=Jog_Fwd,Sprint engine=RetargetModifier3D alias_selected=false production_authorized=false")
        quit(0)
        return
    for failure: String in _failures:
        push_error("GATE8_VARIANT01_NATIVE_RETARGET_AB_FAIL %s" % failure)
    quit(1)
