extends SceneTree

const SAMPLE_HZ := 120.0
const REQUIRED_SEMANTICS := ["idle", "walk", "run"]
const REQUIRED_ROLES := ["hips", "left_upper_arm", "right_upper_arm", "left_foot", "right_foot"]
const SOURCE_SCENES := {
    "idle": "res://kaykit/Idle.fbx",
    "walk": "res://kaykit/Walk.fbx",
    "run": "res://kaykit/Run.fbx",
}
const EXCLUDED_DECOY_CONTAINER := "KayKit_AnimatedCharacter_v1.2.glb"

var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var metrics: Dictionary = {}
    var source_scenes: Dictionary = {}
    var expected_bone_names: Array[String] = []
    var skeleton_signature_consistent := true

    for semantic in REQUIRED_SEMANTICS:
        var path := String(SOURCE_SCENES[semantic])
        var packed := load(path) as PackedScene
        if packed == null:
            failures.append("missing_or_unimported_scene:%s:%s" % [semantic, path])
            continue

        var root := packed.instantiate()
        get_root().add_child(root)
        var player := _find_animation_player(root)
        var skeleton := _find_skeleton(root)
        if player == null:
            failures.append("missing_animation_player:%s" % semantic)
            root.queue_free()
            continue
        if skeleton == null:
            failures.append("missing_skeleton:%s" % semantic)
            root.queue_free()
            continue

        var roles := _resolve_roles(skeleton)
        var missing_roles: Array[String] = []
        for role in REQUIRED_ROLES:
            if int(roles.get(role, -1)) < 0:
                missing_roles.append(role)
        if not missing_roles.is_empty():
            failures.append("missing_roles:%s:%s" % [semantic, ",".join(missing_roles)])
            source_scenes[semantic] = {
                "path": path,
                "skeleton_bones": skeleton.get_bone_count(),
                "bone_names": _bone_names(skeleton),
                "missing_roles": missing_roles,
            }
            root.queue_free()
            continue

        var resolved := _resolve_animation(player, semantic)
        var animation_name := String(resolved.get("name", ""))
        if animation_name.is_empty():
            root.queue_free()
            continue

        var bone_names := _bone_names(skeleton)
        if expected_bone_names.is_empty():
            expected_bone_names = bone_names.duplicate()
        elif bone_names != expected_bone_names:
            skeleton_signature_consistent = false
            failures.append("skeleton_signature_mismatch:%s" % semantic)

        source_scenes[semantic] = {
            "path": path,
            "animation": animation_name,
            "animation_resolution": String(resolved.get("mode", "")),
            "skeleton_bones": skeleton.get_bone_count(),
            "roles": roles,
        }
        metrics[semantic] = _measure_clip(player, skeleton, animation_name, roles)
        root.queue_free()

    if metrics.size() != REQUIRED_SEMANTICS.size():
        failures.append("incomplete_metrics:%d_of_%d" % [metrics.size(), REQUIRED_SEMANTICS.size()])

    var result := {
        "schema": "grand-bruxelles-gate8-kaykit-locomotion-preflight-v2",
        "godot_version": Engine.get_version_info().get("string", ""),
        "source_mode": "single_animation_fbx",
        "source_scenes": source_scenes,
        "excluded_decoy_container": EXCLUDED_DECOY_CONTAINER,
        "skeleton_signature_consistent": skeleton_signature_consistent,
        "skeleton_bones": expected_bone_names.size(),
        "bone_names": expected_bone_names,
        "metrics": metrics,
        "production_authorized": false,
        "activation_ready": false,
        "adoption_ready": false,
        "walk_alias_selected": "",
        "run_alias_selected": "",
        "failures": failures,
    }
    _finish(result)

func _resolve_animation(player: AnimationPlayer, semantic: String) -> Dictionary:
    var exact: Array[String] = []
    var usable: Array[String] = []
    for raw_name in player.get_animation_list():
        var name := String(raw_name)
        if name.to_lower() == "reset":
            continue
        usable.append(name)
        if semantic in _tokens(name):
            exact.append(name)
    if exact.size() == 1:
        return {"name": exact[0], "mode": "exact_token"}
    if exact.size() > 1:
        failures.append("ambiguous_exact_animation:%s:%s" % [semantic, ",".join(exact)])
        return {}
    if usable.size() == 1:
        return {"name": usable[0], "mode": "single_animation_scene"}
    failures.append("animation_not_resolved:%s:usable=%d" % [semantic, usable.size()])
    return {}

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
        var left_arm_pose := skeleton.get_bone_global_pose(int(roles.left_upper_arm)).basis.get_rotation_quaternion()
        var right_arm_pose := skeleton.get_bone_global_pose(int(roles.right_upper_arm)).basis.get_rotation_quaternion()
        max_left_arm = maxf(max_left_arm, rad_to_deg(left_arm_rest.angle_to(left_arm_pose)))
        max_right_arm = maxf(max_right_arm, rad_to_deg(right_arm_rest.angle_to(right_arm_pose)))
        var left_foot := skeleton.get_bone_global_pose(int(roles.left_foot)).origin
        var right_foot := skeleton.get_bone_global_pose(int(roles.right_foot)).origin
        var hips := skeleton.get_bone_global_pose(int(roles.hips)).origin
        min_foot_y = minf(min_foot_y, minf(left_foot.y, right_foot.y))
        max_foot_y = maxf(max_foot_y, maxf(left_foot.y, right_foot.y))
        if i == 0:
            hips_start = hips
            prev_left = left_foot
            prev_right = right_foot
        elif i == sample_count - 1:
            hips_end = hips
        var floor_y := minf(left_foot.y, right_foot.y)
        var contact_epsilon := 0.025
        if i > 0 and left_foot.y <= floor_y + contact_epsilon:
            left_slide += Vector2(left_foot.x - prev_left.x, left_foot.z - prev_left.z).length()
            contact_samples += 1
        if i > 0 and right_foot.y <= floor_y + contact_epsilon:
            right_slide += Vector2(right_foot.x - prev_right.x, right_foot.z - prev_right.z).length()
            contact_samples += 1
        prev_left = left_foot
        prev_right = right_foot
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

func _tokens(text: String) -> Array[String]:
    var normalized := text.to_lower()
    for separator in ["-", " ", ".", "/", ":"]:
        normalized = normalized.replace(separator, "_")
    var out: Array[String] = []
    for token in normalized.split("_", false):
        out.append(String(token))
    return out

func _normalized_bone_name(text: String) -> String:
    var normalized := text.to_lower()
    for separator in ["-", " ", ".", "/", ":"]:
        normalized = normalized.replace(separator, "_")
    return normalized

func _is_left(name: String) -> bool:
    return "left" in name or name.ends_with("_l") or name.begins_with("l_")

func _is_right(name: String) -> bool:
    return "right" in name or name.ends_with("_r") or name.begins_with("r_")

func _resolve_roles(skeleton: Skeleton3D) -> Dictionary:
    var out := {"hips": -1, "left_upper_arm": -1, "right_upper_arm": -1, "left_foot": -1, "right_foot": -1}
    for i in range(skeleton.get_bone_count()):
        var name := _normalized_bone_name(skeleton.get_bone_name(i))
        if int(out.hips) < 0 and ("hips" in name or "pelvis" in name):
            out.hips = i
        var is_upper_arm := "upperarm" in name or "upper_arm" in name
        if int(out.left_upper_arm) < 0 and is_upper_arm and _is_left(name):
            out.left_upper_arm = i
        if int(out.right_upper_arm) < 0 and is_upper_arm and _is_right(name):
            out.right_upper_arm = i
        if int(out.left_foot) < 0 and "foot" in name and _is_left(name):
            out.left_foot = i
        if int(out.right_foot) < 0 and "foot" in name and _is_right(name):
            out.right_foot = i
    return out

func _bone_names(skeleton: Skeleton3D) -> Array[String]:
    var names: Array[String] = []
    for i in range(skeleton.get_bone_count()):
        names.append(skeleton.get_bone_name(i))
    return names

func _find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node
    for child in node.get_children():
        var found := _find_animation_player(child)
        if found != null:
            return found
    return null

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null

func _finish(result: Dictionary) -> void:
    result["failures"] = failures
    var path := "/tmp/gate8-kaykit-locomotion-preflight.json"
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        push_error("cannot_write_result")
        quit(1)
        return
    file.store_string(JSON.stringify(result, "  "))
    file.close()
    if failures.is_empty():
        print("GATE8_KAYKIT_LOCOMOTION_PREFLIGHT_OK source_mode=single_animation_fbx")
        quit(0)
        return
    for failure in failures:
        push_error(failure)
    print("GATE8_KAYKIT_LOCOMOTION_PREFLIGHT_BLOCKED failures=%d" % failures.size())
    quit(1)
