extends SceneTree

const HARDENED := preload("res://game/scripts/player_melee_combat_hardened_runtime.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("PLAYER_MELEE_HARDENED_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var evade := HARDENED.counter_outcome(false, 999999, true)
    if StringName(evade.get("kind", &"")) != &"evade" or int(evade.get("damage", -1)) != 0:
        _fail("active dodge window must fully evade NPC counter damage"); return

    var parry := HARDENED.counter_outcome(true, HARDENED.PERFECT_GUARD_WINDOW_MS - 1, false)
    if StringName(parry.get("kind", &"")) != &"parry" or int(parry.get("damage", -1)) != 0:
        _fail("fresh guard must resolve as zero-damage parry"); return

    var edge_parry := HARDENED.counter_outcome(true, HARDENED.PERFECT_GUARD_WINDOW_MS, false)
    if StringName(edge_parry.get("kind", &"")) != &"parry":
        _fail("perfect guard window must include its configured edge"); return

    var block := HARDENED.counter_outcome(true, HARDENED.PERFECT_GUARD_WINDOW_MS + 1, false)
    if StringName(block.get("kind", &"")) != &"block" or int(block.get("damage", -1)) != 2:
        _fail("held guard after perfect window must preserve legacy 2 damage block"); return

    var open_hit := HARDENED.counter_outcome(false, 999999, false)
    if StringName(open_hit.get("kind", &"")) != &"hit" or int(open_hit.get("damage", -1)) != 8:
        _fail("unguarded counter must preserve legacy 8 damage"); return

    if HARDENED.COUNTER_TELEGRAPH_MS < 180 or HARDENED.COUNTER_TELEGRAPH_MS > 420:
        _fail("counter telegraph must remain readable without making NPCs inert"); return
    if HARDENED.COUNTER_RANGE_M < 1.5 or HARDENED.COUNTER_RANGE_M > 2.5:
        _fail("counter range escaped close-combat bounds"); return

    var expected_moves: Array[StringName] = [&"jab_left", &"cross_right", &"hook_left", &"front_kick_right"]
    var sides: Dictionary = {}
    var previous_stagger := 0
    for move_id: StringName in expected_moves:
        var profile := HARDENED.melee_reaction_profile(move_id)
        if profile.is_empty():
            _fail("missing reaction profile for %s" % move_id); return
        var side := String(profile.get("side", ""))
        if side == "":
            _fail("reaction side missing for %s" % move_id); return
        sides[side] = true
        var stagger_ms := int(profile.get("stagger_ms", 0))
        if stagger_ms < 250 or stagger_ms > 800:
            _fail("stagger outside playable bounds for %s" % move_id); return
        previous_stagger = stagger_ms
    if sides.size() < 3:
        _fail("melee reactions must distinguish left/right/center directions"); return

    var source := FileAccess.get_file_as_string("res://game/scripts/player_melee_combat_hardened_runtime.gd")
    if source.find("combat_dodge_until_ms") < 0:
        _fail("counter resolver is not wired to dodge evade window"); return
    if source.find("counter_windup_until_ms") < 0 or source.find("CounterTelegraph") < 0:
        _fail("NPC counter telegraph state/visual is missing"); return
    if source.find("combat_guard_started_ms") < 0:
        _fail("guard start timestamp required for perfect guard window"); return

    print("PLAYER_MELEE_HARDENED_OK: evade=0 parry=0 block=2 open=8 telegraph_ms=%d directional_profiles=4" % HARDENED.COUNTER_TELEGRAPH_MS)
    quit(0)
