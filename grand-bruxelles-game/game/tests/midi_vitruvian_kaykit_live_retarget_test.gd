extends SceneTree

const SOURCE_SCENE := "res://assets/characters/_review/kaykit_retarget_source/Rogue.glb"
const TARGET_SCENE := "res://assets/characters/_review/vitruvian_game_rig_live_retarget/body.glb"
const SOURCE_MAP_PATH := "res://data/qa/midi_kaykit_humanoid_source_bone_map.json"
const TARGET_MAP_PATH := "res://data/qa/midi_vitruvian_game_rig_humanoid_bone_map.json"
const SAMPLE_FPS := 30.0

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var output := "/tmp/vitruvian-kaykit-live-retarget.metrics.json"
    var args := OS.get_cmdline_user_args()
    if not args.is_empty():
        output = str(args[0])

    var source_cfg := _read_json(SOURCE_MAP_PATH)
    var target_cfg := _read_json(TARGET_MAP_PATH)
    if source_cfg.is_empty() or target_cfg.is_empty():
        return _fail("source/target BoneMap config missing")
    if bool(source_cfg.get("production_authorized", true)) or bool(target_cfg.get("production_authorized", true)):
        return _fail("review BoneMaps cannot be production-authorized")

    var source_packed := ResourceLoader.load(SOURCE_SCENE) as PackedScene
    var target_packed := ResourceLoader.load(TARGET_SCENE) as PackedScene
    if source_packed == null or target_packed == null:
        return _fail("source or target review GLB failed to import")
    var source_root := source_packed.instantiate() as Node3D
    var target_root := target_packed.instantiate() as Node3D
    if source_root == null or target_root == null:
        return _fail("source or target review GLB failed to instantiate")
    get_root().add_child(source_root)
    get_root().add_child(target_root)
    await process_frame

    var source_skeletons: Array[Skeleton3D] = []
    var source_players: Array[AnimationPlayer] = []
    var source_meshes: Array[MeshInstance3D] = []
    _collect(source_root, source_skeletons, source_players, source_meshes)
    var target_skeletons: Array[Skeleton3D] = []
    var target_players: Array[AnimationPlayer] = []
    var target_meshes: Array[MeshInstance3D] = []
    _collect(target_root, target_skeletons, target_players, target_meshes)
    if source_skeletons.size() != 1 or source_players.is_empty():
        return _fail("KayKit source must expose one Skeleton3D and an AnimationPlayer")
    if target_skeletons.size() != 1 or target_meshes.is_empty():
        return _fail("Vitruvian target must expose one Skeleton3D and a skinned mesh")

    var source_actual := source_skeletons[0]
    var target_actual := target_skeletons[0]
    var player := source_players[0]
    player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL

    var source_mapping := source_cfg.get("required_core_mapping", {}) as Dictionary
    var source_expectations := source_cfg.get("required_profile_parent_expectations", {}) as Dictionary
    var target_mapping := target_cfg.get("required_core_mapping", {}) as Dictionary
    var target_expectations := target_cfg.get("required_profile_parent_expectations", {}) as Dictionary
    if source_mapping.size() != 18 or target_mapping.size() != 22:
        return _fail("unexpected mapping sizes source=%d target=%d" % [source_mapping.size(), target_mapping.size()])

    var source_norm_result := _build_normalized_skeleton(source_actual, source_mapping, source_expectations, "KayKitHumanoidSource")
    var target_norm_result := _build_normalized_skeleton(target_actual, target_mapping, target_expectations, "VitruvianHumanoidTarget")
    if source_norm_result.is_empty() or target_norm_result.is_empty():
        return
    var source_norm := source_norm_result["skeleton"] as Skeleton3D
    var target_norm := target_norm_result["skeleton"] as Skeleton3D
    var source_order := source_norm_result["order"] as Array

    var rig_root := Node3D.new()
    rig_root.name = "LiveRetargetRig"
    get_root().add_child(rig_root)
    rig_root.add_child(source_norm)
    source_norm.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
    var modifier := RetargetModifier3D.new()
    modifier.name = "HumanoidRetarget"
    modifier.profile = SkeletonProfileHumanoid.new()
    modifier.use_global_pose = false
    modifier.set_position_enabled(true)
    modifier.set_rotation_enabled(true)
    modifier.set_scale_enabled(false)
    source_norm.add_child(modifier)
    modifier.add_child(target_norm)
    await process_frame

    var source_motion_scale := _humanoid_motion_scale(source_norm)
    var target_motion_scale := _humanoid_motion_scale(target_norm)
    source_norm.motion_scale = source_motion_scale
    target_norm.motion_scale = target_motion_scale
    var scale_ratio := target_motion_scale / source_motion_scale
    if source_motion_scale <= 0.05 or target_motion_scale <= 0.2 or scale_ratio < 1.2 or scale_ratio > 3.5:
        return _fail("implausible motion scale source=%.4f target=%.4f ratio=%.4f" % [source_motion_scale, target_motion_scale, scale_ratio])

    var selection := source_cfg.get("selected_initial_clips", {}) as Dictionary
    var clip_results := {}
    var resolved_keys := {}
    for role in ["idle", "walk", "run"]:
        var clip_name := str(selection.get(role, ""))
        var key := _resolve_animation_key(player, clip_name)
        if key == StringName():
            return _fail("selected clip missing in imported source: %s" % clip_name)
        resolved_keys[role] = str(key)
        var result := await _sample_clip(player, key, clip_name, role, source_actual, source_norm, target_norm, source_mapping, source_expectations, source_order)
        if result.is_empty():
            return
        clip_results[role] = result

    var idle := clip_results["idle"] as Dictionary
    var walk := clip_results["walk"] as Dictionary
    var run := clip_results["run"] as Dictionary
    if float(idle.get("recommended_world_speed_mps", 99.0)) > 0.20:
        return _fail("idle motion is not stationary enough: %s" % str(idle))
    if float(idle.get("mean_contact_residual_mps", 99.0)) > 0.10:
        return _fail("idle feet move too much: %s" % str(idle))
    var walk_speed := float(walk.get("recommended_world_speed_mps", 0.0))
    var run_speed := float(run.get("recommended_world_speed_mps", 0.0))
    if walk_speed < 0.40 or walk_speed > 3.0:
        return _fail("walk cadence/world-speed estimate implausible: %.4f" % walk_speed)
    if run_speed < 1.0 or run_speed > 7.0 or run_speed <= walk_speed * 1.20:
        return _fail("run cadence/world-speed estimate implausible: walk=%.4f run=%.4f" % [walk_speed, run_speed])
    if float(walk.get("mean_contact_residual_mps", 99.0)) > 0.50:
        return _fail("walk live-retarget stance residual too high: %s" % str(walk))
    if float(run.get("mean_contact_residual_mps", 99.0)) > 1.00:
        return _fail("run live-retarget stance residual too high: %s" % str(run))
    if int(walk.get("contact_delta_count", 0)) < 4 or int(run.get("contact_delta_count", 0)) < 3:
        return _fail("insufficient stance samples walk=%s run=%s" % [str(walk), str(run)])

    var metrics := {
        "schema": "grand-bruxelles-vitruvian-kaykit-live-retarget-v1",
        "production_authorized": false,
        "source_license": "CC0-1.0",
        "source_mesh_runtime_reuse": false,
        "source_scene_review_only": SOURCE_SCENE,
        "target_scene_review_only": TARGET_SCENE,
        "retarget_engine": "Godot_4_7_1_RetargetModifier3D_SkeletonProfileHumanoid",
        "source_mapping_count": source_mapping.size(),
        "target_mapping_count": target_mapping.size(),
        "source_motion_scale": source_motion_scale,
        "target_motion_scale": target_motion_scale,
        "motion_scale_ratio": scale_ratio,
        "selected_clips": selection.duplicate(true),
        "resolved_animation_keys": resolved_keys,
        "sample_fps": SAMPLE_FPS,
        "clips": clip_results,
        "scale_transfer_enabled": false,
        "position_transfer_enabled": true,
        "rotation_transfer_enabled": true,
        "root_world_translation_owner": "existing_ambient_pedestrian_runtime",
        "clips_baked": false,
        "next_gate": "bake only these three retargeted target-skeleton clips, verify loop/cycle closure on actual Vitruvian mesh, then wire dormant authored NPC runtime"
    }
    var file := FileAccess.open(output, FileAccess.WRITE)
    if file == null:
        return _fail("could not write live-retarget metrics")
    file.store_string(JSON.stringify(metrics, "  ") + "\n")
    file.close()
    print("GB_VITRUVIAN_KAYKIT_LIVE_RETARGET_OK idle=%s walk=%s run=%s walk_mps=%.4f run_mps=%.4f walk_residual=%.4f run_residual=%.4f source_mesh_reuse=false production_authorized=false" % [selection["idle"], selection["walk"], selection["run"], walk_speed, run_speed, float(walk["mean_contact_residual_mps"]), float(run["mean_contact_residual_mps"])])
    quit(0)

func _sample_clip(player: AnimationPlayer, key: StringName, clip_name: String, role: String, source_actual: Skeleton3D, source_norm: Skeleton3D, target_norm: Skeleton3D, mapping: Dictionary, expectations: Dictionary, order: Array) -> Dictionary:
    var animation := player.get_animation(key)
    if animation == null or animation.length <= 0.0:
        _fail("invalid animation length for %s" % clip_name)
        return {}
    player.stop()
    source_actual.reset_bone_poses()
    source_norm.reset_bone_poses()
    target_norm.reset_bone_poses()
    player.play(key)
    player.seek(0.0, true)
    player.advance(0.0)

    var dt := 1.0 / SAMPLE_FPS
    var steps := maxi(2, int(ceil(animation.length * SAMPLE_FPS)) + 1)
    var samples: Array[Dictionary] = []
    for i in range(steps):
        var t := min(float(i) * dt, animation.length)
        player.seek(t, true)
        player.advance(0.0)
        source_actual.force_update_all_bone_transforms()
        if not _copy_collapsed_pose(source_actual, source_norm, mapping, expectations, order):
            return {}
        source_norm.advance(0.0)
        target_norm.force_update_all_bone_transforms()
        samples.append({
            "t": t,
            "left_foot": _bone_global_origin(target_norm, "LeftFoot"),
            "right_foot": _bone_global_origin(target_norm, "RightFoot"),
            "left_toes": _bone_global_origin(target_norm, "LeftToes"),
            "right_toes": _bone_global_origin(target_norm, "RightToes"),
            "hips": _bone_global_origin(target_norm, "Hips")
        })
    player.stop()
    source_actual.reset_bone_poses()
    var analysis := _analyze_samples(samples, animation.length, role)
    analysis["clip_name"] = clip_name
    analysis["animation_key"] = str(key)
    analysis["duration_s"] = animation.length
    analysis["sample_count"] = samples.size()
    return analysis

func _analyze_samples(samples: Array[Dictionary], duration: float, role: String) -> Dictionary:
    var velocities: Array[Vector2] = []
    var foot_details := {}
    for foot_key in ["left_foot", "right_foot"]:
        var min_y := INF
        var max_y := -INF
        for sample in samples:
            var p := sample[foot_key] as Vector3
            min_y = min(min_y, p.y)
            max_y = max(max_y, p.y)
        var threshold := min_y + max(0.012, (max_y - min_y) * 0.35)
        var contact_count := 0
        for i in range(samples.size() - 1):
            var a := samples[i][foot_key] as Vector3
            var b := samples[i + 1][foot_key] as Vector3
            var step_dt := float(samples[i + 1]["t"]) - float(samples[i]["t"])
            if step_dt <= 0.00001:
                continue
            if a.y <= threshold and b.y <= threshold:
                velocities.append(Vector2((b.x - a.x) / step_dt, (b.z - a.z) / step_dt))
                contact_count += 1
        foot_details[foot_key] = {
            "min_y": min_y,
            "max_y": max_y,
            "vertical_range": max_y - min_y,
            "contact_threshold_y": threshold,
            "contact_delta_count": contact_count
        }

    if velocities.is_empty():
        _fail("no stance/contact deltas detected for %s" % role)
        return {}
    var mean_velocity := Vector2.ZERO
    for velocity in velocities:
        mean_velocity += velocity
    mean_velocity /= float(velocities.size())
    var world_velocity := -mean_velocity
    var residual_sum := 0.0
    var residual_max := 0.0
    for velocity in velocities:
        var residual := (velocity + world_velocity).length()
        residual_sum += residual
        residual_max = max(residual_max, residual)
    var residual_mean := residual_sum / float(velocities.size())

    var first := samples[0]
    var last := samples[-1]
    var left_cycle := _horizontal_distance(first["left_foot"] as Vector3, last["left_foot"] as Vector3)
    var right_cycle := _horizontal_distance(first["right_foot"] as Vector3, last["right_foot"] as Vector3)
    var hips_y_min := INF
    var hips_y_max := -INF
    for sample in samples:
        var hips := sample["hips"] as Vector3
        hips_y_min = min(hips_y_min, hips.y)
        hips_y_max = max(hips_y_max, hips.y)

    return {
        "recommended_world_velocity_local_xz": [world_velocity.x, world_velocity.y],
        "recommended_world_speed_mps": world_velocity.length(),
        "mean_contact_residual_mps": residual_mean,
        "max_contact_residual_mps": residual_max,
        "contact_delta_count": velocities.size(),
        "cycle_closure_left_foot_m": left_cycle,
        "cycle_closure_right_foot_m": right_cycle,
        "hips_vertical_range_m": hips_y_max - hips_y_min,
        "foot_contact": foot_details,
        "duration_s": duration
    }

func _build_normalized_skeleton(actual: Skeleton3D, mapping: Dictionary, expectations: Dictionary, node_name: String) -> Dictionary:
    var order := _topological_profile_order(mapping, expectations)
    if order.size() != mapping.size():
        _fail("could not topologically order mapping for %s" % node_name)
        return {}
    var norm := Skeleton3D.new()
    norm.name = node_name
    var profile_to_index := {}
    for profile_variant in order:
        var profile := str(profile_variant)
        var source_name := str(mapping[profile])
        var actual_index := actual.find_bone(source_name)
        if actual_index < 0:
            _fail("%s missing mapped source bone %s for %s" % [node_name, source_name, profile])
            return {}
        var index := norm.add_bone(profile)
        profile_to_index[profile] = index
        var parent_profile := str(expectations.get(profile, ""))
        var global_rest := actual.get_bone_global_rest(actual_index)
        var local_rest := global_rest
        if not parent_profile.is_empty():
            if not profile_to_index.has(parent_profile):
                _fail("%s parent role not created: %s -> %s" % [node_name, profile, parent_profile])
                return {}
            norm.set_bone_parent(index, int(profile_to_index[parent_profile]))
            var parent_actual := actual.find_bone(str(mapping[parent_profile]))
            local_rest = actual.get_bone_global_rest(parent_actual).affine_inverse() * global_rest
        norm.set_bone_rest(index, local_rest)
    norm.reset_bone_poses()
    return {"skeleton": norm, "order": order}

func _copy_collapsed_pose(actual: Skeleton3D, norm: Skeleton3D, mapping: Dictionary, expectations: Dictionary, order: Array) -> bool:
    for profile_variant in order:
        var profile := str(profile_variant)
        var actual_index := actual.find_bone(str(mapping[profile]))
        var norm_index := norm.find_bone(profile)
        if actual_index < 0 or norm_index < 0:
            _fail("pose copy mapping vanished for %s" % profile)
            return false
        var global_pose := actual.get_bone_global_pose(actual_index)
        var local_pose := global_pose
        var parent_profile := str(expectations.get(profile, ""))
        if not parent_profile.is_empty():
            var parent_actual := actual.find_bone(str(mapping[parent_profile]))
            local_pose = actual.get_bone_global_pose(parent_actual).affine_inverse() * global_pose
        norm.set_bone_pose(norm_index, local_pose)
    norm.force_update_all_bone_transforms()
    return true

func _topological_profile_order(mapping: Dictionary, expectations: Dictionary) -> Array:
    var pending: Array = mapping.keys()
    var order: Array = []
    var guard := 0
    while not pending.is_empty() and guard < 128:
        guard += 1
        var progressed := false
        for i in range(pending.size() - 1, -1, -1):
            var profile := str(pending[i])
            var parent := str(expectations.get(profile, ""))
            if parent.is_empty() or parent in order:
                order.append(profile)
                pending.remove_at(i)
                progressed = true
        if not progressed:
            break
    return order

func _humanoid_motion_scale(skeleton: Skeleton3D) -> float:
    var hips := skeleton.find_bone("Hips")
    if hips < 0:
        return 0.0
    return abs(skeleton.get_bone_global_rest(hips).origin.y)

func _resolve_animation_key(player: AnimationPlayer, desired: String) -> StringName:
    for key in player.get_animation_list():
        var text := str(key)
        if text == desired or text.get_slice("/", text.get_slice_count("/") - 1) == desired:
            return key
    return StringName()

func _bone_global_origin(skeleton: Skeleton3D, profile_name: String) -> Vector3:
    var index := skeleton.find_bone(profile_name)
    if index < 0:
        return Vector3.ZERO
    return skeleton.get_bone_global_pose(index).origin

func _horizontal_distance(a: Vector3, b: Vector3) -> float:
    return Vector2(a.x - b.x, a.z - b.z).length()

func _collect(node: Node, skeletons: Array[Skeleton3D], players: Array[AnimationPlayer], meshes: Array[MeshInstance3D]) -> void:
    if node is Skeleton3D:
        skeletons.append(node as Skeleton3D)
    if node is AnimationPlayer:
        players.append(node as AnimationPlayer)
    if node is MeshInstance3D:
        meshes.append(node as MeshInstance3D)
    for child in node.get_children():
        _collect(child, skeletons, players, meshes)

func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed := JSON.parse_string(file.get_as_text())
    return parsed as Dictionary if parsed is Dictionary else {}

func _fail(message: String) -> void:
    push_error("GB_VITRUVIAN_KAYKIT_LIVE_RETARGET_FAIL: %s" % message)
    quit(2)
