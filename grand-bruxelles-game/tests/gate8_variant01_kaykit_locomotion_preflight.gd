extends SceneTree

const SAMPLE_HZ := 120.0
const REQUIRED := ["idle", "walk", "run"]
var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var scenes: Array[String] = []
    _collect_scenes("res://kaykit", scenes)
    if scenes.is_empty():
        failures.append("no_kaykit_gltf_glb_imported")
        return _finish({})
    var chosen: Dictionary = {}
    for path in scenes:
        var packed := load(path) as PackedScene
        if packed == null:
            continue
        var root := packed.instantiate()
        get_root().add_child(root)
        var player := _find_animation_player(root)
        var skeleton := _find_skeleton(root)
        if player != null and skeleton != null:
            var clips := _resolve_required_clips(player)
            if clips.size() == 3:
                chosen = {"path": path, "root": root, "player": player, "skeleton": skeleton, "clips": clips}
                break
        root.queue_free()
    if chosen.is_empty():
        failures.append("no_scene_with_exact_idle_walk_run_and_skeleton")
        return _finish({"scene_count": scenes.size()})

    var skeleton: Skeleton3D = chosen.skeleton
    var roles := _resolve_roles(skeleton)
    for role in ["left_upper_arm", "right_upper_arm", "left_foot", "right_foot", "hips"]:
        if int(roles.get(role, -1)) < 0:
            failures.append("missing_role:" + role)
    if not failures.is_empty():
        return _finish({"scene": chosen.path, "bone_names": _bone_names(skeleton)})

    var player: AnimationPlayer = chosen.player
    var metrics: Dictionary = {}
    for semantic in REQUIRED:
        metrics[semantic] = _measure_clip(player, skeleton, String(chosen.clips[semantic]), roles)
    var result := {
        "schema": "grand-bruxelles-gate8-kaykit-locomotion-preflight-v1",
        "godot_version": Engine.get_version_info().get("string", ""),
        "scene": chosen.path,
        "scene_count": scenes.size(),
        "skeleton_bones": skeleton.get_bone_count(),
        "roles": roles,
        "clips": chosen.clips,
        "metrics": metrics,
        "production_authorized": false,
        "activation_ready": false,
        "adoption_ready": false,
        "walk_alias_selected": "",
        "run_alias_selected": "",
        "failures": failures,
    }
    _finish(result)

func _measure_clip(player: AnimationPlayer, skeleton: Skeleton3D, clip: String, roles: Dictionary) -> Dictionary:
    var anim := player.get_animation(clip)
    if anim == null or anim.length <= 0.0:
        failures.append("invalid_clip:" + clip)
        return {}
    player.play(clip)
    player.seek(0.0, true)
    player.advance(0.0)
    var left_arm_rest := skeleton.get_bone_global_rest(int(roles.left_upper_arm)).basis.get_rotation_quaternion()
    var right_arm_rest := skeleton.get_bone_global_rest(int(roles.right_upper_arm)).basis.get_rotation_quaternion()
    var sample_count := maxi(2, int(ceil(anim.length * SAMPLE_HZ)) + 1)
    var max_left_arm := 0.0
    var max_right_arm := 0.0
    var min_foot_y := INF
    var max_foot_y := -INF
    var hips_start := Vector3.ZERO
    var hips_end := Vector3.ZERO
    var prev_left := Vector3.ZERO
    var prev_right := Vector3.ZERO
    var left_slide := 0.0
    var right_slide := 0.0
    var contact_samples := 0
    for i in range(sample_count):
        var t := minf(anim.length, float(i) / SAMPLE_HZ)
        player.seek(t, true)
        player.advance(0.0)
        var l_arm := skeleton.get_bone_global_pose(int(roles.left_upper_arm)).basis.get_rotation_quaternion()
        var r_arm := skeleton.get_bone_global_pose(int(roles.right_upper_arm)).basis.get_rotation_quaternion()
        max_left_arm = maxf(max_left_arm, rad_to_deg(left_arm_rest.angle_to(l_arm)))
        max_right_arm = maxf(max_right_arm, rad_to_deg(right_arm_rest.angle_to(r_arm)))
        var lf := skeleton.get_bone_global_pose(int(roles.left_foot)).origin
        var rf := skeleton.get_bone_global_pose(int(roles.right_foot)).origin
        var hips := skeleton.get_bone_global_pose(int(roles.hips)).origin
        min_foot_y = minf(min_foot_y, minf(lf.y, rf.y))
        max_foot_y = maxf(max_foot_y, maxf(lf.y, rf.y))
        if i == 0:
            hips_start = hips
            prev_left = lf
            prev_right = rf
        elif i == sample_count - 1:
            hips_end = hips
        var floor_y := minf(lf.y, rf.y)
        var contact_epsilon := 0.025
        if lf.y <= floor_y + contact_epsilon:
            left_slide += Vector2(lf.x - prev_left.x, lf.z - prev_left.z).length()
            contact_samples += 1
        if rf.y <= floor_y + contact_epsilon:
            right_slide += Vector2(rf.x - prev_right.x, rf.z - prev_right.z).length()
            contact_samples += 1
        prev_left = lf
        prev_right = rf
    var planar_hips := Vector2(hips_end.x - hips_start.x, hips_end.z - hips_start.z).length()
    var duration := float(anim.length)
    return {
        "animation": clip,
        "duration_s": duration,
        "samples": sample_count,
        "max_left_upper_arm_delta_deg": max_left_arm,
        "max_right_upper_arm_delta_deg": max_right_arm,
        "max_upper_arm_delta_deg": maxf(max_left_arm, max_right_arm),
        "foot_vertical_span_m": max_foot_y - min_foot_y,
        "hips_planar_displacement_m": planar_hips,
        "hips_planar_speed_mps": planar_hips / duration,
        "contact_samples": contact_samples,
        "contact_slide_path_m": left_slide + right_slide,
        "contact_slide_mean_mps": (left_slide + right_slide) * SAMPLE_HZ / maxf(1.0, float(contact_samples)),
    }

func _resolve_required_clips(player: AnimationPlayer) -> Dictionary:
    var out := {}
    for name in player.get_animation_list():
        var tokens := _tokens(String(name))
        for semantic in REQUIRED:
            if semantic in tokens and not out.has(semantic):
                out[semantic] = String(name)
    return out

func _tokens(text: String) -> Array[String]:
    var normalized := text.to_lower()
    for sep in ["-", " ", ".", "/", ":"]:
        normalized = normalized.replace(sep, "_")
    var out: Array[String] = []
    for token in normalized.split("_", false):
        out.append(String(token))
    return out

func _resolve_roles(skeleton: Skeleton3D) -> Dictionary:
    var out := {"hips": -1, "left_upper_arm": -1, "right_upper_arm": -1, "left_foot": -1, "right_foot": -1}
    for i in range(skeleton.get_bone_count()):
        var n := skeleton.get_bone_name(i).to_lower().replace("-", "_").replace(".", "_")
        if out.hips < 0 and ("hips" in n or "pelvis" in n): out.hips = i
        if out.left_upper_arm < 0 and (("upperarm" in n or "upper_arm" in n) and ("left" in n or n.ends_with("_l") or n.ends_with("l"))): out.left_upper_arm = i
        if out.right_upper_arm < 0 and (("upperarm" in n or "upper_arm" in n) and ("right" in n or n.ends_with("_r") or n.ends_with("r"))): out.right_upper_arm = i
        if out.left_foot < 0 and "foot" in n and ("left" in n or n.ends_with("_l") or n.ends_with("l")): out.left_foot = i
        if out.right_foot < 0 and "foot" in n and ("right" in n or n.ends_with("_r") or n.ends_with("r")): out.right_foot = i
    return out

func _bone_names(skeleton: Skeleton3D) -> Array[String]:
    var names: Array[String] = []
    for i in range(skeleton.get_bone_count()): names.append(skeleton.get_bone_name(i))
    return names

func _find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer: return node
    for child in node.get_children():
        var found := _find_animation_player(child)
        if found != null: return found
    return null

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D: return node
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found != null: return found
    return null

func _collect_scenes(path: String, out: Array[String]) -> void:
    var dir := DirAccess.open(path)
    if dir == null: return
    dir.list_dir_begin()
    while true:
        var name := dir.get_next()
        if name == "": break
        if name.begins_with("."): continue
        var child := path.path_join(name)
        if dir.current_is_dir(): _collect_scenes(child, out)
        elif name.to_lower().ends_with(".glb") or name.to_lower().ends_with(".gltf"): out.append(child)
    dir.list_dir_end()

func _finish(result: Dictionary) -> void:
    result["failures"] = failures
    var path := "/tmp/gate8-kaykit-locomotion-preflight.json"
    FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
    if failures.is_empty():
        print("GATE8_KAYKIT_LOCOMOTION_PREFLIGHT_OK")
        quit(0)
    for failure in failures: push_error(failure)
    print("GATE8_KAYKIT_LOCOMOTION_PREFLIGHT_BLOCKED failures=%d" % failures.size())
    quit(1)
