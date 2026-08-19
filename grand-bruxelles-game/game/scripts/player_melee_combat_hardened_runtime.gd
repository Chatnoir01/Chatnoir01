extends "res://game/scripts/player_melee_combat_runtime.gd"

# Feel/defence layer over the stable melee runtime.
# Keeps hit detection, KO, loot and world reactions in the base implementation.

const PERFECT_GUARD_WINDOW_MS := 180
const COUNTER_TELEGRAPH_MS := 260
const COUNTER_STRIKE_IMPACT_MS := 70
const COUNTER_STRIKE_RECOVER_MS := 150
const COUNTER_RANGE_M := 2.05
const COUNTER_CONTACT_GRACE_M := 0.16
const MELEE_FLINCH_THROTTLE_MS := 105

func set_guarding(player: CharacterBody3D, enabled: bool) -> void:
    if player == null or not is_instance_valid(player):
        return
    var was_guarding := is_guarding(player)
    super.set_guarding(player, enabled)
    var now_guarding := is_guarding(player)
    if now_guarding and not was_guarding:
        player.set_meta("combat_guard_started_ms", Time.get_ticks_msec())
        _animate_guard_limbs(player, true)
    elif not now_guarding and was_guarding:
        player.set_meta("combat_guard_released_ms", Time.get_ticks_msec())
        _animate_guard_limbs(player, false)

func resolve_counter_hit(player: CharacterBody3D) -> int:
    if player == null or not is_instance_valid(player):
        return 0
    var now := Time.get_ticks_msec()
    var dodge_active := now < int(player.get_meta("combat_dodge_until_ms", 0))
    var guarding := is_guarding(player)
    var guard_age_ms := 999999
    if guarding:
        guard_age_ms = maxi(0, now - int(player.get_meta("combat_guard_started_ms", now)))
    var outcome := counter_outcome(guarding, guard_age_ms, dodge_active)
    var kind := StringName(outcome.get("kind", &"hit"))
    if kind == &"evade":
        player.set_meta("combat_last_counter_damage", 0)
        player.set_meta("combat_last_evade_ms", now)
        player.set_meta("combat_evade_count", int(player.get_meta("combat_evade_count", 0)) + 1)
        _show_feedback("ESQUIVÉ", 260)
        _animate_defence_snap(player, -1.0)
        return 0
    if kind == &"parry":
        player.set_meta("combat_last_counter_damage", 0)
        player.set_meta("combat_last_parry_ms", now)
        player.set_meta("combat_parry_count", int(player.get_meta("combat_parry_count", 0)) + 1)
        player.set_meta("combat_parry_bonus_until_ms", now + 420)
        _show_feedback("PARRÉ", 300)
        _animate_defence_snap(player, 1.0)
        return 0
    var damage := super.resolve_counter_hit(player)
    if damage > 0:
        _animate_counter_received(player, guarding, damage)
    return damage

func _apply_hit(npc: NpcAgent, player: CharacterBody3D, damage: float) -> StringName:
    var reaction := super._apply_hit(npc, player, damage)
    if npc == null or not is_instance_valid(npc) or reaction == &"ko":
        return reaction
    if player != null and bool(player.get_meta("combat_weapon_hit_inflight", false)):
        npc.set_meta("combat_last_melee_move_id", &"")
        npc.set_meta("combat_last_melee_reaction_side", "weapon")
        return reaction
    var move_id := StringName(player.get_meta("combat_move_id", &"")) if player != null else &""
    var profile := melee_reaction_profile(move_id)
    npc.set_meta("combat_last_melee_move_id", move_id)
    npc.set_meta("combat_last_melee_reaction_side", profile.get("side", "center"))
    _animate_directional_hit(npc, profile)

    var state_variant: Variant = _reaction_states.get(npc.get_instance_id(), {})
    if state_variant is Dictionary:
        var state := state_variant as Dictionary
        if not state.is_empty():
            var stagger_ms := int(profile.get("stagger_ms", 360))
            state["next_counter_ms"] = maxi(int(state.get("next_counter_ms", 0)), Time.get_ticks_msec() + stagger_ms)
            _reaction_states[npc.get_instance_id()] = state
    return reaction

func _tick_reactions(now: int) -> void:
    var expired: Array[int] = []
    for raw_id: Variant in _reaction_states.keys():
        var instance_id := int(raw_id)
        var state: Dictionary = _reaction_states[instance_id]
        var npc_ref: WeakRef = state.get("npc")
        var player_ref: WeakRef = state.get("player")
        var npc := npc_ref.get_ref() as NpcAgent if npc_ref != null else null
        var player := player_ref.get_ref() as CharacterBody3D if player_ref != null else null
        if npc == null or not is_instance_valid(npc) or bool(npc.get_meta("melee_knocked_out", false)):
            expired.append(instance_id)
            continue

        var reaction := StringName(state.get("reaction", &""))
        if now >= int(state.get("expires_ms", 0)):
            if reaction == &"defend":
                npc.movement_held = false
            npc.set_meta("melee_hurt_feedback", false)
            npc.set_meta("combat_counter_telegraph_until_ms", 0)
            npc.set_meta("combat_counter_strike_impact_ms", 0)
            expired.append(instance_id)
            continue
        if reaction != &"fight" or player == null or not is_instance_valid(player):
            continue

        npc.behavior.set_destination(player.global_position)
        var planar_distance := Vector2(
            npc.global_position.x - player.global_position.x,
            npc.global_position.z - player.global_position.z
        ).length()
        var strike_impact_ms := int(state.get("counter_strike_impact_ms", 0))
        if strike_impact_ms > 0:
            if now >= strike_impact_ms:
                var dealt := 0
                if counter_contact_allowed(planar_distance):
                    dealt = resolve_counter_hit(player)
                else:
                    player.set_meta("combat_last_counter_damage", 0)
                    player.set_meta("combat_last_counter_whiff_ms", now)
                    _show_feedback("RATÉ", 170)
                npc.set_meta("combat_last_counter_damage", dealt)
                npc.set_meta("combat_last_counter_resolved_ms", now)
                npc.set_meta("combat_counter_strike_impact_ms", 0)
                state["counter_strike_impact_ms"] = 0
                state["next_counter_ms"] = now + COUNTER_COOLDOWN_MS
                _reaction_states[instance_id] = state
            continue

        var windup_until := int(state.get("counter_windup_until_ms", 0))
        if planar_distance > COUNTER_RANGE_M:
            if windup_until > 0:
                state["counter_windup_until_ms"] = 0
                npc.set_meta("combat_counter_telegraph_until_ms", 0)
                _reaction_states[instance_id] = state
            continue

        if windup_until > 0:
            if now >= windup_until:
                var side := StringName(state.get("counter_strike_side", &"right"))
                var impact_ms := now + COUNTER_STRIKE_IMPACT_MS
                state["counter_windup_until_ms"] = 0
                state["counter_strike_impact_ms"] = impact_ms
                _reaction_states[instance_id] = state
                npc.set_meta("combat_counter_telegraph_until_ms", 0)
                npc.set_meta("combat_counter_strike_impact_ms", impact_ms)
                npc.set_meta("combat_counter_strike_side", side)
                _animate_counter_strike(npc, side)
            continue

        if now >= int(state.get("next_counter_ms", 0)):
            var telegraph_until := now + COUNTER_TELEGRAPH_MS
            var telegraph_count := int(npc.get_meta("combat_counter_telegraph_count", 0)) + 1
            var side := counter_strike_side(npc.variation_seed, telegraph_count)
            state["counter_windup_until_ms"] = telegraph_until
            state["counter_strike_side"] = side
            _reaction_states[instance_id] = state
            npc.set_meta("combat_counter_telegraph_until_ms", telegraph_until)
            npc.set_meta("combat_counter_telegraph_count", telegraph_count)
            npc.set_meta("combat_counter_strike_side", side)
            _animate_counter_telegraph(npc, side)

    for instance_id: int in expired:
        _reaction_states.erase(instance_id)

func _animate_guard_limbs(player: CharacterBody3D, enabled: bool) -> void:
    var visual := player.get_node_or_null("VisualUpgrade") as Node3D
    if visual == null:
        return
    var names: Array[String] = ["LeftArm", "RightArm"]
    for index: int in range(names.size()):
        var limb := visual.get_node_or_null(names[index]) as Node3D
        if limb == null:
            continue
        if not limb.has_meta("combat_guard_base_rotation"):
            limb.set_meta("combat_guard_base_rotation", limb.rotation)
        var base_rotation: Vector3 = limb.get_meta("combat_guard_base_rotation", limb.rotation)
        var side := -1.0 if index == 0 else 1.0
        var target := base_rotation
        if enabled:
            target += Vector3(-0.72, 0.0, side * 0.34)
        var tween := create_tween()
        tween.tween_property(limb, "rotation", target, 0.10 if enabled else 0.13)

func _animate_defence_snap(player: CharacterBody3D, direction_sign: float) -> void:
    var visual := player.get_node_or_null("VisualUpgrade") as Node3D
    if visual == null:
        return
    var base_z := visual.rotation.z
    var tween := create_tween()
    tween.tween_property(visual, "rotation:z", base_z + 0.10 * direction_sign, 0.045)
    tween.tween_property(visual, "rotation:z", base_z, 0.11)

func _animate_counter_received(player: CharacterBody3D, guarded: bool, damage: int) -> void:
    var visual := player.get_node_or_null("VisualUpgrade") as Node3D
    if visual == null:
        return
    var strength := 0.38 if guarded else clampf(float(damage) / float(COUNTER_DAMAGE), 0.55, 1.0)
    var direction_sign := -1.0 if posmod(int(player.get_meta("combat_hit_reaction_count", 0)), 2) == 0 else 1.0
    player.set_meta("combat_hit_reaction_count", int(player.get_meta("combat_hit_reaction_count", 0)) + 1)
    player.set_meta("combat_last_hit_reaction_strength", strength)
    var base_z := visual.rotation.z
    var base_x := visual.position.x
    var tween := create_tween()
    tween.tween_property(visual, "rotation:z", base_z + 0.13 * direction_sign * strength, 0.055)
    tween.parallel().tween_property(visual, "position:x", base_x + 0.055 * direction_sign * strength, 0.055)
    tween.tween_property(visual, "rotation:z", base_z, 0.15)
    tween.parallel().tween_property(visual, "position:x", base_x, 0.15)

func _animate_directional_hit(npc: NpcAgent, profile: Dictionary) -> void:
    var now := Time.get_ticks_msec()
    if now < int(npc.get_meta("combat_melee_flinch_until_ms", 0)):
        return
    npc.set_meta("combat_melee_flinch_until_ms", now + MELEE_FLINCH_THROTTLE_MS)
    var visual := _npc_visual(npc)
    if visual == null:
        return
    var base_z := visual.rotation.z
    var base_y := visual.rotation.y
    var roll := deg_to_rad(float(profile.get("roll_deg", 5.0)))
    var yaw := deg_to_rad(float(profile.get("yaw_deg", 0.0)))
    var tween := create_tween()
    tween.tween_property(visual, "rotation:z", base_z + roll, 0.05)
    tween.parallel().tween_property(visual, "rotation:y", base_y + yaw, 0.05)
    tween.tween_property(visual, "rotation:z", base_z, 0.14)
    tween.parallel().tween_property(visual, "rotation:y", base_y, 0.14)

func _animate_counter_telegraph(npc: NpcAgent, side: StringName) -> void:
    var visual := _npc_visual(npc)
    if visual != null:
        var base_x := visual.rotation.x
        var base_y := visual.rotation.y
        var side_sign := -1.0 if side == &"left" else 1.0
        var tween := create_tween()
        tween.tween_property(visual, "rotation:x", base_x - 0.14, 0.10)
        tween.parallel().tween_property(visual, "rotation:y", base_y - 0.10 * side_sign, 0.10)
        tween.tween_interval(maxf(float(COUNTER_TELEGRAPH_MS) / 1000.0 - 0.15, 0.01))
        tween.tween_property(visual, "rotation:x", base_x, 0.05)
        tween.parallel().tween_property(visual, "rotation:y", base_y, 0.05)

    var limb := _npc_limb(npc, "LeftArm" if side == &"left" else "RightArm")
    if limb != null:
        if not limb.has_meta("combat_counter_base_rotation"):
            limb.set_meta("combat_counter_base_rotation", limb.rotation)
        var limb_base: Vector3 = limb.get_meta("combat_counter_base_rotation", limb.rotation)
        var windup_target := limb_base
        windup_target.x += 0.34
        windup_target.z += 0.16 if side == &"left" else -0.16
        var limb_tween := create_tween()
        limb_tween.tween_property(limb, "rotation", windup_target, 0.11)

    var marker := Label3D.new()
    marker.name = "CounterTelegraph"
    marker.text = "!"
    marker.position = Vector3(0.0, 2.22, 0.0)
    marker.font_size = 42
    marker.outline_size = 8
    npc.add_child(marker)
    var marker_tween := create_tween()
    marker_tween.tween_property(marker, "position:y", 2.40, float(COUNTER_TELEGRAPH_MS) / 1000.0)
    marker_tween.tween_callback(marker.queue_free)

func _animate_counter_strike(npc: NpcAgent, side: StringName) -> void:
    var limb := _npc_limb(npc, "LeftArm" if side == &"left" else "RightArm")
    var side_sign := -1.0 if side == &"left" else 1.0
    if limb != null:
        var base_rotation: Vector3 = limb.get_meta("combat_counter_base_rotation", limb.rotation)
        var strike_target := base_rotation
        strike_target.x -= 1.08
        strike_target.z += 0.22 * side_sign
        var limb_tween := create_tween()
        limb_tween.tween_property(limb, "rotation", strike_target, float(COUNTER_STRIKE_IMPACT_MS) / 1000.0)
        limb_tween.tween_property(limb, "rotation", base_rotation, float(COUNTER_STRIKE_RECOVER_MS) / 1000.0)

    var visual := _npc_visual(npc)
    if visual != null:
        var base_y := visual.rotation.y
        var base_z := visual.rotation.z
        var body_tween := create_tween()
        body_tween.tween_property(visual, "rotation:y", base_y + 0.18 * side_sign, float(COUNTER_STRIKE_IMPACT_MS) / 1000.0)
        body_tween.parallel().tween_property(visual, "rotation:z", base_z - 0.055 * side_sign, float(COUNTER_STRIKE_IMPACT_MS) / 1000.0)
        body_tween.tween_property(visual, "rotation:y", base_y, float(COUNTER_STRIKE_RECOVER_MS) / 1000.0)
        body_tween.parallel().tween_property(visual, "rotation:z", base_z, float(COUNTER_STRIKE_RECOVER_MS) / 1000.0)
    npc.set_meta("combat_counter_strike_count", int(npc.get_meta("combat_counter_strike_count", 0)) + 1)

func _npc_visual(npc: NpcAgent) -> Node3D:
    if npc == null:
        return null
    var visual := npc.get_node_or_null("VisualUpgrade") as Node3D
    if visual != null:
        return visual
    return npc.get_node_or_null("ProfiledNpcProxy") as Node3D

func _npc_limb(npc: NpcAgent, limb_name: String) -> Node3D:
    var visual := _npc_visual(npc)
    if visual != null:
        var direct := visual.get_node_or_null(limb_name) as Node3D
        if direct != null:
            return direct
    var found := npc.find_child(limb_name, true, false)
    return found as Node3D

static func counter_outcome(guarding: bool, guard_age_ms: int, dodge_active: bool) -> Dictionary:
    if dodge_active:
        return {"kind": &"evade", "damage": 0}
    if guarding and guard_age_ms >= 0 and guard_age_ms <= PERFECT_GUARD_WINDOW_MS:
        return {"kind": &"parry", "damage": 0}
    if guarding:
        return {"kind": &"block", "damage": GUARDED_COUNTER_DAMAGE}
    return {"kind": &"hit", "damage": COUNTER_DAMAGE}

static func counter_contact_allowed(distance_m: float) -> bool:
    return maxf(distance_m, 0.0) <= COUNTER_RANGE_M + COUNTER_CONTACT_GRACE_M

static func counter_strike_side(seed: int, counter_index: int) -> StringName:
    return &"left" if posmod(seed * 17 + counter_index * 11, 2) == 0 else &"right"

static func melee_reaction_profile(move_id: StringName) -> Dictionary:
    match move_id:
        &"jab_left":
            return {"side": "right", "roll_deg": 5.0, "yaw_deg": -3.0, "stagger_ms": 360}
        &"cross_right":
            return {"side": "left", "roll_deg": -7.0, "yaw_deg": 4.0, "stagger_ms": 420}
        &"hook_left":
            return {"side": "right", "roll_deg": 11.0, "yaw_deg": -8.0, "stagger_ms": 500}
        &"front_kick_right":
            return {"side": "center", "roll_deg": -4.0, "yaw_deg": 3.0, "stagger_ms": 620}
        _:
            return {"side": "center", "roll_deg": 4.0, "yaw_deg": 0.0, "stagger_ms": 360}
