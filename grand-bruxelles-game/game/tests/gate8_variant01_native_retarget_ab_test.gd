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
    "hips", "spine", "chest", "upper_chest", "neck", "head",
    "left_shoulder", "left_upper_arm", "left_forearm", "left_hand",
    "right_shoulder", "right_upper_arm", "right_forearm", "right_hand",
    "left_upper_leg", "left_lower_leg", "left_foot", "left_toe",
    "right_upper_leg", "right_lower_leg", "right_foot", "right_toe"
]

const PARENT_ROLE := {
    "hips": "", "spine": "hips", "chest": "spine", "upper_chest": "chest",
    "neck": "upper_chest", "head": "neck",
    "left_shoulder": "upper_chest", "left_upper_arm": "left_shoulder",
    "left_forearm": "left_upper_arm", "left_hand": "left_forearm",
    "right_shoulder": "upper_chest", "right_upper_arm": "right_shoulder",
    "right_forearm": "right_upper_arm", "right_hand": "right_forearm",
    "left_upper_leg": "hips", "left_lower_leg": "left_upper_leg",
    "left_foot": "left_lower_leg", "left_toe": "left_foot",
    "right_upper_leg": "hips", "right_lower_leg": "right_upper_leg",
    "right_foot": "right_lower_leg", "right_toe": "right_foot"
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
        if float(source_motion.get(clip, 0.0)) < MIN_SOURCE_ANIMATION_MOTION_M:
            _failures.append("source_animation_lost_after_runtime_remap clip=%s motion=%.5f" % [clip, float(source_motion.get(clip, 0.0))])

    if not await _setup_native_modifier():
        _finish()
        return

    var results := {}
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
    print("GATE8_NATIVE_RETARGET_AB candidate=01 clips=2 failures=%d source_renamed=%d target_names_unchanged=%s bindings=%d alias_selected=false production_authorized=false" % [_failures.size(), _source_bones_renamed, str(_target_names_unchanged), _resolved_target_mesh_bindings])
    _finish()

func _build_world() -> void:
    _world = Node3D.new()
    root.add_child(_world)
    var we := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.16, 0.18, 0.21, 1.0)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.78, 0.80, 0.84, 1.0)
    env.ambient_light_energy = 1.05
    we.environment = env
    _world.add_child(we)
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
    light.light_energy = 1.25
    light.shadow_enabled = true
    _world.add_child(light)
    _ground = MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(8.0, 8.0)
    _ground.mesh = plane
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.30, 0.31, 0.32, 1.0)
    mat.roughness = 0.92
    _ground.material_override = mat
    _world.add_child(_ground)
    _camera = Camera3D.new()
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
    _world.add_child(_source_instance)
    _world.add_child(_target_instance)
    await process_frame
    _source_skeleton = _find_skeleton(_source_instance)
    _target_skeleton = _find_skeleton(_target_instance)
    _source_player = _find_animation_player(_source_instance)
    if _source_skeleton == null: _failures.append("source_skeleton_missing")
    if _target_skeleton == null: _failures.append("target_skeleton_missing")
    if _source_player == null: _failures.append("source_animation_player_missing_required_clips")
    if not _failures.is_empty(): return false
    for mesh: MeshInstance3D in _find_meshes(_source_instance): mesh.visible = false
    _target_meshes = _find_meshes(_target_instance)
    if _target_meshes.is_empty(): _failures.append("target_meshes_missing")
    for role: String in ROLE_ORDER:
        var pair: Array = ROLE_PAIRS[role]
        if _source_skeleton.find_bone(String(pair[0])) < 0: _failures.append("source_bone_missing=%s" % role)
        if _target_skeleton.find_bone(String(pair[1])) < 0: _failures.append("target_bone_missing=%s" % role)
    return _failures.is_empty()

func _snapshot_target_names() -> Dictionary:
    var out := {}
    for role: String in ROLE_ORDER:
        var name := String((ROLE_PAIRS[role] as Array)[1])
        var idx := _target_skeleton.find_bone(name)
        out[role] = {"index": idx, "name": _target_skeleton.get_bone_name(idx)}
    return out

func _verify_target_names(snapshot: Dictionary) -> void:
    for role: String in ROLE_ORDER:
        var row: Dictionary = snapshot[role]
        var idx := int(row["index"])
        if idx < 0 or idx >= _target_skeleton.get_bone_count() or _target_skeleton.get_bone_name(idx) != StringName(row["name"]):
            _target_names_unchanged = false
            return

func _remap_source_animation_tracks() -> int:
    var count := 0
    for raw_name: StringName in _source_player.get_animation_list():
        var anim := _source_player.get_animation(raw_name)
        if anim == null: continue
        for i: int in range(anim.get_track_count()):
            var before := String(anim.track_get_path(i))
            var after := before
            for role: String in ROLE_ORDER:
                var pair: Array = ROLE_PAIRS[role]
                after = after.replace(":%s" % String(pair[0]), ":%s" % String(pair[1]))
            if after != before:
                anim.track_set_path(i, NodePath(after))
                count += 1
    return count

func _rename_source_bones() -> int:
    var count := 0
    for role: String in ROLE_ORDER:
        var pair: Array = ROLE_PAIRS[role]
        var src := String(pair[0])
        var dst := String(pair[1])
        if _source_skeleton.find_bone(dst) >= 0:
            _failures.append("source_target_name_collision role=%s" % role)
            continue
        var idx := _source_skeleton.find_bone(src)
        if idx < 0:
            _failures.append("source_bone_missing_before_rename role=%s" % role)
            continue
        _source_skeleton.set_bone_name(idx, dst)
        if _source_skeleton.get_bone_name(idx) == StringName(dst): count += 1
    return count

func _measure_source_motion() -> Dictionary:
    var out := {}
    for clip: String in CLIPS:
        var anim_name := _resolve_animation_name(_source_player, clip)
        var anim := _source_player.get_animation(anim_name)
        if anim == null or anim.length <= 0.0:
            out[clip] = 0.0
            continue
        _source_player.play(anim_name)
        _source_player.seek(anim.length * 0.12, true)
        _source_player.advance(0.0)
        _source_skeleton.force_update_all_bone_transforms()
        var a := _source_bone_position("left_foot")
        _source_player.seek(anim.length * 0.48, true)
        _source_player.advance(0.0)
        _source_skeleton.force_update_all_bone_transforms()
        var b := _source_bone_position("left_foot")
        out[clip] = a.distance_to(b)
        _source_player.stop()
    return out

func _setup_native_modifier() -> bool:
    var profile := _build_profile()
    if profile.get_bone_size() != ROLE_ORDER.size():
        _failures.append("native_profile_invalid")
        return false
    _modifier = RetargetModifier3D.new()
    _modifier.set_use_global_pose(false)
    _modifier.set_position_enabled(false)
    _modifier.set_rotation_enabled(true)
    _modifier.set_scale_enabled(false)
    _source_skeleton.add_child(_modifier)
    _target_skeleton.reparent(_modifier, true)
    _modifier.set_profile(profile)
    await process_frame
    if _target_skeleton.get_parent() != _modifier: _failures.append("target_skeleton_not_modifier_child")
    _resolved_target_mesh_bindings = 0
    for mesh: MeshInstance3D in _target_meshes:
        mesh.skeleton = mesh.get_path_to(_target_skeleton)
        if mesh.get_node_or_null(mesh.skeleton) == _target_skeleton: _resolved_target_mesh_bindings += 1
    if _resolved_target_mesh_bindings != _target_meshes.size(): _failures.append("target_mesh_binding_resolution=%d expected=%d" % [_resolved_target_mesh_bindings, _target_meshes.size()])
    var common := 0
    for role: String in ROLE_ORDER:
        var name := String((ROLE_PAIRS[role] as Array)[1])
        if _source_skeleton.find_bone(name) >= 0 and _target_skeleton.find_bone(name) >= 0: common += 1
    if common != ROLE_ORDER.size(): _failures.append("native_common_bone_names=%d" % common)
    return _failures.is_empty()

func _build_profile() -> SkeletonProfile:
    var p := SkeletonProfile.new()
    p.set_bone_size(ROLE_ORDER.size())
    for i: int in range(ROLE_ORDER.size()):
        var role := ROLE_ORDER[i]
        var name := String((ROLE_PAIRS[role] as Array)[1])
        p.set_bone_name(i, name)
        var parent_role := String(PARENT_ROLE.get(role, ""))
        if not parent_role.is_empty(): p.set_bone_parent(i, String((ROLE_PAIRS[parent_role] as Array)[1]))
        p.set_required(i, true)
    p.set_root_bone(String((ROLE_PAIRS["hips"] as Array)[1]))
    p.set_scale_base_bone(String((ROLE_PAIRS["hips"] as Array)[1]))
    return p

func _measure_clip(clip: String) -> Dictionary:
    var anim_name := _resolve_animation_name(_source_player, clip)
    var anim := _source_player.get_animation(anim_name)
    if anim == null or anim.length <= 0.0:
        _failures.append("clip_invalid=%s" % clip)
        return {}
    _reset_target_pose()
    var count := maxi(MINIMUM_SAMPLES, int(ceil(anim.length * SAMPLE_RATE_HZ)))
    var dt := anim.length / float(count)
    var left: Array[Vector3] = []
    var right: Array[Vector3] = []
    var corrections: Array[float] = []
    var torso: Array[float] = []
    for i: int in range(count):
        await _sample_native_pose(anim_name, minf(anim.length - 0.00001, float(i) * dt))
        var l := _target_bone_position("left_foot")
        var r := _target_bone_position("right_foot")
        left.append(l); right.append(r)
        corrections.append(GROUND_CLEARANCE_M - minf(l.y, r.y))
        torso.append(absf(_torso_bend(_source_skeleton) - _torso_bend(_target_skeleton)))
    var raw_ground := INF
    for i: int in range(left.size()): raw_ground = minf(raw_ground, minf(left[i].y, right[i].y))
    var limit := raw_ground + CONTACT_HEIGHT_WINDOW_M
    var ls := _contact_slide(left, limit, dt)
    var rs := _contact_slide(right, limit, dt)
    var contacts := int(ls["samples"]) + int(rs["samples"])
    if contacts <= 0: _failures.append("no_contact_samples clip=%s" % clip)
    var span := _array_max(corrections) - _array_min(corrections)
    var step := _max_adjacent_delta(corrections)
    var torso_mean := _array_mean(torso)
    var torso_peak := _array_max(torso)
    _gate(clip, "ground_correction_span", span, MAX_GROUND_CORRECTION_SPAN_M)
    _gate(clip, "ground_correction_step", step, MAX_GROUND_CORRECTION_STEP_M)
    _gate(clip, "torso_mean_delta", torso_mean, MAX_MEAN_TORSO_DELTA_DEG)
    _gate(clip, "torso_peak_delta", torso_peak, MAX_PEAK_TORSO_DELTA_DEG)
    var frame := await _capture(clip, anim_name, anim.length * 0.35)
    var mean_slide := (float(ls["mean_mps"]) + float(rs["mean_mps"])) * 0.5
    var peak_slide := maxf(float(ls["max_mps"]), float(rs["max_mps"]))
    print("GATE8_NATIVE_RETARGET_CLIP clip=%s samples=%d contacts=%d mean_slide_mps=%.4f peak_slide_mps=%.4f ground_span_m=%.4f ground_step_m=%.4f torso_mean_deg=%.3f torso_peak_deg=%.3f" % [clip, count, contacts, mean_slide, peak_slide, span, step, torso_mean, torso_peak])
    return {"animation_name": anim_name, "duration_s": anim.length, "sample_count": count, "sample_rate_hz_effective": float(count)/anim.length, "raw_ground_y": raw_ground, "ground_correction_min_m": _array_min(corrections), "ground_correction_max_m": _array_max(corrections), "ground_correction_span_m": span, "ground_correction_max_step_m": step, "left_contact_samples": int(ls["samples"]), "right_contact_samples": int(rs["samples"]), "mean_contact_slide_mps": mean_slide, "peak_contact_slide_mps": peak_slide, "mean_torso_bend_delta_deg": torso_mean, "peak_torso_bend_delta_deg": torso_peak, "frame_path": frame, "frame_width": 1280, "frame_height": 720}

func _sample_native_pose(anim_name: String, time_s: float) -> void:
    _source_player.play(anim_name)
    _source_player.pause()
    _source_player.seek(time_s, true)
    _source_player.advance(0.0)
    _source_skeleton.force_update_all_bone_transforms()
    await process_frame
    _source_skeleton.force_update_all_bone_transforms()
    _target_skeleton.force_update_all_bone_transforms()

func _capture(clip: String, anim_name: String, t: float) -> String:
    await _sample_native_pose(anim_name, t)
    var foot_y := minf(_target_bone_position("left_foot").y, _target_bone_position("right_foot").y)
    _ground.global_position.y = _target_skeleton.to_global(Vector3(0, foot_y - GROUND_CLEARANCE_M, 0)).y
    var pelvis := _target_skeleton.to_global(_target_bone_position("hips"))
    var head := _target_skeleton.to_global(_target_bone_position("head"))
    var center := (pelvis + head) * 0.5
    _camera.look_at_from_position(center + Vector3(2.9, 0.45, 4.15), center, Vector3.UP)
    await process_frame; await process_frame
    RenderingServer.force_draw(false)
    await process_frame
    var image := root.get_texture().get_image()
    var path := "res://gate8_variant01_native_%s.png" % clip.to_lower().replace("_", "-")
    if image == null or image.is_empty() or image.get_width() != 1280 or image.get_height() != 720:
        _failures.append("capture_invalid=%s" % clip)
        return ""
    if image.save_png(path) != OK: _failures.append("capture_save_failed=%s" % clip)
    return path

func _reset_target_pose() -> void:
    for i: int in range(_target_skeleton.get_bone_count()): _target_skeleton.reset_bone_pose(i)
    _target_skeleton.force_update_all_bone_transforms()

func _source_bone_position(role: String) -> Vector3:
    var i := _source_skeleton.find_bone(String((ROLE_PAIRS[role] as Array)[1]))
    return Vector3.ZERO if i < 0 else _source_skeleton.get_bone_global_pose(i).origin

func _target_bone_position(role: String) -> Vector3:
    var i := _target_skeleton.find_bone(String((ROLE_PAIRS[role] as Array)[1]))
    return Vector3.ZERO if i < 0 else _target_skeleton.get_bone_global_pose(i).origin

func _torso_bend(s: Skeleton3D) -> float:
    var a := s.find_bone(String((ROLE_PAIRS["spine"] as Array)[1]))
    var b := s.find_bone(String((ROLE_PAIRS["chest"] as Array)[1]))
    var c := s.find_bone(String((ROLE_PAIRS["neck"] as Array)[1]))
    if a < 0 or b < 0 or c < 0: return 180.0
    var ab := s.get_bone_global_pose(b).origin - s.get_bone_global_pose(a).origin
    var bc := s.get_bone_global_pose(c).origin - s.get_bone_global_pose(b).origin
    if ab.length_squared() < 0.000001 or bc.length_squared() < 0.000001: return 180.0
    return rad_to_deg(ab.normalized().angle_to(bc.normalized()))

func _contact_slide(pos: Array[Vector3], limit: float, dt: float) -> Dictionary:
    var speeds: Array[float] = []
    for i: int in range(1, pos.size()):
        if pos[i-1].y > limit or pos[i].y > limit: continue
        speeds.append(Vector2(pos[i].x-pos[i-1].x, pos[i].z-pos[i-1].z).length()/maxf(dt,0.000001))
    return {"samples": speeds.size(), "mean_mps": _array_mean(speeds), "max_mps": _array_max(speeds)}

func _find_skeleton(n: Node) -> Skeleton3D:
    if n is Skeleton3D: return n as Skeleton3D
    for c: Node in n.get_children():
        var r := _find_skeleton(c)
        if r != null: return r
    return null

func _find_animation_player(n: Node) -> AnimationPlayer:
    if n is AnimationPlayer:
        var p := n as AnimationPlayer
        var ok := true
        for clip: String in CLIPS:
            if _resolve_animation_name(p, clip).is_empty(): ok = false
        if ok: return p
    for c: Node in n.get_children():
        var r := _find_animation_player(c)
        if r != null: return r
    return null

func _find_meshes(n: Node) -> Array[MeshInstance3D]:
    var out: Array[MeshInstance3D] = []
    if n is MeshInstance3D: out.append(n as MeshInstance3D)
    for c: Node in n.get_children(): out.append_array(_find_meshes(c))
    return out

func _resolve_animation_name(p: AnimationPlayer, token: String) -> String:
    for raw: StringName in p.get_animation_list():
        var n := String(raw)
        if n == token or n.ends_with("/%s" % token): return n
    return ""

func _gate(clip: String, key: String, value: float, limit: float) -> void:
    if value > limit: _failures.append("%s clip=%s value=%.4f limit=%.4f" % [key, clip, value, limit])

func _array_mean(v: Array[float]) -> float:
    if v.is_empty(): return 0.0
    var t := 0.0
    for x: float in v: t += x
    return t/float(v.size())

func _array_min(v: Array[float]) -> float:
    if v.is_empty(): return 0.0
    var r := INF
    for x: float in v: r = minf(r,x)
    return r

func _array_max(v: Array[float]) -> float:
    if v.is_empty(): return 0.0
    var r := -INF
    for x: float in v: r = maxf(r,x)
    return r

func _max_adjacent_delta(v: Array[float]) -> float:
    var r := 0.0
    for i: int in range(1,v.size()): r = maxf(r,absf(v[i]-v[i-1]))
    return r

func _write_result(result: Dictionary) -> void:
    var f := FileAccess.open("res://gate8_variant01_native_retarget_ab_result.json", FileAccess.WRITE)
    if f == null:
        _failures.append("result_file_open_failed")
        return
    f.store_string(JSON.stringify(result,"  "))
    f.close()

func _finish() -> void:
    if _failures.is_empty():
        print("GATE8_NATIVE_RETARGET_AB_OK candidate=01 clips=Jog_Fwd,Sprint alias_selected=false production_authorized=false")
        quit(0)
        return
    for failure: String in _failures: push_error("GATE8_NATIVE_RETARGET_AB_FAIL %s" % failure)
    quit(1)
