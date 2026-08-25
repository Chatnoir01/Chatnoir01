extends SceneTree

const REQUIRED_SEMANTICS := ["idle", "walk", "run"]
const REQUIRED_ROLES := ["hips", "left_upper_arm", "right_upper_arm", "left_foot", "right_foot"]
const SOURCE_SCENES := {
    "idle": "res://kaykit/Idle.fbx",
    "walk": "res://kaykit/Walk.fbx",
    "run": "res://kaykit/Run.fbx",
}
const EXPECTED_NON_HUMANOID_BONES := [
    "Body",
    "Head",
    "armLeft",
    "handSlotLeft",
    "armRight",
    "handSlotRight",
]
const MECHANICAL_STATE := "BLOCKED_NON_HUMANOID_SKELETON"

var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var source_scenes: Dictionary = {}
    var signatures: Array[Array] = []

    for semantic in REQUIRED_SEMANTICS:
        var path := String(SOURCE_SCENES[semantic])
        var packed := load(path) as PackedScene
        if packed == null:
            failures.append("missing_or_unimported_scene:%s:%s" % [semantic, path])
            continue
        var root := packed.instantiate()
        get_root().add_child(root)
        var skeleton := _find_skeleton(root)
        var player := _find_animation_player(root)
        if skeleton == null:
            failures.append("missing_skeleton:%s" % semantic)
            root.queue_free()
            continue
        if player == null:
            failures.append("missing_animation_player:%s" % semantic)
            root.queue_free()
            continue

        var bone_names := _bone_names(skeleton)
        var roles := _resolve_roles(skeleton)
        var missing_roles: Array[String] = []
        for role in REQUIRED_ROLES:
            if int(roles.get(role, -1)) < 0:
                missing_roles.append(role)
        var usable_animations := _usable_animation_names(player)
        signatures.append(bone_names)
        source_scenes[semantic] = {
            "path": path,
            "skeleton_bones": skeleton.get_bone_count(),
            "bone_names": bone_names,
            "roles": roles,
            "missing_roles": missing_roles,
            "usable_animations": usable_animations,
        }

        if bone_names != EXPECTED_NON_HUMANOID_BONES:
            failures.append("unexpected_bone_signature:%s:%s" % [semantic, ",".join(bone_names)])
        if missing_roles != REQUIRED_ROLES:
            failures.append("unexpected_required_role_resolution:%s:%s" % [semantic, ",".join(missing_roles)])
        if usable_animations.is_empty():
            failures.append("no_usable_animation:%s" % semantic)
        root.queue_free()

    if source_scenes.size() != REQUIRED_SEMANTICS.size():
        failures.append("incomplete_scene_characterization:%d_of_%d" % [source_scenes.size(), REQUIRED_SEMANTICS.size()])

    var signatures_consistent := signatures.size() == REQUIRED_SEMANTICS.size()
    if signatures_consistent:
        for signature in signatures:
            if signature != EXPECTED_NON_HUMANOID_BONES:
                signatures_consistent = false
                break
    if not signatures_consistent:
        failures.append("single_animation_fbx_skeleton_signatures_not_consistent")

    var result := {
        "schema": "grand-bruxelles-gate8-kaykit-locomotion-preflight-v3",
        "godot_version": Engine.get_version_info().get("string", ""),
        "source_mode": "single_animation_fbx",
        "source_scenes": source_scenes,
        "mechanical_state": MECHANICAL_STATE,
        "target_humanoid_retarget_compatible": false,
        "observed_skeleton_bones": EXPECTED_NON_HUMANOID_BONES.size(),
        "observed_bone_names": EXPECTED_NON_HUMANOID_BONES,
        "required_humanoid_roles": REQUIRED_ROLES,
        "missing_required_humanoid_roles": REQUIRED_ROLES,
        "skeleton_signature_consistent": signatures_consistent,
        "measurement_skipped_reason": "source skeleton has no hips or foot bones; planted-feet and humanoid retarget metrics would be fabricated",
        "metrics": {},
        "production_authorized": false,
        "activation_ready": false,
        "adoption_ready": false,
        "walk_alias_selected": "",
        "run_alias_selected": "",
        "failures": failures,
    }
    _finish(result)

func _usable_animation_names(player: AnimationPlayer) -> Array[String]:
    var names: Array[String] = []
    for raw_name in player.get_animation_list():
        var name := String(raw_name)
        if name.to_lower() != "reset":
            names.append(name)
    return names

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
        print("GATE8_KAYKIT_LOCOMOTION_BLOCK_CONFIRMED state=%s bones=%d" % [MECHANICAL_STATE, EXPECTED_NON_HUMANOID_BONES.size()])
        quit(0)
        return
    for failure in failures:
        push_error(failure)
    print("GATE8_KAYKIT_LOCOMOTION_CHARACTERIZATION_FAILED failures=%d" % failures.size())
    quit(1)
