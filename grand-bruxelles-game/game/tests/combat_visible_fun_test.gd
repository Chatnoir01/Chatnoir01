extends SceneTree

const ARSENAL := preload("res://game/scripts/player_combat_arsenal_hardened_runtime.gd")
const POSE := preload("res://game/scripts/combat_authored_pose_runtime.gd")
const FX := preload("res://game/scripts/combat_shot_fx_runtime.gd")
const REAL_PLAYER := "res://assets/characters/player_character.glb"

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

    # Safety regression: the previous implementation independently overrode
    # parent and child global bone poses and produced severe visible contortion.
    if pose_source.find("set_bone_global_pose_override") >= 0:
        _fail("combat pose layer must never directly override global bone poses")
        return
    for token: String in ["AnimationPlayer", "resolve_melee_animation", "resolve_weapon_shot_animation", "combat_pose_safe_fallback", "request_melee_pose", "request_shot_pose"]:
        if pose_source.find(token) < 0:
            _fail("safe authored animation layer missing token %s" % token)
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

    if not ResourceLoader.exists(REAL_PLAYER):
        _fail("real authored player GLB missing")
        return
    var resource := ResourceLoader.load(REAL_PLAYER)
    if not resource is PackedScene:
        _fail("real authored player did not import as PackedScene")
        return
    var instance := (resource as PackedScene).instantiate()
    root.add_child(instance)
    await process_frame
    var animation_player := _find_animation_player(instance)
    if animation_player == null:
        _fail("real authored player AnimationPlayer missing")
        return
    var names := animation_player.get_animation_list()
    if names.size() < 70:
        _fail("authored animation catalog unexpectedly small: %d" % names.size())
        return

    var melee_clip := POSE.resolve_melee_animation(names, &"jab_left")
    var kick_clip := POSE.resolve_melee_animation(names, &"front_kick_right")
    if melee_clip == &"" or kick_clip == &"":
        _fail("real KayKit animation catalog must resolve safe melee/kick actions")
        return
    var bx9_clip := POSE.resolve_weapon_shot_animation(names, &"bx9")
    var cbr4_clip := POSE.resolve_weapon_shot_animation(names, &"cbr4")
    var sct8_clip := POSE.resolve_weapon_shot_animation(names, &"sct8")
    instance.queue_free()

    print("COMBAT_VISIBLE_FUN_OK: hand_grip=green authored_animation_safe=green moves=10 action_lock=green muzzle=green tracer=green impacts=green casings=green catalog=%d melee=%s kick=%s bx9=%s cbr4=%s sct8=%s" % [names.size(), String(melee_clip), String(kick_clip), String(bx9_clip), String(cbr4_clip), String(sct8_clip)])
    quit(0)

func _find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer
    for child: Node in node.get_children():
        var found := _find_animation_player(child)
        if found != null:
            return found
    return null

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
