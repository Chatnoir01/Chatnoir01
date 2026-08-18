extends SceneTree

const ARSENAL := preload("res://game/scripts/player_combat_arsenal_runtime.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("PLAYER_COMBAT_ARSENAL_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var project_text := FileAccess.get_file_as_string("res://project.godot")
    var melee_pos := project_text.find("PlayerMeleeCombatRuntime=\"*res://game/scripts/player_melee_combat_runtime.gd\"")
    var arsenal_pos := project_text.find("PlayerCombatArsenalRuntime=\"*res://game/scripts/player_combat_arsenal_runtime.gd\"")
    if melee_pos < 0 or arsenal_pos < 0:
        _fail("combat autoloads missing from project.godot"); return
    # Godot sends _input in reverse depth-first order. Arsenal must therefore be
    # declared after legacy melee so it receives and consumes fire/melee input first.
    if arsenal_pos <= melee_pos:
        _fail("arsenal autoload must be declared after legacy melee for input priority"); return

    if ARSENAL.MELEE_MOVES.size() < 4:
        _fail("expected at least four distinct melee moves"); return
    var move_ids: Dictionary = {}
    for index: int in range(ARSENAL.MELEE_MOVES.size()):
        var move := ARSENAL.melee_move(index)
        var move_id := StringName(move.get("id", &""))
        if move_id == &"" or move_ids.has(move_id):
            _fail("melee move ids must be non-empty and unique"); return
        move_ids[move_id] = true
        var total_time := float(move.get("windup_s", 0.0)) + float(move.get("active_s", 0.0)) + float(move.get("recover_s", 0.0))
        if total_time <= 0.15 or total_time > 0.65:
            _fail("melee move timing outside playable bounds: %s %.3f" % [move_id, total_time]); return

    var expected_weapons: Array[StringName] = [&"bx9", &"cbr4", &"sct8"]
    for weapon_id: StringName in expected_weapons:
        var profile := ARSENAL.weapon_profile(weapon_id)
        if profile.is_empty():
            _fail("missing weapon profile %s" % weapon_id); return
        var mag_size := int(profile.get("mag_size", 0))
        var reserve := int(profile.get("reserve", 0))
        if mag_size <= 0 or reserve < mag_size:
            _fail("invalid ammo budget for %s" % weapon_id); return
        if int(profile.get("fire_interval_ms", 0)) < 70:
            _fail("fire cadence is outside the performance/simulation guardrail for %s" % weapon_id); return
        if int(profile.get("reload_ms", 0)) <= 0:
            _fail("reload must have a non-zero duration for %s" % weapon_id); return
        var range_m := float(profile.get("range_m", 0.0))
        var base_damage := float(profile.get("damage", 0.0))
        var min_factor := float(profile.get("min_damage_factor", 0.0))
        var near_damage := ARSENAL.damage_at_distance(base_damage, 0.0, range_m, min_factor)
        var mid_damage := ARSENAL.damage_at_distance(base_damage, range_m * 0.5, range_m, min_factor)
        var far_damage := ARSENAL.damage_at_distance(base_damage, range_m, range_m, min_factor)
        if near_damage < mid_damage or mid_damage < far_damage or far_damage <= 0.0:
            _fail("damage falloff must be positive and monotonic for %s" % weapon_id); return
        var hip := ARSENAL.spread_for_state(profile, false, 0.0)
        var aimed := ARSENAL.spread_for_state(profile, true, 0.0)
        var moving := ARSENAL.spread_for_state(profile, false, 7.0)
        if aimed >= hip:
            _fail("aiming must improve spread for %s" % weapon_id); return
        if moving <= hip:
            _fail("movement must increase spread for %s" % weapon_id); return

    if not ARSENAL.weapon_profile(&"does_not_exist").is_empty():
        _fail("unknown weapon ids must not resolve"); return
    if ARSENAL.damage_at_distance(25.0, 999.0, 50.0, 0.5) < 12.49:
        _fail("falloff must clamp at the configured minimum factor"); return

    print("PLAYER_COMBAT_ARSENAL_OK: input_order=green moves=%d weapons=%d deterministic tuning invariants green" % [ARSENAL.MELEE_MOVES.size(), expected_weapons.size()])
    quit(0)
