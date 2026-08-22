extends SceneTree

const TOUCH := preload("res://game/scripts/player_combat_touch_runtime.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("COMBAT_TOUCH_WEAPON_CYCLE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var expected: Array[StringName] = [&"", &"bx9", &"cbr4", &"sct8", &"crossbow", &"knife"]
    if TOUCH.WEAPON_CYCLE != expected:
        _fail("touch weapon cycle drifted: %s" % str(TOUCH.WEAPON_CYCLE))
        return
    if String(TOUCH.WEAPON_LABELS.get(&"crossbow", "")) != "ARBALETE":
        _fail("crossbow touch label missing")
        return
    if String(TOUCH.WEAPON_LABELS.get(&"knife", "")) != "COUTEAU":
        _fail("knife touch label missing")
        return

    var source := FileAccess.get_file_as_string("res://game/scripts/player_combat_touch_runtime.gd")
    for token: String in [
        "weapon_id == KNIFE_ID or weapon_id == &\"\"",
        "weapon_id != &\"\" and weapon_id != KNIFE_ID",
        "melee.call(\"set_guarding\", player, true)",
        "dodge.call(\"request_dodge\", player, Vector3.ZERO)",
        "arsenal.call(\"request_reload\", player)",
        "arsenal.call(\"request_fire\", player)",
        "_action_button.text = \"TAILLER\"",
        "_aim_button.text = \"GARDE\"",
        "_reload_button.text = \"ESQUIVE\"",
    ]:
        if source.find(token) < 0:
            _fail("touch contextual combat contract missing token: %s" % token)
            return

    print("COMBAT_TOUCH_WEAPON_CYCLE_OK: cycle=unarmed/bx9/cbr4/sct8/crossbow/knife crossbow=aim_reload knife=guard_dodge_slash")
    quit(0)
