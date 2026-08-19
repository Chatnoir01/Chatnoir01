extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const SAFE_POSE_SOURCE := "res://game/scripts/combat_authored_pose_runtime.gd"
const WEAPONS: Array[StringName] = [&"bx9", &"cbr4", &"sct8"]
const MAX_BONE_SHIFT_M := 0.08

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("COMBAT_RIG_SAFETY_WITNESS_FAIL: %s" % message)
    quit(1)

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D
    for child: Node in node.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null

func _freeze_animation_nodes(node: Node) -> void:
    if node is AnimationPlayer:
        var player := node as AnimationPlayer
        player.speed_scale = 0.0
        player.pause()
    elif node is AnimationTree:
        (node as AnimationTree).active = false
    for child: Node in node.get_children():
        _freeze_animation_nodes(child)

func _snapshot_bones(skeleton: Skeleton3D) -> Array[Vector3]:
    var points: Array[Vector3] = []
    for bone_index: int in range(skeleton.get_bone_count()):
        points.append(skeleton.get_bone_global_pose(bone_index).origin)
    return points

func _max_shift(skeleton: Skeleton3D, baseline: Array[Vector3]) -> Dictionary:
    var max_shift := 0.0
    var worst_bone := ""
    for bone_index: int in range(mini(skeleton.get_bone_count(), baseline.size())):
        var shift := skeleton.get_bone_global_pose(bone_index).origin.distance_to(baseline[bone_index])
        if shift > max_shift:
            max_shift = shift
            worst_bone = String(skeleton.get_bone_name(bone_index))
    return {"max_shift_m": max_shift, "worst_bone": worst_bone}

func _wait_for_weapon_lock(player: CharacterBody3D, weapon_id: StringName) -> bool:
    for _attempt: int in range(180):
        await process_frame
        if StringName(player.get_meta("combat_weapon_id", &"")) != weapon_id:
            continue
        if bool(player.get_meta("combat_weapon_grip_locked", false)) and bool(player.get_meta("combat_weapon_orientation_locked", false)):
            return true
    return false

func _run() -> void:
    var safe_pose_runtime := root.get_node_or_null("CombatAuthoredPoseRuntime")
    if safe_pose_runtime == null:
        _fail("rig-safe CombatAuthoredPoseRuntime must remain active")
        return
    var pose_source := FileAccess.get_file_as_string(SAFE_POSE_SOURCE)
    if pose_source.is_empty() or pose_source.find("set_bone_global_pose_override") >= 0:
        _fail("combat authored action runtime contains a direct global bone override")
        return
    if pose_source.find("AnimationPlayer") < 0 or pose_source.find("combat_authored_animation_v3_safe") < 0:
        _fail("combat authored action runtime is not the rig-safe AnimationPlayer implementation")
        return

    var error := change_scene_to_file(MAIN_SCENE)
    if error != OK:
        _fail("main scene load failed: %s" % error)
        return

    var main: Node = null
    var player: CharacterBody3D = null
    for _attempt: int in range(300):
        await process_frame
        main = current_scene
        if main != null:
            player = main.get_node_or_null("Player") as CharacterBody3D
            if player != null:
                break
    if main == null or player == null:
        _fail("production main/player unavailable")
        return

    var arsenal := root.get_node_or_null("PlayerCombatArsenalRuntime")
    if arsenal == null or not arsenal.has_method("equip_weapon"):
        _fail("production combat arsenal unavailable")
        return

    var visual := player.get_node_or_null("VisualUpgrade")
    if visual == null:
        _fail("player VisualUpgrade unavailable")
        return

    var skeleton: Skeleton3D = null
    for _attempt: int in range(300):
        await process_frame
        skeleton = _find_skeleton(visual)
        if skeleton != null and skeleton.get_bone_count() > 0:
            break
    if skeleton == null or skeleton.get_bone_count() == 0:
        _fail("authored player skeleton unavailable")
        return

    player.velocity = Vector3.ZERO
    player.set_physics_process(false)
    var locomotion := root.get_node_or_null("AuthoredPlayerLocomotionRuntime")
    if locomotion != null:
        locomotion.set_process(false)
    safe_pose_runtime.set_process(false)
    _freeze_animation_nodes(visual)

    arsenal.call("equip_weapon", player, &"")
    for _frame: int in range(8):
        await process_frame
    var baseline := _snapshot_bones(skeleton)
    if baseline.size() < 8:
        _fail("not enough authored bones for deformation witness: %d" % baseline.size())
        return

    var report: Dictionary = {}
    for weapon_id: StringName in WEAPONS:
        if not bool(arsenal.call("equip_weapon", player, weapon_id)):
            _fail("equip failed for %s" % weapon_id)
            return
        if not await _wait_for_weapon_lock(player, weapon_id):
            _fail("weapon never hand-locked for %s" % weapon_id)
            return
        for _frame: int in range(8):
            await process_frame
        var shift := _max_shift(skeleton, baseline)
        var max_shift := float(shift.get("max_shift_m", 999.0))
        report[String(weapon_id)] = shift
        if max_shift > MAX_BONE_SHIFT_M:
            _fail("%s deformed authored rig: worst_bone=%s shift=%.4fm > %.4fm" % [weapon_id, String(shift.get("worst_bone", "?")), max_shift, MAX_BONE_SHIFT_M])
            return

    print("COMBAT_RIG_SAFETY_WITNESS_OK: authored_skeleton=true safe_pose_autoload=true direct_bone_override=false max_bone_shift_m=%.3f report=%s" % [MAX_BONE_SHIFT_M, JSON.stringify(report)])
    quit(0)