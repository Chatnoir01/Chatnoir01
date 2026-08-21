extends "res://game/scripts/combat_weapon_hand_orientation_runtime.gd"

# Keeps the proven hand lock/orientation, then layers a short draw/holster arc.
# No Skeleton3D bone override is used: equipped state always returns to the exact
# V3 right-hand socket, while transition state is intentionally marked unlocked.

const SIGNATURE_POLISH := "combat_weapon_hand_orientation_polish_v1"

func orient_weapon_from_player(holder: Node3D, player: CharacterBody3D, weapon_id: StringName) -> bool:
    var locked := super.orient_weapon_from_player(holder, player, weapon_id)
    if holder == null or player == null:
        return false

    var state := StringName(player.get_meta("combat_weapon_state", &"equipped"))
    if state != &"holstering" and state != &"equipping":
        holder.set_meta("combat_weapon_transition_pose_active", false)
        holder.set_meta("combat_weapon_orientation_polish_signature", SIGNATURE_POLISH)
        player.set_meta("combat_weapon_transition_pose_active", false)
        return locked

    var progress := _transition_progress(player)
    var weight := progress if state == &"holstering" else 1.0 - progress
    var long_weapon := weapon_id == &"cbr4" or weapon_id == &"sct8"
    var local_offset := Vector3(0.10, -0.22, 0.12) if not long_weapon else Vector3(0.14, -0.29, 0.19)
    holder.global_position += player.global_transform.basis * (local_offset * weight)
    var extra_deg := Vector3(22.0, 18.0, 28.0) if not long_weapon else Vector3(30.0, 20.0, 18.0)
    holder.rotation += Vector3(
        deg_to_rad(extra_deg.x * weight),
        deg_to_rad(extra_deg.y * weight),
        deg_to_rad(extra_deg.z * weight)
    )

    holder.set_meta("combat_weapon_transition_pose_active", true)
    holder.set_meta("combat_weapon_transition_pose_weight", weight)
    holder.set_meta("combat_weapon_orientation_polish_signature", SIGNATURE_POLISH)
    holder.set_meta("combat_weapon_orientation_locked", false)
    player.set_meta("combat_weapon_transition_pose_active", true)
    player.set_meta("combat_weapon_transition_pose_weight", weight)
    player.set_meta("combat_weapon_orientation_locked", false)
    return false

static func _transition_progress(player: CharacterBody3D) -> float:
    var started := int(player.get_meta("combat_weapon_switch_phase_started_ms", 0))
    var end := int(player.get_meta("combat_weapon_switch_phase_end_ms", 0))
    if end <= started:
        return 1.0
    return clampf(float(Time.get_ticks_msec() - started) / float(end - started), 0.0, 1.0)
