extends "res://game/scripts/player_combat_touch_runtime.gd"

# Touch bridge for the Rogue-native crossbow loadout.
# The base touch UI is preserved; only the weapon cycle/label are extended.

const ROGUE_WEAPON_CYCLE: Array[StringName] = [&"", &"crossbow", &"bx9", &"cbr4", &"sct8"]

func _cycle_weapon() -> void:
    var arsenal := _arsenal()
    var player := _current_player()
    if arsenal == null or player == null:
        return
    var current := StringName(arsenal.call("equipped_weapon"))
    var index := ROGUE_WEAPON_CYCLE.find(current)
    var next_index := 0 if index < 0 else (index + 1) % ROGUE_WEAPON_CYCLE.size()
    arsenal.call("equip_weapon", player, ROGUE_WEAPON_CYCLE[next_index])
    _refresh_labels(arsenal)

func _refresh_labels(arsenal: Node) -> void:
    super._refresh_labels(arsenal)
    if _status_label == null:
        return
    var weapon_id := StringName(arsenal.call("equipped_weapon"))
    if weapon_id == &"crossbow":
        _status_label.text = _status_label.text.replace("CROSSBOW", "ARBALETE")
