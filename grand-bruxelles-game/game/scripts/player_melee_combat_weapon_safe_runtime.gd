extends "res://game/scripts/player_melee_combat_hardened_runtime.gd"

# Final melee invariant guard for weapon switching. Arsenal owns the switch;
# this runtime owns deferred melee contact. If a switch begins during windup,
# the unresolved contact is cancelled before it can land with a different
# weapon already in transition.

const WEAPON_SWITCH_CANCEL_REASON := "weapon_switch"

func _ready() -> void:
    super._ready()
    process_priority = -4

func _process(delta: float) -> void:
    var player := _current_player()
    if player != null and bool(player.get_meta("combat_weapon_switching", false)):
        cancel_pending_attack_for_weapon_switch(player)
    super._process(delta)

func cancel_pending_attack_for_weapon_switch(player: CharacterBody3D) -> bool:
    if player == null or not is_instance_valid(player):
        return false
    if not bool(player.get_meta("combat_attack_pending", false)) and _pending_player_attack.is_empty():
        return false

    var now := Time.get_ticks_msec()
    _pending_player_attack.clear()
    _next_attack_allowed_ms = now
    player.set_meta("combat_attack_pending", false)
    player.set_meta("combat_attack_phase", "ready")
    player.set_meta("combat_attack_impact_at_ms", 0)
    player.set_meta("combat_attack_active_until_ms", 0)
    player.set_meta("combat_attack_recovery_until_ms", now)
    player.set_meta("combat_move_recovery_ms", 0)
    player.set_meta("combat_move_recovery_landed", false)
    player.set_meta("combat_attack_cancelled_ms", now)
    player.set_meta("combat_attack_cancel_reason", WEAPON_SWITCH_CANCEL_REASON)
    player.set_meta("combat_weapon_melee_attack", false)
    set_guarding(player, false)
    return true
