extends SceneTree

const SOURCE_SCENE := "res://assets/animation_source.glb"
const TARGET_SCENE := "res://assets/npc_gate_01.glb"
const CLIPS: Array[String] = ["Jog_Fwd", "Sprint"]
const DISTANCES_M: Array[float] = [2.0, 5.0, 8.0]
const CAPTURE_SIZE := Vector2i(1280, 720)
const SAMPLE_RATE_HZ := 60.0
const SETTLE_FRAMES := 2
const CAMERA_EYE_HEIGHT_M := 1.62
const CAMERA_FOV_DEGREES := 68.0
const MAX_GROUNDING_CORRECTION_M := 0.25
const MIN_TARGET_POSE_DELTA_DEG := 5.0

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
    "hips": "", "spine": "hips", "chest": "spine", "upper_chest": "chest",
    "neck": "upper_chest", "head": "neck",
    "left_shoulder": "upper_chest", "left_upper_arm": "left_shoulder",
    "left_forearm": "left_upper_arm", "left_hand": "left_forearm",
    "right_shoulder": "upper_chest", "right_upper_arm": "right_shoulder",
    "right_forearm": "right_upper_arm", "right_hand": "right_forearm",
    "left_upper_leg": "hips", "left_lower_leg": "left_upper_leg",
    "left_foot": "left_lower_leg", "left_toe": "left_foot",
    "right_upper_leg": "hips", "right_lower_leg": "right_upper_leg",
    "right_foot": "right_lower_leg", "right_toe": "right_foot",
}
const MOTION_ROLES: Array[String] = [
    "hips", "chest", "left_upper_arm", "right_upper_arm",
    "left_upper_leg", "right_upper_leg", "left_lower_leg", "right_lower_leg",
]

var _failures: Array[String] = []
var _source_scene: Node3D
var _target_scene: Node3D
var _source_real: Skeleton3D
var _target_real: Skeleton3D
var _source_probe: Skeleton3D
var _target_probe: Skeleton3D
var _player: AnimationPlayer
var _viewport: SubViewport
var _world_root: Node3D
var _camera: Camera3D
var _source_role_indices: Dictionary = {}
var _source_probe_role_indices: Dictionary = {}
var _target_probe_role_indices: Dictionary = {}
var _target_real_role_indices: Dictionary = {}

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    _source_scene = _instantiate(SOURCE_SCENE)
    _target_scene = _instantiate(TARGET_SCENE)
    if _source_scene == null or _target_scene == null:
        _finish({})
        return

    root.add_child(_source_scene)
    _source_scene.visible = false
    _build_viewport()
    _world_root.add_child(_target_scene)
    await _settle()

    _source_real = _find_skeleton(_source_scene)
    _target_real = _find_skeleton(_target_scene)
    _player = _find_player_with_clips(_source_scene)
    if _source_real == null or _target_real == null or _player == null:
        _failures.append("required_source_target_or_player_missing")
        _finish({})
        return

    var integrity := _target_integrity(_target_scene)
    if int(integrity["skinned_meshes"]) <= 0 or int(integrity["skinned_surfaces"]) <= 0:
        _failures.append("target_skin_missing")
    if int(integrity["missing_material_surfaces"]) != 0:
        _failures.append("target_material_missing surfaces=%d" % int(integrity["missing_material_surfaces"]))

    _source_probe = _clone_skeleton_data(_source_real)
    _target_probe = _clone_skeleton_data(_target_real)
    _source_probe.name = "CanonicalVisualSource"
    _target_probe.name = "CanonicalVisualTarget"
    root.add_child(_source_probe)
    _canonicalize(_source_probe, 0)
    _canonicalize(_target_probe, 1)
    if not _cache_role_indices():
        _finish({})
        return

    var modifier := RetargetModifier3D.new()
    modifier.name = "NativeVisualRetarget"
    modifier.set_use_global_pose(false)
    modifier.set_position_enabled(false)
    modifier.set_rotation_enabled(true)
    modifier.set_scale_enabled(false)
    _source_probe.add_child(modifier)
    modifier.add_child(_target_probe)
    modifier.set_profile(_build_profile())
    await _settle()

    var output_dir := OS.get_environment("GATE8_NATIVE_VISUAL_DIR")
    if output_dir.is_empty():
        output_dir = "user://gate8_native_visual"
    var mkdir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
    if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
        _failures.append("output_dir_failed=%s" % error_string(mkdir_error))
        _finish({})
        return

    var clip_rows := {}
    var capture_count := 0
    for clip in CLIPS:
        var selected := await _find_peak_pose_time(clip)
        if selected.is_empty():
            continue
        var time_s := float(selected["time_s"])
        var peak_delta := float(selected["peak_target_pose_delta_deg"])
        await _apply_clip_time_to_real_target(clip, time_s)
        var correction := _ground_real_target()
        if absf(correction) > MAX_GROUNDING_CORRECTION_M:
            _failures.append("grounding_correction_out_of_range clip=%s correction=%.4f" % [clip, correction])
        var frames: Array[String] = []
        for distance_m in DISTANCES_M:
            var path := await _capture_frame(clip, distance_m, output_dir)
            if not path.is_empty():
                frames.append(path)
                capture_count += 1
        clip_rows[clip] = {
            "time_s": time_s,
            "peak_target_pose_delta_deg": peak_delta,
            "grounding_correction_m": correction,
            "frames": frames,
        }
        _target_scene.position.y = 0.0
        _target_real.reset_bone_poses()
        _target_real.force_update_all_bone_transforms()
        await _settle()

    if capture_count != CLIPS.size() * DISTANCES_M.size():
        _failures.append("capture_count_mismatch=%d" % capture_count)

    var result := {
        "format": "grand-bruxelles-gate8-variant01-native-skin-witness-v2",
        "engine_version": Engine.get_version_info().get("string", "unknown"),
        "candidate_variant": 1,
        "native_modifier": true,
        "skin_safe_pose_mirror": true,
        "stable_skin_role_index_cache": true,
        "source_role_cache_count": _source_role_indices.size(),
        "source_probe_role_cache_count": _source_probe_role_indices.size(),
        "target_probe_role_cache_count": _target_probe_role_indices.size(),
        "target_real_role_cache_count": _target_real_role_indices.size(),
        "capture_size": [CAPTURE_SIZE.x, CAPTURE_SIZE.y],
        "distances_m": DISTANCES_M,
        "capture_count": capture_count,
        "target_integrity": integrity,
        "clips": clip_rows,
        "run_alias_selected": "",
        "production_authorized": false,
        "activation_ready": false,
        "adoption_ready": false,
        "visual_approval_claimed": false,
        "selection_state": "PLAYER_VIEW_REVIEW_REQUIRED" if _failures.is_empty() else "BLOCKED_SKIN_WITNESS",
        "failures": _failures,
    }
    _write_result(result)
    print("GATE8_NATIVE_SKIN_WITNESS captures=%d stable_skin_role_index_cache=true cached_roles=%d alias_selected=false production_authorized=false" % [capture_count, ROLE_PAIRS.size()])
    _finish(result)

func _cache_role_indices() -> bool:
    _source_role_indices.clear()
    _source_probe_role_indices.clear()
    _target_probe_role_indices.clear()
    _target_real_role_indices.clear()
    for role in ROLE_PAIRS:
        var source_idx := _source_real.find_bone(String(ROLE_PAIRS[role][0]))
        var source_probe_idx := _source_probe.find_bone(_canonical(role))
        var target_probe_idx := _target_probe.find_bone(_canonical(role))
        var target_real_idx := _target_real.find_bone(String(ROLE_PAIRS[role][1]))
        if source_idx < 0 or source_probe_idx < 0 or target_probe_idx < 0 or target_real_idx < 0:
            _failures.append("skin_role_index_cache_incomplete role=%s source=%d source_probe=%d target_probe=%d target_real=%d" % [role, source_idx, source_probe_idx, target_probe_idx, target_real_idx])
            continue
        _source_role_indices[role] = source_idx
        _source_probe_role_indices[role] = source_probe_idx
        _target_probe_role_indices[role] = target_probe_idx
        _target_real_role_indices[role] = target_real_idx
    var expected := ROLE_PAIRS.size()
    var complete := _source_role_indices.size() == expected and _source_probe_role_indices.size() == expected and _target_probe_role_indices.size() == expected and _target_real_role_indices.size() == expected
    if not complete:
        _failures.append("skin_role_index_cache_count_mismatch expected=%d source=%d source_probe=%d target_probe=%d target_real=%d" % [expected, _source_role_indices.size(), _source_probe_role_indices.size(), _target_probe_role_indices.size(), _target_real_role_indices.size()])
    return complete

func _find_peak_pose_time(token: String) -> Dictionary:
    var animation_name := _resolve_animation_name(_player, token)
    if animation_name.is_empty():
        _failures.append("clip_missing=%s" % token)
        return {}
    var animation := _player.get_animation(animation_name)
    if animation == null or animation.length <= 0.0:
        _failures.append("clip_invalid=%s" % token)
        return {}
    var samples := maxi(40, int(ceil(animation.length * SAMPLE_RATE_HZ)))
    var best_time := 0.0
    var best_delta := -INF
    _player.play(animation_name)
    for i in range(samples):
        var time_s := minf(animation.length - 0.00001, float(i) * animation.length / float(samples))
        _player.seek(time_s, true)
        _player.advance(0.0)
        _source_real.force_update_all_bone_transforms()
        _copy_source_pose_to_probe()
        _source_probe.force_update_all_bone_transforms()
        await _settle()
        _target_probe.force_update_all_bone_transforms()
        var delta := _target_motion_delta_deg()
        if delta > best_delta:
            best_delta = delta
            best_time = time_s
    _player.stop()
    if best_delta < MIN_TARGET_POSE_DELTA_DEG:
        _failures.append("target_motion_too_small clip=%s peak=%.3f" % [token, best_delta])
    return {"time_s": best_time, "peak_target_pose_delta_deg": best_delta}

func _apply_clip_time_to_real_target(token: String, time_s: float) -> void:
    var animation_name := _resolve_animation_name(_player, token)
    _player.play(animation_name)
    _player.seek(time_s, true)
    _player.advance(0.0)
    _source_real.force_update_all_bone_transforms()
    _copy_source_pose_to_probe()
    _source_probe.force_update_all_bone_transforms()
    await _settle()
    _target_probe.force_update_all_bone_transforms()
    _target_real.reset_bone_poses()
    for role in ROLE_PAIRS:
        var probe_idx: int = _target_probe_role_indices[role]
        var real_idx: int = _target_real_role_indices[role]
        _target_real.set_bone_pose_rotation(real_idx, _target_probe.get_bone_pose_rotation(probe_idx))
    _target_real.force_update_all_bone_transforms()
    _player.stop()
    await _settle()

func _copy_source_pose_to_probe() -> void:
    for role in ROLE_PAIRS:
        var source_idx: int = _source_role_indices[role]
        var probe_idx: int = _source_probe_role_indices[role]
        _source_probe.set_bone_pose_position(probe_idx, _source_real.get_bone_pose_position(source_idx))
        _source_probe.set_bone_pose_rotation(probe_idx, _source_real.get_bone_pose_rotation(source_idx))
        _source_probe.set_bone_pose_scale(probe_idx, _source_real.get_bone_pose_scale(source_idx))

func _ground_real_target() -> float:
    _target_scene.position.y = 0.0
    _target_real.force_update_all_bone_transforms()
    var left_idx: int = _target_real_role_indices["left_foot"]
    var right_idx: int = _target_real_role_indices["right_foot"]
    var left_y := (_target_real.global_transform * _target_real.get_bone_global_pose(left_idx).origin).y
    var right_y := (_target_real.global_transform * _target_real.get_bone_global_pose(right_idx).origin).y
    var correction := -minf(left_y, right_y)
    _target_scene.position.y += correction
    _target_real.force_update_all_bone_transforms()
    return correction

func _capture_frame(token: String, distance_m: float, output_dir: String) -> String:
    _target_scene.position.z = -distance_m
    var head_idx: int = _target_real_role_indices["head"]
    var left_idx: int = _target_real_role_indices["left_foot"]
    var right_idx: int = _target_real_role_indices["right_foot"]
    await _settle()
    var head_world := _target_real.to_global(_target_real.get_bone_global_pose(head_idx).origin)
    var left_world := _target_real.to_global(_target_real.get_bone_global_pose(left_idx).origin)
    var right_world := _target_real.to_global(_target_real.get_bone_global_pose(right_idx).origin)
    var look_target := (head_world + (left_world + right_world) * 0.5) * 0.5
    _camera.position = Vector3(0.0, CAMERA_EYE_HEIGHT_M, 0.0)
    _camera.look_at(look_target, Vector3.UP)
    await _settle()
    await RenderingServer.frame_post_draw
    var image := _viewport.get_texture().get_image()
    if image == null or image.is_empty() or image.get_size() != CAPTURE_SIZE:
        _failures.append("capture_invalid clip=%s distance=%.1f" % [token, distance_m])
        return ""
    var safe_token := token.to_lower().replace("_", "-")
    var output_path := output_dir.path_join("gate8-variant01-%s-%dm.png" % [safe_token, int(distance_m)])
    var error := image.save_png(output_path)
    if error != OK:
        _failures.append("capture_save_failed clip=%s distance=%.1f error=%s" % [token, distance_m, error_string(error)])
        return ""
    print("GATE8_NATIVE_SKIN_FRAME_OK clip=%s distance=%dm size=1280x720 screenshot=%s" % [token, int(distance_m), output_path])
    return output_path

func _build_viewport() -> void:
    _viewport = SubViewport.new()
    _viewport.size = CAPTURE_SIZE
    _viewport.own_world_3d = true
    _viewport.transparent_bg = false
    _viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(_viewport)
    _world_root = Node3D.new()
    _viewport.add_child(_world_root)
    var world_environment := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.08, 0.10, 0.14, 1.0)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.72, 0.75, 0.82, 1.0)
    environment.ambient_light_energy = 0.8
    world_environment.environment = environment
    _world_root.add_child(world_environment)
    var key := DirectionalLight3D.new()
    key.rotation_degrees = Vector3(-48.0, -24.0, 0.0)
    key.light_energy = 1.4
    key.shadow_enabled = true
    _world_root.add_child(key)
    var fill := DirectionalLight3D.new()
    fill.rotation_degrees = Vector3(-25.0, 155.0, 0.0)
    fill.light_energy = 0.55
    _world_root.add_child(fill)
    var floor := MeshInstance3D.new()
    var floor_mesh := PlaneMesh.new()
    floor_mesh.size = Vector2(14.0, 20.0)
    var floor_material := StandardMaterial3D.new()
    floor_material.albedo_color = Color(0.24, 0.26, 0.29, 1.0)
    floor_material.roughness = 0.96
    floor_mesh.material = floor_material
    floor.mesh = floor_mesh
    floor.position = Vector3(0.0, -0.005, -4.5)
    _world_root.add_child(floor)
    _camera = Camera3D.new()
    _camera.position = Vector3(0.0, CAMERA_EYE_HEIGHT_M, 0.0)
    _camera.fov = CAMERA_FOV_DEGREES
    _camera.near = 0.05
    _camera.current = true
    _world_root.add_child(_camera)

func _target_integrity(node: Node) -> Dictionary:
    var skinned_meshes := 0
    var skinned_surfaces := 0
    var materials := 0
    var missing_material_surfaces := 0
    for raw in node.find_children("*", "MeshInstance3D", true, false):
        var mesh_instance := raw as MeshInstance3D
        if mesh_instance == null or mesh_instance.mesh == null:
            continue
        if mesh_instance.skin != null or not mesh_instance.skeleton.is_empty():
            skinned_meshes += 1
            for surface in range(mesh_instance.mesh.get_surface_count()):
                skinned_surfaces += 1
                var material := mesh_instance.get_surface_override_material(surface)
                if material == null:
                    material = mesh_instance.mesh.surface_get_material(surface)
                if material == null:
                    missing_material_surfaces += 1
                else:
                    materials += 1
    return {
        "skinned_meshes": skinned_meshes,
        "skinned_surfaces": skinned_surfaces,
        "materials": materials,
        "missing_material_surfaces": missing_material_surfaces,
    }

func _target_motion_delta_deg() -> float:
    var peak := 0.0
    for role in MOTION_ROLES:
        var idx: int = _target_probe_role_indices[role]
        peak = maxf(peak, rad_to_deg(_target_probe.get_bone_rest(idx).basis.get_rotation_quaternion().angle_to(_target_probe.get_bone_pose_rotation(idx))))
    return peak

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
        var animation_name := String(name_value)
        if animation_name.split("/")[-1] == token:
            return animation_name
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

func _canonicalize(skeleton: Skeleton3D, side: int) -> void:
    for role in ROLE_PAIRS:
        var idx := skeleton.find_bone(String(ROLE_PAIRS[role][side]))
        if idx < 0:
            _failures.append("bone_missing side=%d role=%s" % [side, role])
            continue
        skeleton.set_bone_name(idx, _canonical(role))

func _build_profile() -> SkeletonProfile:
    var profile := SkeletonProfile.new()
    profile.bone_size = ROLE_PAIRS.size()
    var index := 0
    for role in ROLE_PAIRS:
        profile.set_bone_name(index, _canonical(role))
        var parent_role := String(ROLE_PARENT[role])
        if not parent_role.is_empty():
            profile.set_bone_parent(index, _canonical(parent_role))
        profile.set_required(index, true)
        index += 1
    profile.root_bone = _canonical("hips")
    profile.scale_base_bone = _canonical("hips")
    return profile

func _canonical(role: String) -> String:
    return "gb_humanoid_%s" % role

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null

func _instantiate(path: String) -> Node3D:
    var packed := load(path) as PackedScene
    if packed == null:
        _failures.append("scene_load_failed=%s" % path)
        return null
    return packed.instantiate() as Node3D

func _settle() -> void:
    for _i in range(SETTLE_FRAMES):
        await process_frame

func _write_result(result: Dictionary) -> void:
    var file := FileAccess.open("res://gate8_variant01_native_skin_witness_result.json", FileAccess.WRITE)
    if file == null:
        _failures.append("result_file_open_failed")
        return
    file.store_string(JSON.stringify(result, "  "))
    file.close()

func _finish(_result: Dictionary) -> void:
    if _failures.is_empty():
        print("GATE8_NATIVE_SKIN_WITNESS_OK player_view_review_required=true stable_skin_role_index_cache=true production_authorized=false")
        quit(0)
        return
    for failure in _failures:
        push_error("GATE8_NATIVE_SKIN_WITNESS_FAIL %s" % failure)
    quit(1)
