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

    var move_ids: Array[StringName] = [&"jab_left", &"cross_right", &"hook_left", &"front_kick_right"]
    for move_id: StringName in move_ids:
        var weight := HARDENED.melee_weight_profile(move_id)
        if weight.is_empty() or StringName(weight.get("id", &"neutral")) == &"neutral":
            _fail("missing dedicated body-weight profile for %s" % move_id); return
        var drop_m := float(weight.get("drop_m", 0.0))
        if drop_m < 0.005 or drop_m > 0.04:
            _fail("body-weight drop escaped subtle playable bounds for %s" % move_id); return
        if absf(float(weight.get("pitch_deg", 0.0))) < 1.0 or absf(float(weight.get("pitch_deg", 0.0))) > 8.0:
            _fail("body pitch escaped readable bounds for %s" % move_id); return
        if String(weight.get("brace_limb", "")) == "":
            _fail("body-weight profile needs a bracing leg for %s" % move_id); return
    if float(HARDENED.melee_weight_profile(&"front_kick_right").get("pitch_deg", 0.0)) <= 0.0:
        _fail("front kick should counterbalance backward instead of using punch drive"); return
    if float(HARDENED.melee_weight_profile(&"cross_right").get("pitch_deg", 0.0)) >= 0.0:
        _fail("cross should drive body forward"); return

    if HARDENED.next_combo_index(0, false, 1) != 0 or HARDENED.next_combo_index(2, false, 9) != 0:
        _fail("missed strike must reset combo to jab"); return
    if HARDENED.next_combo_index(0, true, 1) != 1:
        _fail("landed jab must advance to cross"); return
    if HARDENED.next_combo_index(1, true, 1) != 2:
        _fail("normal landed cross must advance to hook"); return
    if HARDENED.next_combo_index(1, true, 3) != 3:
        _fail("every third completed cross must branch to kick"); return
    if HARDENED.next_combo_index(2, true, 4) != 3:
        _fail("landed hook must advance to kick"); return
    if HARDENED.next_combo_index(3, true, 4) != 0:
        _fail("landed kick must wrap to jab"); return

    var source := FileAccess.get_file_as_string("res://game/scripts/player_combat_arsenal_hardened_runtime.gd")
    if source.find("_next_fire_ms = 0") < 0:
        _fail("weapon switch must reset inherited cadence gate"); return
    if source.find("func set_aiming") < 0:
        _fail("touch aiming needs a public arsenal API"); return
    if source.find("IMPACT  -%d") < 0 or source.find("_animate_weapon_flinch") < 0:
        _fail("weapon impacts need accurate damage feedback and visible flinch"); return
    if source.find("combat_weapon_hit_inflight") < 0:
        _fail("weapon hits must be isolated from melee directional flinch"); return
    if source.find("_animate_melee_weight_transfer") < 0:
        _fail("melee combo must animate full-body weight transfer"); return
    if source.find("func _apply_recoil(profile: Dictionary)") < 0:
        _fail("hardened arsenal must own recoil so the hand mount cannot drift"); return
    if source.find("combat_weapon_recoil_mount_locked") < 0:
        _fail("recoil hand-lock marker missing"); return
    if source.find("_weapon_visual.position.z") >= 0 or source.find("position:z\"") >= 0:
        _fail("hardened recoil must not translate the weapon holder away from the hand"); return
    if source.find("func _rebuild_weapon_visual(player: CharacterBody3D)") < 0:
        _fail("hardened arsenal must normalize holder identity during weapon swaps"); return
    if source.find("CombatWeaponVisualRetired_") < 0 or source.find("combat_weapon_canonical_holder") < 0:
        _fail("rapid weapon swaps must retire the old holder before creating the canonical holder"); return
    if source.find("combat_weapon_holder_weapon_id") < 0:
        _fail("canonical weapon holder must publish its active weapon id"); return
    if source.find("MELEE_BUFFER_MS") < 0 or source.find("_tick_melee_buffer") < 0:
        _fail("modern melee must keep the bounded one-slot input buffer"); return

    var move_publish_pos := source.find("player.set_meta(\"combat_move_id\"")
    var melee_call_pos := source.find("melee_runtime.call(\"request_attack_with_move\", player, move)")
    if move_publish_pos < 0 or melee_call_pos < 0 or move_publish_pos >= melee_call_pos:
        _fail("combo move metadata must be published before deferred melee contact scheduling"); return

    var project_text := FileAccess.get_file_as_string("res://project.godot")
    var expected := "PlayerCombatArsenalRuntime=\"*res://game/scripts/player_combat_arsenal_polish_runtime.gd\""
    if project_text.find(expected) < 0:
        _fail("project must autoload the polish arsenal runtime"); return
    var polish_source := FileAccess.get_file_as_string("res://game/scripts/player_combat_arsenal_polish_runtime.gd")
    if polish_source.find("extends \"res://game/scripts/player_combat_arsenal_hardened_runtime.gd\"") < 0:
        _fail("polish runtime must extend hardened arsenal rather than bypass it"); return

    print("PLAYER_COMBAT_HARDENING_OK: camera_preflight=green cadence_reset=green public_aim_api=green hit_feedback=green flinch=green combo_direction_order=green combo_variation=green flinch_isolation=green weight_transfer=4 grip_recoil_lock=green canonical_holder_swap=green deferred_melee_contract=green buffer=green polish_inheritance=green")
    quit(0)