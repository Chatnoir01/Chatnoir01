extends "res://game/scripts/player_combat_arsenal_runtime.gd"

# Combat V3 hardening: safe fire preflight + hand-locked recoil + contact-timed,
# buffered melee. This runtime is the single production owner of attack inputs.

const WEAPON_FLINCH_THROTTLE_MS := 90
const ACTION_LOCK_EXTRA_MS := 70
const MELEE_BUFFER_MS := 180
const MELEE_MOVES_V2: Array[Dictionary] = [
    {"id": &"jab_left", "label": "DIRECT GAUCHE", "limb": "LeftArm", "windup_s": 0.055, "active_s": 0.085, "recover_s": 0.19, "yaw_deg": -11.0, "roll_deg": 3.0, "lunge_m": 0.08, "limb_x_deg": -78.0, "limb_z_deg": -4.0},
    {"id": &"cross_right", "label": "DIRECT DROIT", "limb": "RightArm", "windup_s": 0.070, "active_s": 0.090, "recover_s": 0.20, "yaw_deg": 18.0, "roll_deg": -5.0, "lunge_m": 0.12, "limb_x_deg": -92.0, "limb_z_deg": 5.0},
    {"id": &"hook_left", "label": "CROCHET GAUCHE", "limb": "LeftArm", "windup_s": 0.085, "active_s": 0.105, "recover_s": 0.22, "yaw_deg": -28.0, "roll_deg": 8.0, "lunge_m": 0.07, "limb_x_deg": -63.0, "limb_z_deg": -36.0},
    {"id": &"hook_right", "label": "CROCHET DROIT", "limb": "RightArm", "windup_s": 0.085, "active_s": 0.105, "recover_s": 0.22, "yaw_deg": 29.0, "roll_deg": -8.0, "lunge_m": 0.07, "limb_x_deg": -64.0, "limb_z_deg": 36.0},
    {"id": &"uppercut_right", "label": "UPPERCUT DROIT", "limb": "RightArm", "windup_s": 0.095, "active_s": 0.100, "recover_s": 0.24, "yaw_deg": 15.0, "roll_deg": -4.0, "lunge_m": 0.09, "limb_x_deg": -48.0, "limb_z_deg": 18.0},
    {"id": &"body_hook_left", "label": "CROCHET CORPS", "limb": "LeftArm", "windup_s": 0.090, "active_s": 0.105, "recover_s": 0.23, "yaw_deg": -24.0, "roll_deg": 7.0, "lunge_m": 0.08, "limb_x_deg": -58.0, "limb_z_deg": -30.0},
    {"id": &"front_kick_right", "label": "COUP DE PIED", "limb": "RightLeg", "windup_s": 0.095, "active_s": 0.115, "recover_s": 0.25, "yaw_deg": 8.0, "roll_deg": -2.0, "lunge_m": 0.16, "limb_x_deg": -58.0, "limb_z_deg": 0.0},
    {"id": &"low_kick_left", "label": "LOW KICK GAUCHE", "limb": "LeftLeg", "windup_s": 0.090, "active_s": 0.110, "recover_s": 0.25, "yaw_deg": -15.0, "roll_deg": 5.0, "lunge_m": 0.12, "limb_x_deg": -50.0, "limb_z_deg": -18.0},
    {"id": &"push_kick_right", "label": "PUSH KICK", "limb": "RightLeg", "windup_s": 0.105, "active_s": 0.120, "recover_s": 0.27, "yaw_deg": 4.0, "roll_deg": -2.0, "lunge_m": 0.19, "limb_x_deg": -66.0, "limb_z_deg": 0.0},
    {"id": &"elbow_right", "label": "COUDE DROIT", "limb": "RightArm", "windup_s": 0.080, "active_s": 0.090, "recover_s": 0.22, "yaw_deg": 32.0, "roll_deg": -9.0, "lunge_m": 0.06, "limb_x_deg": -44.0, "limb_z_deg": 40.0},
]

var _buffered_melee_move: Dictionary = {}
var _buffered_melee_until_ms := 0
var _buffered_melee_player_id := 0

func _process(delta: float) -> void:
    super._process(delta)
    var player := _current_player()
    if player != null:
        player.set_meta("combat_attack_input_owner", "arsenal")
        _tick_melee_buffer(player)

func equip_weapon(player: CharacterBody3D, weapon_id: StringName) -> bool:
    var equipped := super.equip_weapon(player, weapon_id)
    if equipped:
        _next_fire_ms = 0
        if weapon_id != &"":
            _clear_melee_buffer(player, "weapon_equipped")
    return equipped

func _rebuild_weapon_visual(player: CharacterBody3D) -> void:
    if _weapon_visual != null and is_instance_valid(_weapon_visual):
        _weapon_visual.name = "CombatWeaponVisualRetired_%d" % _weapon_visual.get_instance_id()
    super._rebuild_weapon_visual(player)
    if _weapon_visual != null and is_instance_valid(_weapon_visual):
        _weapon_visual.name = "CombatWeaponVisual"
        _weapon_visual.set_meta("combat_weapon_canonical_holder", true)
        _weapon_visual.set_meta("combat_weapon_holder_weapon_id", _equipped_weapon)

func request_fire(player: CharacterBody3D) -> Dictionary:
    var player_available := player != null and is_instance_valid(player) and player.is_inside_tree()
    var armed := is_armed()
    var camera_available := false
    if player_available and armed:
        camera_available = _player_camera(player) != null
    var preflight := fire_preflight_reason(player_available, armed, camera_available)
    if preflight != &"":
        return {"fired": false, "reason": String(preflight)}
    var result := super.request_fire(player)
    if bool(result.get("fired", false)):
        var pose_runtime := get_node_or_null("/root/CombatAuthoredPoseRuntime")
        if pose_runtime != null and pose_runtime.has_method("request_shot_pose"):
            pose_runtime.call("request_shot_pose", player, _equipped_weapon)
    return result

func set_aiming(player: CharacterBody3D, aiming: bool) -> bool:
    if player == null or not is_instance_valid(player) or not is_armed():
        return false
    _aiming = aiming
    player.set_meta("combat_weapon_aiming", aiming)
    _refresh_hud(player)
    return true

func _apply_recoil(profile: Dictionary) -> void:
    _recoil_pitch = minf(_recoil_pitch + float(profile.get("recoil_pitch_deg", 1.0)), 6.5)
    var yaw_amount := float(profile.get("recoil_yaw_deg", 0.25))
    _recoil_yaw = clampf(_recoil_yaw + _rng.randf_range(-yaw_amount, yaw_amount), -3.0, 3.0)
    if _weapon_visual != null and is_instance_valid(_weapon_visual):
        _weapon_visual.set_meta("combat_weapon_recoil_mount_locked", true)

func request_melee_combo(player: CharacterBody3D) -> Dictionary:
    if player == null or not is_instance_valid(player):
        return {"hit": false, "reason": "player_unavailable"}
    if is_armed():
        return {"hit": false, "reason": "weapon_equipped"}
    var melee_runtime := get_node_or_null("/root/PlayerMeleeCombatRuntime")
    if melee_runtime == null or not melee_runtime.has_method("request_attack_with_move"):
        return {"hit": false, "reason": "melee_runtime_unavailable"}

    var now := Time.get_ticks_msec()
    if now - _last_melee_ms > COMBO_RESET_MS and _buffered_melee_move.is_empty():
        _combo_index = 0

    var recovery_until := int(player.get_meta("combat_attack_recovery_until_ms", 0))
    if now < recovery_until:
        var remaining_ms := recovery_until - now
        if remaining_ms <= MELEE_BUFFER_MS:
            if not _buffered_melee_move.is_empty():
                return {
                    "hit": false,
                    "buffered": true,
                    "reason": "buffer_full",
                    "move_id": _buffered_melee_move.get("id", &""),
                    "remaining_ms": remaining_ms,
                }
            var buffered_move := melee_move_v2(_combo_index)
            _buffered_melee_move = buffered_move.duplicate(true)
            _buffered_melee_until_ms = now + MELEE_BUFFER_MS
            _buffered_melee_player_id = player.get_instance_id()
            player.set_meta("combat_melee_buffered", true)
            player.set_meta("combat_melee_buffered_move_id", buffered_move.get("id", &""))
            player.set_meta("combat_melee_buffer_until_ms", _buffered_melee_until_ms)
            return {
                "hit": false,
                "buffered": true,
                "reason": "buffered",
                "move_id": buffered_move.get("id", &""),
                "remaining_ms": remaining_ms,
            }
        return {"hit": false, "reason": "recovery", "remaining_ms": remaining_ms}

    return _commit_melee_move(player, melee_move_v2(_combo_index), melee_runtime)

func _commit_melee_move(player: CharacterBody3D, move: Dictionary, melee_runtime: Node = null) -> Dictionary:
    if player == null or not is_instance_valid(player):
        return {"hit": false, "reason": "player_unavailable"}
    if melee_runtime == null:
        melee_runtime = get_node_or_null("/root/PlayerMeleeCombatRuntime")
    if melee_runtime == null or not melee_runtime.has_method("request_attack_with_move"):
        return {"hit": false, "reason": "melee_runtime_unavailable"}

    var previous_move_id: Variant = player.get_meta("combat_move_id", &"")
    var previous_move_label: Variant = player.get_meta("combat_move_label", "")
    player.set_meta("combat_move_id", move.get("id", &""))
    player.set_meta("combat_move_label", move.get("label", ""))
    player.set_meta("combat_attack_input_owner", "arsenal")

    var result_variant: Variant = melee_runtime.call("request_attack_with_move", player, move)
    if not result_variant is Dictionary:
        player.set_meta("combat_move_id", previous_move_id)
        player.set_meta("combat_move_label", previous_move_label)
        return {"hit": false, "reason": "invalid_melee_result"}
    var result := result_variant as Dictionary
    if not bool(result.get("pending", false)):
        player.set_meta("combat_move_id", previous_move_id)
        player.set_meta("combat_move_label", previous_move_label)
        return result

    var now := Time.get_ticks_msec()
    var attack_count := int(player.get_meta("combat_attack_count", 0))
    _combo_index = next_combo_index_v2(_combo_index, true, attack_count)
    _last_melee_ms = now
    player.set_meta("combat_combo_step", _combo_index)
    player.set_meta("combat_combo_next_move_id", melee_move_v2(_combo_index).get("id", &""))
    _animate_melee_move(player, move)
    result["move_id"] = move.get("id", &"")
    result["move_label"] = move.get("label", "")
    result["next_move_id"] = melee_move_v2(_combo_index).get("id", &"")
    return result

func _tick_melee_buffer(player: CharacterBody3D) -> void:
    if _buffered_melee_move.is_empty():
        return
    var now := Time.get_ticks_msec()
    if player.get_instance_id() != _buffered_melee_player_id or is_armed():
        _clear_melee_buffer(player, "owner_changed")
        return
    if now > _buffered_melee_until_ms:
        _clear_melee_buffer(player, "expired")
        return
    var recovery_until := int(player.get_meta("combat_attack_recovery_until_ms", 0))
    if now < recovery_until:
        return

    var move := _buffered_melee_move.duplicate(true)
    _clear_melee_buffer(player, "released")
    var result := _commit_melee_move(player, move)
    player.set_meta("combat_melee_buffer_fired_ms", now)
    player.set_meta("combat_melee_buffer_fired", bool(result.get("pending", false)))

func _clear_melee_buffer(player: CharacterBody3D, reason: String) -> void:
    _buffered_melee_move.clear()
    _buffered_melee_until_ms = 0
    _buffered_melee_player_id = 0
    if player != null and is_instance_valid(player):
        player.set_meta("combat_melee_buffered", false)
        player.set_meta("combat_melee_buffer_clear_reason", reason)
        player.set_meta("combat_melee_buffered_move_id", &"")

func _animate_melee_move(player: CharacterBody3D, move: Dictionary) -> void:
    var total_ms := int(round((float(move.get("windup_s", 0.07)) + float(move.get("active_s", 0.09)) + float(move.get("recover_s", 0.20))) * 1000.0))
    player.set_meta("combat_action_lock_until_ms", Time.get_ticks_msec() + total_ms + ACTION_LOCK_EXTRA_MS)
    player.set_meta("combat_melee_anim_started_ms", Time.get_ticks_msec())
    super._animate_melee_move(player, move)
    _animate_melee_weight_transfer(player, move)
    var pose_runtime := get_node_or_null("/root/CombatAuthoredPoseRuntime")
    if pose_runtime != null and pose_runtime.has_method("request_melee_pose"):
        pose_runtime.call("request_melee_pose", player, move)

func _animate_melee_weight_transfer(player: CharacterBody3D, move: Dictionary) -> void:
    var visual := player.get_node_or_null("VisualUpgrade") as Node3D
    if visual == null:
        return
    var profile := melee_weight_profile(StringName(move.get("id", &"")))
    var windup := float(move.get("windup_s", 0.07))
    var active := float(move.get("active_s", 0.09))
    var recover := float(move.get("recover_s", 0.20))
    var base_x := visual.rotation.x
    var base_y := visual.position.y
    var pitch := deg_to_rad(float(profile.get("pitch_deg", -3.0)))
    var drop_m := float(profile.get("drop_m", 0.015))
    player.set_meta("combat_melee_weight_profile", profile.get("id", &"neutral"))
    player.set_meta("combat_melee_weight_drop_m", drop_m)
    var body_tween := create_tween()
    body_tween.tween_property(visual, "rotation:x", base_x - pitch * 0.35, windup)
    body_tween.parallel().tween_property(visual, "position:y", base_y - drop_m * 0.35, windup)
    body_tween.tween_property(visual, "rotation:x", base_x + pitch, active)
    body_tween.parallel().tween_property(visual, "position:y", base_y - drop_m, active)
    body_tween.tween_property(visual, "rotation:x", base_x, recover)
    body_tween.parallel().tween_property(visual, "position:y", base_y, recover)

    var brace_name := String(profile.get("brace_limb", ""))
    var brace := visual.get_node_or_null(brace_name) as Node3D
    if brace != null:
        var brace_base := brace.rotation
        var brace_target := brace_base
        brace_target.x += deg_to_rad(float(profile.get("brace_x_deg", 0.0)))
        brace_target.z += deg_to_rad(float(profile.get("brace_z_deg", 0.0)))
        var brace_tween := create_tween()
        brace_tween.tween_property(brace, "rotation", brace_target, windup + active)
        brace_tween.tween_property(brace, "rotation", brace_base, recover)

func _apply_weapon_hit(npc: NpcAgent, player: CharacterBody3D, damage: float) -> bool:
    if player != null and is_instance_valid(player):
        player.set_meta("combat_weapon_hit_inflight", true)
    var applied := super._apply_weapon_hit(npc, player, damage)
    if player != null and is_instance_valid(player):
        player.set_meta("combat_weapon_hit_inflight", false)
    if not applied or npc == null or not is_instance_valid(npc):
        return applied
    _retag_weapon_hit_feedback(npc, damage)
    if not bool(npc.get_meta("melee_knocked_out", false)):
        _animate_weapon_flinch(npc, player, damage)
    return true

func _retag_weapon_hit_feedback(npc: NpcAgent, damage: float) -> void:
    if bool(npc.get_meta("melee_knocked_out", false)):
        return
    var reaction := StringName(npc.get_meta("melee_reaction", &"hit"))
    for child: Node in npc.get_children():
        if child is Label3D and child.name == "MeleeHurtFeedback":
            var marker := child as Label3D
            marker.text = "IMPACT  -%d\n%s" % [int(round(maxf(damage, 0.0))), String(reaction).to_upper()]

func _animate_weapon_flinch(npc: NpcAgent, player: CharacterBody3D, damage: float) -> void:
    var now := Time.get_ticks_msec()
    if now < int(npc.get_meta("combat_weapon_flinch_until_ms", 0)):
        return
    npc.set_meta("combat_weapon_flinch_until_ms", now + WEAPON_FLINCH_THROTTLE_MS)
    var visual := npc.get_node_or_null("ProfiledNpcProxy") as Node3D
    if visual == null:
        visual = npc.get_node_or_null("VisualUpgrade") as Node3D
    if visual == null:
        return
    var sign := -1.0 if posmod(npc.get_instance_id(), 2) == 0 else 1.0
    if player != null and is_instance_valid(player):
        var local_hit := npc.to_local(player.global_position)
        if absf(local_hit.x) > 0.05:
            sign = -signf(local_hit.x)
    var angle_deg := weapon_flinch_angle_deg(damage)
    var base_z := visual.rotation.z
    var base_x := visual.position.x
    npc.set_meta("combat_weapon_flinch_angle_deg", angle_deg)
    var tween := create_tween()
    tween.tween_property(visual, "rotation:z", base_z + deg_to_rad(angle_deg * sign), 0.045)
    tween.parallel().tween_property(visual, "position:x", base_x + 0.035 * sign, 0.045)
    tween.tween_property(visual, "rotation:z", base_z, 0.13)
    tween.parallel().tween_property(visual, "position:x", base_x, 0.13)

static func fire_preflight_reason(player_available: bool, armed: bool, camera_available: bool) -> StringName:
    if not player_available:
        return &"player_unavailable"
    if not armed:
        return &"unarmed"
    if not camera_available:
        return &"camera_unavailable"
    return &""

static func weapon_flinch_angle_deg(damage: float) -> float:
    var t := clampf(maxf(damage, 0.0) / 55.0, 0.0, 1.0)
    return lerpf(3.5, 10.0, t)

static func melee_move_v2(index: int) -> Dictionary:
    if MELEE_MOVES_V2.is_empty():
        return {}
    return MELEE_MOVES_V2[posmod(index, MELEE_MOVES_V2.size())].duplicate(true)

static func next_combo_index_v2(current_index: int, landed: bool, attack_count: int) -> int:
    if not landed:
        return 0
    var step := 1
    if posmod(attack_count, 4) == 0:
        step = 2
    elif posmod(attack_count, 7) == 0:
        step = 3
    return posmod(current_index + step, MELEE_MOVES_V2.size())

# Backward-compatible contract used by the existing Combat Arsenal gate.
static func next_combo_index(current_index: int, landed: bool, attack_count: int) -> int:
    if not landed:
        return 0
    match current_index:
        0:
            return 1
        1:
            return 3 if posmod(attack_count, 3) == 0 else 2
        2:
            return 3
        _:
            return 0

static func melee_weight_profile(move_id: StringName) -> Dictionary:
    match move_id:
        &"jab_left":
            return {"id": &"jab_drive", "pitch_deg": -2.5, "drop_m": 0.012, "brace_limb": "RightLeg", "brace_x_deg": -4.0, "brace_z_deg": 1.0}
        &"cross_right":
            return {"id": &"cross_drive", "pitch_deg": -4.2, "drop_m": 0.018, "brace_limb": "LeftLeg", "brace_x_deg": -8.0, "brace_z_deg": -2.0}
        &"hook_left":
            return {"id": &"hook_rotation", "pitch_deg": -3.4, "drop_m": 0.020, "brace_limb": "RightLeg", "brace_x_deg": -7.0, "brace_z_deg": 4.0}
        &"hook_right", &"body_hook_left", &"uppercut_right", &"elbow_right":
            return {"id": &"rotation_drive", "pitch_deg": -3.8, "drop_m": 0.020, "brace_limb": "LeftLeg", "brace_x_deg": -7.0, "brace_z_deg": -3.0}
        &"front_kick_right":
            return {"id": &"kick_balance", "pitch_deg": 5.5, "drop_m": 0.027, "brace_limb": "LeftLeg", "brace_x_deg": -12.0, "brace_z_deg": -3.0}
        &"low_kick_left":
            return {"id": &"kick_balance_left", "pitch_deg": 5.0, "drop_m": 0.025, "brace_limb": "RightLeg", "brace_x_deg": -11.0, "brace_z_deg": 3.0}
        &"push_kick_right":
            return {"id": &"push_kick_balance", "pitch_deg": 6.0, "drop_m": 0.030, "brace_limb": "LeftLeg", "brace_x_deg": -13.0, "brace_z_deg": -2.0}
        _:
            return {"id": &"neutral", "pitch_deg": -2.0, "drop_m": 0.010, "brace_limb": "", "brace_x_deg": 0.0, "brace_z_deg": 0.0}