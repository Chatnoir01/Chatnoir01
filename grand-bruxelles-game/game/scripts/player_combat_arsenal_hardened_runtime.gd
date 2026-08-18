extends "res://game/scripts/player_combat_arsenal_runtime.gd"

# Thin hardening layer over the feature-rich arsenal runtime.
# Keeps the base combat implementation stable while enforcing safe preflight rules.

const WEAPON_FLINCH_THROTTLE_MS := 90

func equip_weapon(player: CharacterBody3D, weapon_id: StringName) -> bool:
    var equipped := super.equip_weapon(player, weapon_id)
    if equipped:
        # Cadence belongs to the weapon that fired, not the next weapon selected.
        _next_fire_ms = 0
    return equipped

func request_fire(player: CharacterBody3D) -> Dictionary:
    var player_available := player != null and is_instance_valid(player) and player.is_inside_tree()
    var armed := is_armed()
    var camera_available := false
    if player_available and armed:
        camera_available = _player_camera(player) != null
    var preflight := fire_preflight_reason(player_available, armed, camera_available)
    if preflight != &"":
        return {"fired": false, "reason": String(preflight)}
    # Only the base implementation is allowed to consume ammo after preflight passes.
    return super.request_fire(player)

func set_aiming(player: CharacterBody3D, aiming: bool) -> bool:
    if player == null or not is_instance_valid(player) or not is_armed():
        return false
    _aiming = aiming
    player.set_meta("combat_weapon_aiming", aiming)
    _refresh_hud(player)
    return true

func request_melee_combo(player: CharacterBody3D) -> Dictionary:
    if player == null or not is_instance_valid(player):
        return {"hit": false, "reason": "player_unavailable"}
    if is_armed():
        return {"hit": false, "reason": "weapon_equipped"}
    var melee_runtime := get_node_or_null("/root/PlayerMeleeCombatRuntime")
    if melee_runtime == null or not melee_runtime.has_method("request_attack"):
        return {"hit": false, "reason": "melee_runtime_unavailable"}

    var now := Time.get_ticks_msec()
    if now - _last_melee_ms > COMBO_RESET_MS:
        _combo_index = 0
    var move := melee_move(_combo_index)

    # The melee runtime resolves its hit synchronously. Publish the move before
    # request_attack so directional hurt reactions see the correct hand/leg.
    var previous_move_id := player.get_meta("combat_move_id", &"")
    var previous_move_label := player.get_meta("combat_move_label", "")
    player.set_meta("combat_move_id", move.get("id", &""))
    player.set_meta("combat_move_label", move.get("label", ""))

    var result_variant: Variant = melee_runtime.call("request_attack", player)
    if not result_variant is Dictionary:
        player.set_meta("combat_move_id", previous_move_id)
        player.set_meta("combat_move_label", previous_move_label)
        return {"hit": false, "reason": "invalid_melee_result"}
    var result := result_variant as Dictionary
    if not result.has("recovery_ms"):
        player.set_meta("combat_move_id", previous_move_id)
        player.set_meta("combat_move_label", previous_move_label)
        return result

    _combo_index = (_combo_index + 1) % MELEE_MOVES.size()
    _last_melee_ms = now
    player.set_meta("combat_combo_step", _combo_index)
    _animate_melee_move(player, move)
    result["move_id"] = move.get("id", &"")
    result["move_label"] = move.get("label", "")
    return result

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
