extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("COMBAT_WEAPON_SWITCH_MELEE_CANCEL_FAIL: %s" % message)
    quit(1)

func _wait_equipped(player: CharacterBody3D, weapon_id: StringName) -> bool:
    for _attempt: int in range(240):
        await process_frame
        if StringName(player.get_meta("combat_weapon_id", &"")) == weapon_id \
        and StringName(player.get_meta("combat_weapon_state", &"")) == &"equipped" \
        and not bool(player.get_meta("combat_weapon_switching", false)):
            return true
    return false

func _run() -> void:
    if change_scene_to_file(MAIN_SCENE) != OK:
        _fail("main scene load failed")
        return

    var player: CharacterBody3D = null
    for _attempt: int in range(360):
        await process_frame
        if current_scene != null:
            player = current_scene.get_node_or_null("Player") as CharacterBody3D
            if player != null:
                break
    if player == null:
        _fail("production player unavailable")
        return

    var arsenal := root.get_node_or_null("PlayerCombatArsenalRuntime")
    var melee := root.get_node_or_null("PlayerMeleeCombatRuntime")
    if arsenal == null or melee == null:
        _fail("production combat owners unavailable")
        return
    if not melee.has_method("cancel_pending_attack_for_weapon_switch"):
        _fail("weapon-safe melee cancellation API unavailable")
        return

    if not bool(arsenal.call("equip_weapon", player, &"knife")) or not await _wait_equipped(player, &"knife"):
        _fail("knife failed to reach equipped state")
        return

    var before_impact_ms := int(player.get_meta("combat_last_melee_impact_ms", 0))
    var attack_variant: Variant = arsenal.call("request_fire", player)
    if not attack_variant is Dictionary:
        _fail("knife attack result was not a Dictionary")
        return
    var attack := attack_variant as Dictionary
    if not bool(attack.get("fired", false)) or not bool(attack.get("pending", false)):
        _fail("knife attack did not enter deferred windup: %s" % JSON.stringify(attack))
        return
    if not bool(player.get_meta("combat_attack_pending", false)):
        _fail("knife attack pending flag missing before switch")
        return
    var original_impact_at := int(player.get_meta("combat_attack_impact_at_ms", 0))
    if original_impact_at <= Time.get_ticks_msec():
        _fail("knife impact was not scheduled in the future")
        return

    if not bool(arsenal.call("equip_weapon", player, &"bx9")):
        _fail("BX-9 switch request rejected during knife windup")
        return
    if StringName(player.get_meta("combat_weapon_state", &"")) != &"holstering":
        _fail("switch did not enter holstering during knife windup")
        return

    for _frame: int in range(8):
        await process_frame
        if not bool(player.get_meta("combat_attack_pending", true)):
            break
    if bool(player.get_meta("combat_attack_pending", true)):
        _fail("unresolved knife contact survived weapon switch")
        return
    if String(player.get_meta("combat_attack_cancel_reason", "")) != "weapon_switch":
        _fail("melee cancellation reason was not weapon_switch")
        return
    if int(player.get_meta("combat_attack_impact_at_ms", -1)) != 0:
        _fail("stale melee impact timestamp survived cancellation")
        return

    var deadline := maxi(original_impact_at + 100, Time.get_ticks_msec() + 140)
    while Time.get_ticks_msec() < deadline:
        await process_frame
    if int(player.get_meta("combat_last_melee_impact_ms", 0)) != before_impact_ms:
        _fail("cancelled knife strike still resolved a delayed impact")
        return
    if not await _wait_equipped(player, &"bx9"):
        _fail("BX-9 did not finish equipping after cancelled knife strike")
        return

    print("COMBAT_WEAPON_SWITCH_MELEE_CANCEL_OK: knife_windup=green switch_cancel=green no_phantom_contact=green bx9_equipped=green")
    quit(0)
