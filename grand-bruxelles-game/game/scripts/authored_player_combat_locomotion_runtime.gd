extends "res://game/scripts/authored_player_locomotion_runtime.gd"

# Preserve the production hysteresis/speed-sync/foot-slide protections and only
# extend the weapon-to-authored-locomotion mapping for the native crossbow.

func _armed_hand_mode() -> String:
    if not is_instance_valid(_player):
        return ""
    var weapon_id := StringName(_player.get_meta(WEAPON_META, &""))
    if weapon_id == &"crossbow":
        return "2h"
    if weapon_id == &"knife":
        return ""
    return super._armed_hand_mode()
