extends SceneTree

const ARSENAL := preload("res://game/scripts/player_combat_arsenal_hardened_runtime.gd")
const POSE := preload("res://game/scripts/combat_authored_pose_runtime.gd")
const LOCOMOTION := preload("res://game/scripts/authored_player_locomotion_runtime.gd")
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
        if float(move.get("windup_s", 0.0)) <= 0.0 or float(move.get("active_s", 0.0)) <= 0.0 or float(move.get("recover_s", 0.0)) <= 0.0:
            _fail("combat move timing must include windup, active and recovery phases")
            return

    var required_moves: Array[StringName] = [&"jab_left", &"cross_right", &"hook_left", &"hook_right", &"uppercut_right", &"body_hook_left", &"front_kick_right", &"low_kick_left", &"push_kick_right", &"elbow_right"]
    for required: StringName in required_moves:
        if not ids.has(required):
            _fail("missing required visible move %s" % required)
            return

    if ARSENAL.MELEE_BUFFER_MS < 120 or ARSENAL.MELEE_BUFFER_MS > 240:
        _fail("melee buffer escaped responsive one-input bounds")
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
    var melee_source := _read("res://game/scripts/player_melee_combat_hardened_runtime.gd")
    var project_source := _read("res://project.godot")
    if [locomotion_source, pose_source, fx_source, arsenal_source, melee_source, project_source].any(func(value: String) -> bool: return value.is_empty()):
        _fail("source fixture missing")
        return

    for token: String in ["combat_action_lock_until_ms", "_action_locked()", "resolve_ranged_locomotion", "authored_locomotion_weapon_aware", "_target_animation_for_state"]:
        if locomotion_source.find(token) < 0:
            _fail("locomotion must preserve combat/ranged authored animation contract: %s" % token)
            return

    if pose_source.find("set_bone_global_pose_override") >= 0:
        _fail("combat pose layer must never directly override global bone poses")
        return
    for token: String in ["AnimationPlayer", "resolve_melee_animation", "resolve_weapon_shot_animation", "melee_variant_hint", "combat_pose_safe_fallback", "request_melee_pose", "request_shot_pose"]:
        if pose_source.find(token) < 0:
            _fail("safe authored animation layer missing token %s" % token)
            return

    for token: String in ["CombatMuzzleFlash", "CombatTracer_", "CombatImpactFx_", "CombatCasing_", "OmniLight3D"]:
        if fx_source.find(token) < 0:
            _fail("shot FX layer missing token %s" % token)
            return
    for token: String in ["MELEE_MOVES_V2", "MELEE_BUFFER_MS", "_tick_melee_buffer", "request_attack_with_move", "request_melee_pose", "request_shot_pose", "combat_melee_anim_started_ms"]:
        if arsenal_source.find(token) < 0:
            _fail("arsenal hardening missing modern combat hook %s" % token)
            return
    for token: String in ["combat_attack_impact_at_ms", "combat_attack_pending", "combat_attack_input_owner", "request_attack_with_move"]:
        if melee_source.find(token) < 0:
            _fail("melee runtime missing contact-timed contract %s" % token)
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

    var melee_candidates: Array[String] = []
    for animation_name: String in names:
        var lowered := animation_name.to_lower()
        if lowered.contains("unarmed") or lowered.contains("melee"):
            melee_candidates.append(animation_name)
    print("COMBAT_MELEE_CATALOG: %s" % [melee_candidates])

    var resolved_melee_clips: Dictionary = {}
    for move_id: StringName in required_moves:
        var clip := POSE.resolve_melee_animation(names, move_id)
        if clip == &"":
            _fail("real KayKit animation catalog could not resolve %s" % move_id)
            return
        resolved_melee_clips[clip] = true
    if resolved_melee_clips.size() < 2:
        _fail("ten-move repertoire collapsed to fewer than two real authored action clips")
        return

    var melee_clip := POSE.resolve_melee_animation(names, &"jab_left")
    var kick_clip := POSE.resolve_melee_animation(names, &"front_kick_right")
    var bx9_clip := POSE.resolve_weapon_shot_animation(names, &"bx9")
    var cbr4_clip := POSE.resolve_weapon_shot_animation(names, &"cbr4")
    var sct8_clip := POSE.resolve_weapon_shot_animation(names, &"sct8")
    if bx9_clip == &"" or cbr4_clip == &"" or sct8_clip == &"":
        _fail("real KayKit animation catalog must resolve 1H/2H ranged shoot clips")
        return

    var ranged_candidates: Array[String] = []
    for animation_name: String in names:
        if animation_name.to_lower().contains("ranged"):
            ranged_candidates.append(animation_name)
    print("COMBAT_RANGED_CATALOG: %s" % [ranged_candidates])

    var ranged_1h := LOCOMOTION.resolve_ranged_locomotion(names, "1h")
    var ranged_2h := LOCOMOTION.resolve_ranged_locomotion(names, "2h")
    var ranged_1h_idle := String(ranged_1h.get("idle", ""))
    var ranged_1h_walk := String(ranged_1h.get("walk", ""))
    var ranged_1h_run := String(ranged_1h.get("run", ""))
    var ranged_2h_idle := String(ranged_2h.get("idle", ""))
    var ranged_2h_walk := String(ranged_2h.get("walk", ""))
    var ranged_2h_run := String(ranged_2h.get("run", ""))
    if ranged_1h_idle.is_empty() or ranged_2h_idle.is_empty():
        _fail("real KayKit animation catalog must resolve 1H/2H ranged idle carry; candidates=%s" % [ranged_candidates])
        return
    instance.queue_free()

    print("COMBAT_VISIBLE_FUN_OK: rig_safe=green authored_actions=green authored_action_variants=%d armed_idle=green moves=10 buffer_ms=%d contact_timing=green action_lock=green muzzle=green tracer=green impacts=green casings=green catalog=%d melee=%s kick=%s bx9=%s cbr4=%s sct8=%s ranged1h=[%s,%s,%s] ranged2h=[%s,%s,%s]" % [resolved_melee_clips.size(), ARSENAL.MELEE_BUFFER_MS, names.size(), String(melee_clip), String(kick_clip), String(bx9_clip), String(cbr4_clip), String(sct8_clip), ranged_1h_idle, ranged_1h_walk, ranged_1h_run, ranged_2h_idle, ranged_2h_walk, ranged_2h_run])
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