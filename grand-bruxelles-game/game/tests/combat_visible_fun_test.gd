extends SceneTree

const ARSENAL := preload("res://game/scripts/player_combat_arsenal_hardened_runtime.gd")
const POSE := preload("res://game/scripts/combat_authored_pose_runtime.gd")
const FX := preload("res://game/scripts/combat_shot_fx_runtime.gd")

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    if ARSENAL.MELEE_MOVES_V2.size() < 10:
        _fail("combat repertoire must expose at least 10 distinct moves")
        return
    var ids: Dictionary = {}
    for move: Dictionary in ARSENAL.MELEE_MOVES_V2:
        var move_id := StringName(move.get("id", &""))
        if move_id == &"" or ids.has(move_id):
            _fail("combat repertoire contains an empty or duplicate move id")
            return
        ids[move_id] = true
        if float(move.get("active_s", 0.0)) <= 0.0 or float(move.get("recover_s", 0.0)) <= 0.0:
            _fail("combat move timing must include active and recovery phases")
            return

    for required: StringName in [&"jab_left", &"cross_right", &"hook_left", &"hook_right", &"uppercut_right", &"body_hook_left", &"front_kick_right", &"low_kick_left", &"push_kick_right", &"elbow_right"]:
        if not ids.has(required):
            _fail("missing required visible move %s" % required)
            return
        if POSE.melee_pose_profile(required).is_empty():
            _fail("missing authored skeleton pose for %s" % required)
            return

    if POSE.weapon_pose_profile(&"bx9", true).is_empty() or POSE.weapon_pose_profile(&"cbr4", true).is_empty() or POSE.weapon_pose_profile(&"sct8", true).is_empty():
        _fail("all fictional weapons need authored upper-body poses")
        return
    if FX.muzzle_local(&"bx9").z >= 0.0 or FX.muzzle_local(&"cbr4").z >= 0.0 or FX.muzzle_local(&"sct8").z >= 0.0:
        _fail("muzzle sockets must be forward of the hand grip")
        return
    if FX.visual_range_m(&"cbr4") <= FX.visual_range_m(&"sct8"):
        _fail("visual tracer ranges drifted")
        return

    var locomotion_source := _read("res://game/scripts/authored_player_locomotion_runtime.gd")
    var pose_source := _read("res://game/scripts/combat_authored_pose_runtime.gd")
    var fx_source := _read("res://game/scripts/combat_shot_fx_runtime.gd")
    var arsenal_source := _read("res://game/scripts/player_combat_arsenal_hardened_runtime.gd")
    var project_source := _read("res://project.godot")
    if [locomotion_source, pose_source, fx_source, arsenal_source, project_source].any(func(value: String) -> bool: return value.is_empty()):
        _fail("source fixture missing")
        return

    for token: String in ["combat_action_lock_until_ms", "_action_locked()"]:
        if locomotion_source.find(token) < 0:
            _fail("locomotion must respect combat action lock: %s" % token)
            return
    for token: String in ["Skeleton3D", "set_bone_global_pose_override", "right_upper_arm", "left_forearm", "right_thigh", "request_melee_pose"]:
        if pose_source.find(token) < 0:
            _fail("authored combat pose layer missing token %s" % token)
            return
    for token: String in ["CombatMuzzleFlash", "CombatTracer_", "CombatImpactFx_", "CombatCasing_", "OmniLight3D"]:
        if fx_source.find(token) < 0:
            _fail("shot FX layer missing token %s" % token)
            return
    for token: String in ["MELEE_MOVES_V2", "request_melee_pose", "request_shot_pose", "combat_melee_anim_started_ms"]:
        if arsenal_source.find(token) < 0:
            _fail("arsenal hardening missing visible combat hook %s" % token)
            return
    for token: String in ["CombatAuthoredPoseRuntime=", "CombatWeaponHandOrientationRuntime=", "CombatShotFxRuntime="]:
        if project_source.find(token) < 0:
            _fail("project autoload missing %s" % token)
            return

    print("COMBAT_VISIBLE_FUN_OK: hand_grip=green authored_bones=green moves=10 action_lock=green muzzle=green tracer=green impacts=green casings=green recoil_pose=green")
    quit(0)

func _read(path: String) -> String:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return ""
    var text := file.get_as_text()
    file.close()
    return text

func _fail(message: String) -> void:
    push_error("COMBAT_VISIBLE_FUN_FAIL: %s" % message)
    quit(1)
