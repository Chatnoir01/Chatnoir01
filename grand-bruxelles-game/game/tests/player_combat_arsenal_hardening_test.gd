extends SceneTree

const HARDENED := preload("res://game/scripts/player_combat_arsenal_hardened_runtime.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("PLAYER_COMBAT_HARDENING_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    if HARDENED.fire_preflight_reason(false, true, true) != &"player_unavailable":
        _fail("missing player must fail before any ammo mutation"); return
    if HARDENED.fire_preflight_reason(true, false, true) != &"unarmed":
        _fail("unarmed preflight must stay explicit"); return
    if HARDENED.fire_preflight_reason(true, true, false) != &"camera_unavailable":
        _fail("missing camera must fail before base request_fire"); return
    if HARDENED.fire_preflight_reason(true, true, true) != &"":
        _fail("valid fire preflight should pass"); return

    var source := FileAccess.get_file_as_string("res://game/scripts/player_combat_arsenal_hardened_runtime.gd")
    if source.find("_next_fire_ms = 0") < 0:
        _fail("weapon switch must reset inherited cadence gate"); return
    if source.find("func set_aiming") < 0:
        _fail("touch aiming needs a public arsenal API"); return

    var project_text := FileAccess.get_file_as_string("res://project.godot")
    var expected := "PlayerCombatArsenalRuntime=\"*res://game/scripts/player_combat_arsenal_hardened_runtime.gd\""
    if project_text.find(expected) < 0:
        _fail("project must autoload the hardened arsenal runtime"); return

    print("PLAYER_COMBAT_HARDENING_OK: camera_preflight=green cadence_reset=green public_aim_api=green")
    quit(0)
