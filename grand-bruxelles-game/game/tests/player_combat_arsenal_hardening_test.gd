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

    var low_flinch := HARDENED.weapon_flinch_angle_deg(5.0)
    var medium_flinch := HARDENED.weapon_flinch_angle_deg(25.0)
    var high_flinch := HARDENED.weapon_flinch_angle_deg(80.0)
    if low_flinch < 3.49 or medium_flinch <= low_flinch or high_flinch < medium_flinch or high_flinch > 10.01:
        _fail("weapon flinch must scale monotonically inside readable bounds"); return

    var source := FileAccess.get_file_as_string("res://game/scripts/player_combat_arsenal_hardened_runtime.gd")
    if source.find("_next_fire_ms = 0") < 0:
        _fail("weapon switch must reset inherited cadence gate"); return
    if source.find("func set_aiming") < 0:
        _fail("touch aiming needs a public arsenal API"); return
    if source.find("IMPACT  -%d") < 0 or source.find("_animate_weapon_flinch") < 0:
        _fail("weapon impacts need accurate damage feedback and visible flinch"); return
    if source.find("combat_weapon_hit_inflight") < 0:
        _fail("weapon hits must be isolated from melee directional flinch"); return

    var move_publish_pos := source.find("player.set_meta(\"combat_move_id\"")
    var melee_call_pos := source.find("melee_runtime.call(\"request_attack\", player)")
    if move_publish_pos < 0 or melee_call_pos < 0 or move_publish_pos >= melee_call_pos:
        _fail("combo move metadata must be published before melee hit resolution"); return

    var project_text := FileAccess.get_file_as_string("res://project.godot")
    var expected := "PlayerCombatArsenalRuntime=\"*res://game/scripts/player_combat_arsenal_hardened_runtime.gd\""
    if project_text.find(expected) < 0:
        _fail("project must autoload the hardened arsenal runtime"); return

    print("PLAYER_COMBAT_HARDENING_OK: camera_preflight=green cadence_reset=green public_aim_api=green hit_feedback=green flinch=green combo_direction_order=green flinch_isolation=green")
    quit(0)
