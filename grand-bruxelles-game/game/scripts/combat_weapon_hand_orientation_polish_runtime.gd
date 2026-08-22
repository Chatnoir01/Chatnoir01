extends "res://game/scripts/combat_weapon_hand_orientation_runtime.gd"

# Keeps the proven hand lock/orientation, then layers a short draw/holster arc.
# Equipped long weapons get one additional production-safe correction: rotate
# the whole weapon around the already locked right-hand grip until the *real*
# visible support socket falls inside the left arm's reachable volume. No bone
# override is used and the weapon is never translated away from hand.r.

const SIGNATURE_POLISH := "combat_weapon_hand_orientation_polish_v2_support_autofit"
const SUPPORT_SOCKET_NAME := "WeaponSupportGripSocket"
const LONG_WEAPONS: Array[StringName] = [&"cbr4", &"sct8"]
const AUTOFIT_MAX_YAW_DEG := 75.0
const AUTOFIT_STEP_DEG := 5.0
const AUTOFIT_REACH_MARGIN_M := 0.03
const AUTOFIT_FALLBACK_REACH_M := 0.44
const AUTOFIT_MIN_FORWARD_DOT := 0.45

func orient_weapon_from_player(holder: Node3D, player: CharacterBody3D, weapon_id: StringName) -> bool:
    var locked := super.orient_weapon_from_player(holder, player, weapon_id)
    if holder == null or player == null:
        return false

    var state := StringName(player.get_meta("combat_weapon_state", &"equipped"))
    if state != &"holstering" and state != &"equipping":
        if weapon_id in LONG_WEAPONS:
            locked = _autofit_long_weapon_support(holder, player, weapon_id) and locked
        else:
            _clear_autofit_meta(holder, player)
        holder.set_meta("combat_weapon_transition_pose_active", false)
        holder.set_meta("combat_weapon_orientation_polish_signature", SIGNATURE_POLISH)
        player.set_meta("combat_weapon_transition_pose_active", false)
        return locked

    _clear_autofit_meta(holder, player)
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

func _autofit_long_weapon_support(holder: Node3D, player: CharacterBody3D, weapon_id: StringName) -> bool:
    var support := holder.find_child(SUPPORT_SOCKET_NAME, true, false) as Node3D
    var socket := holder.get_node_or_null(RIGHT_HAND_SOCKET_NAME) as Node3D
    if support == null or socket == null:
        _clear_autofit_meta(holder, player)
        return false

    # CombatSupportHandIKRuntime publishes the authored upperarm.l origin every
    # frame. Orientation runs first, so after the first warm-up frame this is a
    # stable previous-frame shoulder reference without touching Skeleton3D.
    var left_shoulder: Vector3 = player.get_meta("combat_support_ik_shoulder_world", Vector3.ZERO)
    if left_shoulder == Vector3.ZERO:
        _clear_autofit_meta(holder, player)
        return true

    var grip_runtime := get_node_or_null("/root/CombatWeaponVisualUpgradeRuntime")
    if grip_runtime == null or not grip_runtime.has_method("resolve_right_hand_anchor"):
        _clear_autofit_meta(holder, player)
        return false
    var anchor_variant: Variant = grip_runtime.call("resolve_right_hand_anchor", player)
    if not anchor_variant is Dictionary:
        _clear_autofit_meta(holder, player)
        return false
    var anchor := anchor_variant as Dictionary
    if not bool(anchor.get("found", false)):
        _clear_autofit_meta(holder, player)
        return false
    var hand_transform: Transform3D = anchor.get("transform", Transform3D.IDENTITY)

    var reach_m := AUTOFIT_FALLBACK_REACH_M
    var lengths_variant: Variant = player.get_meta("combat_support_ik_lengths", {})
    if lengths_variant is Dictionary:
        var lengths := lengths_variant as Dictionary
        reach_m = maxf(0.30, float(lengths.get("full_hand_reach", AUTOFIT_FALLBACK_REACH_M)) - AUTOFIT_REACH_MARGIN_M)

    var carry_deg := carry_rotation_degrees(weapon_id)
    var player_forward := (-player.global_transform.basis.z).normalized()
    var best_yaw := 0.0
    var best_distance := INF
    var best_forward_dot := -1.0
    var best_score := INF

    # Scan a bounded carry arc around hand.r. A 5-degree grid is deterministic,
    # cheap (31 candidates), and lets the rig select the smallest correction
    # that makes the actual foregrip reachable instead of hard-coding one model.
    var step_count := int(round(AUTOFIT_MAX_YAW_DEG / AUTOFIT_STEP_DEG))
    for step: int in range(-step_count, step_count + 1):
        var yaw_offset := float(step) * AUTOFIT_STEP_DEG
        _apply_locked_carry(holder, socket, hand_transform.origin, player, carry_deg, yaw_offset)
        var weapon_forward := (-holder.global_transform.basis.z).normalized()
        var forward_dot := weapon_forward.dot(player_forward)
        if forward_dot < AUTOFIT_MIN_FORWARD_DOT:
            continue
        var distance_m := support.global_position.distance_to(left_shoulder)
        var outside_m := maxf(0.0, distance_m - reach_m)
        # Reachability dominates. Inside the reachable volume, prefer the least
        # yaw correction so the weapon stays visually forward and readable.
        var score := outside_m * 100.0 + absf(yaw_offset) * 0.001 - forward_dot * 0.0001
        if score < best_score:
            best_score = score
            best_yaw = yaw_offset
            best_distance = distance_m
            best_forward_dot = forward_dot

    _apply_locked_carry(holder, socket, hand_transform.origin, player, carry_deg, best_yaw)
    var grip_gap_m := socket.global_position.distance_to(hand_transform.origin)
    var grip_locked := grip_gap_m <= HAND_LOCK_EPSILON_M
    var reachable := best_distance <= reach_m + 0.001

    holder.set_meta("combat_weapon_support_autofit_active", true)
    holder.set_meta("combat_weapon_support_autofit_weapon", weapon_id)
    holder.set_meta("combat_weapon_support_autofit_yaw_deg", best_yaw)
    holder.set_meta("combat_weapon_support_autofit_distance_m", best_distance)
    holder.set_meta("combat_weapon_support_autofit_reach_m", reach_m)
    holder.set_meta("combat_weapon_support_autofit_forward_dot", best_forward_dot)
    holder.set_meta("combat_weapon_support_autofit_reachable", reachable)
    holder.set_meta("combat_weapon_orientation_locked", grip_locked)
    player.set_meta("combat_weapon_support_autofit_active", true)
    player.set_meta("combat_weapon_support_autofit_yaw_deg", best_yaw)
    player.set_meta("combat_weapon_support_autofit_distance_m", best_distance)
    player.set_meta("combat_weapon_support_autofit_reach_m", reach_m)
    player.set_meta("combat_weapon_support_autofit_forward_dot", best_forward_dot)
    player.set_meta("combat_weapon_support_autofit_reachable", reachable)
    player.set_meta("combat_weapon_orientation_locked", grip_locked)
    player.set_meta("combat_weapon_orientation_gap_m", grip_gap_m)
    return grip_locked

func _apply_locked_carry(holder: Node3D, socket: Node3D, hand_world: Vector3, player: CharacterBody3D, carry_deg: Vector3, yaw_offset_deg: float) -> void:
    holder.global_rotation = player.global_rotation + Vector3(
        deg_to_rad(carry_deg.x),
        deg_to_rad(carry_deg.y + yaw_offset_deg),
        deg_to_rad(carry_deg.z)
    )
    holder.global_position += hand_world - socket.global_position

func _clear_autofit_meta(holder: Node3D, player: CharacterBody3D) -> void:
    if holder != null:
        holder.set_meta("combat_weapon_support_autofit_active", false)
    if player != null:
        player.set_meta("combat_weapon_support_autofit_active", false)

static func _transition_progress(player: CharacterBody3D) -> float:
    var started := int(player.get_meta("combat_weapon_switch_phase_started_ms", 0))
    var end := int(player.get_meta("combat_weapon_switch_phase_end_ms", 0))
    if end <= started:
        return 1.0
    return clampf(float(Time.get_ticks_msec() - started) / float(end - started), 0.0, 1.0)
