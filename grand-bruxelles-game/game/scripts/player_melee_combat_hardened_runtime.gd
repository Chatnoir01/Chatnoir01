extends "res://game/scripts/player_melee_combat_runtime.gd"

# Production feel/defence layer over the stable melee resolver.
# Attack input ownership belongs to PlayerCombatArsenalRuntime; this service owns
# contact timing, hit resolution, guard/parry and NPC counter behaviour.

const PERFECT_GUARD_WINDOW_MS := 180
const COUNTER_TELEGRAPH_MS := 260
const COUNTER_STRIKE_IMPACT_MS := 70
const COUNTER_STRIKE_RECOVER_MS := 150
const COUNTER_RANGE_M := 2.05
const COUNTER_CONTACT_GRACE_M := 0.16
const MELEE_FLINCH_THROTTLE_MS := 105
const CONTACT_ACTIVE_FRACTION := 0.42
const MIN_POST_CONTACT_ACTIVE_MS := 35

var _pending_player_attack: Dictionary = {}

func _ready() -> void:
    super._ready()
    set_process(true)
    set_process_input(true)

func _process(delta: float) -> void:
    super._process(delta)
    var now := Time.get_ticks_msec()
    _tick_pending_player_attack(now)
    var player := _current_player()
    if player != null and is_instance_valid(player):
        player.set_meta("combat_attack_input_owner", "arsenal")

# Intentionally replaces the base input handler. Guard/loot stay here; F and
# left-click attacks are owned only by PlayerCombatArsenalRuntime in production.
func _input(event: InputEvent) -> void:
    var player := _current_player()
    if player == null:
        return
    player.set_meta("combat_attack_input_owner", "arsenal")

    if event is InputEventMouseButton:
        var mouse_event := event as InputEventMouseButton
        if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
            set_guarding(player, mouse_event.pressed)
            get_viewport().set_input_as_handled()
            return

    if event is InputEventKey:
        var key_event := event as InputEventKey
        if key_event.echo:
            return
        if key_event.keycode == KEY_G:
            set_guarding(player, key_event.pressed)
            get_viewport().set_input_as_handled()
            return
        if key_event.keycode == KEY_E and key_event.pressed:
            request_loot(player)
            get_viewport().set_input_as_handled()

func set_guarding(player: CharacterBody3D, enabled: bool) -> void:
    if player == null or not is_instance_valid(player):
        return
    if enabled and bool(player.get_meta("combat_attack_pending", false)):
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

func request_attack(player: CharacterBody3D) -> Dictionary:
    var move := {
        "id": StringName(player.get_meta("combat_move_id", &"")) if player != null and is_instance_valid(player) else &"",
        "windup_s": float(ATTACK_WINDUP_MS) / 1000.0,
        "active_s": float(ATTACK_ACTIVE_MS) / 1000.0,
        "recover_s": float(maxi(ATTACK_COOLDOWN_MS - ATTACK_WINDUP_MS - ATTACK_ACTIVE_MS, 1)) / 1000.0,
    }
    return request_attack_with_move(player, move)

func request_attack_with_move(player: CharacterBody3D, move: Dictionary) -> Dictionary:
    if player == null or not is_instance_valid(player) or not player.is_inside_tree():
        return {"hit": false, "pending": false, "reason": "player_unavailable"}
    if is_guarding(player):
        return {"hit": false, "pending": false, "reason": "guarding"}
    var now := Time.get_ticks_msec()
    if now < int(player.get_meta("combat_dodge_until_ms", 0)):
        return {"hit": false, "pending": false, "reason": "dodging"}
    var recovery_until := int(player.get_meta("combat_attack_recovery_until_ms", 0))
    if now < recovery_until:
        return {
            "hit": false,
            "pending": false,
            "reason": "recovery",
            "remaining_ms": recovery_until - now,
            "recovery_ms": recovery_until - int(player.get_meta("combat_attack_started_ms", now)),
        }
    if not _pending_player_attack.is_empty():
        var active_ref: WeakRef = _pending_player_attack.get("player")
        var active_player := active_ref.get_ref() as CharacterBody3D if active_ref != null else null
        if active_player != null and is_instance_valid(active_player):
            return {"hit": false, "pending": false, "reason": "attack_pending"}
        _pending_player_attack.clear()

    var move_id := StringName(move.get("id", &""))
    var windup_ms := maxi(1, int(round(float(move.get("windup_s", float(ATTACK_WINDUP_MS) / 1000.0)) * 1000.0)))
    var active_ms := maxi(1, int(round(float(move.get("active_s", float(ATTACK_ACTIVE_MS) / 1000.0)) * 1000.0)))
    var declared_recover_ms := maxi(1, int(round(float(move.get("recover_s", 0.20)) * 1000.0)))
    var contact_offset_ms := windup_ms + maxi(1, int(round(float(active_ms) * CONTACT_ACTIVE_FRACTION)))
    var impact_at_ms := now + contact_offset_ms
    var active_until_ms := now + windup_ms + active_ms
    var whiff_recovery_ms := maxi(melee_recovery_ms(move_id, false), windup_ms + active_ms + declared_recover_ms)
    var attack_recovery_until_ms := now + whiff_recovery_ms

    _next_attack_allowed_ms = attack_recovery_until_ms
    player.set_meta("combat_attack_input_owner", "arsenal")
    player.set_meta("combat_attack_started_ms", now)
    player.set_meta("combat_attack_impact_at_ms", impact_at_ms)
    player.set_meta("combat_attack_active_until_ms", active_until_ms)
    player.set_meta("combat_attack_recovery_until_ms", attack_recovery_until_ms)
    player.set_meta("combat_attack_phase", "windup")
    player.set_meta("combat_attack_pending", true)
    player.set_meta("combat_move_id", move_id)
    player.set_meta("combat_move_recovery_ms", whiff_recovery_ms)
    player.set_meta("combat_move_recovery_landed", false)
    player.set_meta("combat_attack_count", int(player.get_meta("combat_attack_count", 0)) + 1)

    _pending_player_attack = {
        "player": weakref(player),
        "move_id": move_id,
        "started_ms": now,
        "impact_ms": impact_at_ms,
        "active_until_ms": active_until_ms,
        "recovery_until_ms": attack_recovery_until_ms,
        "resolved": false,
    }
    return {
        "hit": false,
        "pending": true,
        "reason": "windup",
        "move_id": move_id,
        "impact_at_ms": impact_at_ms,
        "recovery_ms": whiff_recovery_ms,
    }

func _tick_pending_player_attack(now: int) -> void:
    if _pending_player_attack.is_empty():
        return
    var player_ref: WeakRef = _pending_player_attack.get("player")
    var player := player_ref.get_ref() as CharacterBody3D if player_ref != null else null
    if player == null or not is_instance_valid(player) or not player.is_inside_tree():
        _pending_player_attack.clear()
        return

    var resolved := bool(_pending_player_attack.get("resolved", false))
    var impact_ms := int(_pending_player_attack.get("impact_ms", 0))
    var active_until_ms := int(_pending_player_attack.get("active_until_ms", impact_ms + MIN_POST_CONTACT_ACTIVE_MS))
    var recovery_until_ms := int(_pending_player_attack.get("recovery_until_ms", active_until_ms + 1))

    if not resolved and now >= impact_ms:
        var result := perform_attack(player)
        var landed := bool(result.get("hit", false))
        var move_id := StringName(_pending_player_attack.get("move_id", &""))
        var recovery_ms := melee_recovery_ms(move_id, landed)
        var started_ms := int(_pending_player_attack.get("started_ms", now))
        recovery_until_ms = maxi(started_ms + recovery_ms, active_until_ms + MIN_POST_CONTACT_ACTIVE_MS)
        _next_attack_allowed_ms = recovery_until_ms
        _pending_player_attack["resolved"] = true
        _pending_player_attack["recovery_until_ms"] = recovery_until_ms
        player.set_meta("combat_attack_pending", false)
        player.set_meta("combat_attack_phase", "active" if now < active_until_ms else "recovery")
        player.set_meta("combat_attack_recovery_until_ms", recovery_until_ms)
        player.set_meta("combat_move_recovery_ms", recovery_until_ms - started_ms)
        player.set_meta("combat_move_recovery_landed", landed)
        player.set_meta("combat_last_melee_result", result.duplicate(true))
        player.set_meta("combat_last_melee_impact_ms", now)
        player.set_meta("combat_last_melee_hit", landed)
        if landed:
            var reaction := String(result.get("reaction", "hit")).to_upper()
            _show_feedback("TOUCHÉ  -%d\n%s" % [int(round(ATTACK_DAMAGE)), reaction], 420)
        else:
            _show_feedback("COUP", 220)
        resolved = true

    if not resolved:
        player.set_meta("combat_attack_phase", "windup")
        return
    if now < active_until_ms:
        player.set_meta("combat_attack_phase", "active")
        return
    if now < recovery_until_ms:
        player.set_meta("combat_attack_phase", "recovery")
        return

    player.set_meta("combat_attack_phase", "ready")
    player.set_meta("combat_attack_pending", false)
    _pending_player_attack.clear()

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
                var style := StringName(state.get("counter_strike_style", &"cross"))
                var impact_ms := now + COUNTER_STRIKE_IMPACT_MS
                state["counter_windup_until_ms"] = 0
                state["counter_strike_impact_ms"] = impact_ms
                _reaction_states[instance_id] = state
                npc.set_meta("combat_counter_telegraph_until_ms", 0)
                npc.set_meta("combat_counter_strike_impact_ms", impact_ms)
                npc.set_meta("combat_counter_strike_side", side)
                npc.set_meta("combat_counter_strike_style", style)
                _animate_counter_strike(npc, side, style)
            continue

        if now >= int(state.get("next_counter_ms", 0)):
            var telegraph_until := now + COUNTER_TELEGRAPH_MS
            var telegraph_count := int(npc.get_meta("combat_counter_telegraph_count", 0)) + 1
            var side := counter_strike_side(npc.variation_seed, telegraph_count)
            var style := counter_strike_style(npc.variation_seed, telegraph_count)
            state["counter_windup_until_ms"] = telegraph_until
            state["counter_strike_side"] = side
            state["counter_strike_style"] = style
            _reaction_states[instance_id] = state
            npc.set_meta("combat_counter_telegraph_until_ms", telegraph_until)
            npc.set_meta("combat_counter_telegraph_count", telegraph_count)
            npc.set_meta("combat_counter_strike_side", side)
            npc.set_meta("combat_counter_strike_style", style)
            _animate_counter_telegraph(npc, side, style)

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

func _animate_counter_telegraph(npc: NpcAgent, side: StringName, style: StringName) -> void:
    var profile := counter_strike_profile(style)
    var side_sign := -1.0 if side == &"left" else 1.0
    var visual := _npc_visual(npc)
    if visual != null:
        var base_x := visual.rotation.x
        var base_y := visual.rotation.y
        var tween := create_tween()
        tween.tween_property(visual, "rotation:x", base_x + float(profile.get("windup_pitch", -0.14)), 0.10)
        tween.parallel().tween_property(visual, "rotation:y", base_y - float(profile.get("windup_yaw", 0.10)) * side_sign, 0.10)
        tween.tween_interval(maxf(float(COUNTER_TELEGRAPH_MS) / 1000.0 - 0.15, 0.01))
        tween.tween_property(visual, "rotation:x", base_x, 0.05)
        tween.parallel().tween_property(visual, "rotation:y", base_y, 0.05)

    var limb := _npc_limb(npc, "LeftArm" if side == &"left" else "RightArm")
    if limb != null:
        if not limb.has_meta("combat_counter_base_rotation"):
            limb.set_meta("combat_counter_base_rotation", limb.rotation)
        var limb_base: Vector3 = limb.get_meta("combat_counter_base_rotation", limb.rotation)
        var windup_target := limb_base
        windup_target.x += float(profile.get("windup_arm_x", 0.34))
        windup_target.z += float(profile.get("windup_arm_z", 0.16)) * side_sign
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

func _animate_counter_strike(npc: NpcAgent, side: StringName, style: StringName) -> void:
    var profile := counter_strike_profile(style)
    var side_sign := -1.0 if side == &"left" else 1.0
    var limb := _npc_limb(npc, "LeftArm" if side == &"left" else "RightArm")
    if limb != null:
        var base_rotation: Vector3 = limb.get_meta("combat_counter_base_rotation", limb.rotation)
        var strike_target := base_rotation
        strike_target.x += float(profile.get("arm_x", -1.08))
        strike_target.z += float(profile.get("arm_z", 0.22)) * side_sign
        var limb_tween := create_tween()
        limb_tween.tween_property(limb, "rotation", strike_target, float(COUNTER_STRIKE_IMPACT_MS) / 1000.0)
        limb_tween.tween_property(limb, "rotation", base_rotation, float(COUNTER_STRIKE_RECOVER_MS) / 1000.0)

    var visual := _npc_visual(npc)
    if visual != null:
        var base_y := visual.rotation.y
        var base_z := visual.rotation.z
        var body_tween := create_tween()
        body_tween.tween_property(visual, "rotation:y", base_y + float(profile.get("body_yaw", 0.18)) * side_sign, float(COUNTER_STRIKE_IMPACT_MS) / 1000.0)
        body_tween.parallel().tween_property(visual, "rotation:z", base_z + float(profile.get("body_roll", -0.055)) * side_sign, float(COUNTER_STRIKE_IMPACT_MS) / 1000.0)
        body_tween.tween_property(visual, "rotation:y", base_y, float(COUNTER_STRIKE_RECOVER_MS) / 1000.0)
        body_tween.parallel().tween_property(visual, "rotation:z", base_z, float(COUNTER_STRIKE_RECOVER_MS) / 1000.0)
    npc.set_meta("combat_counter_strike_count", int(npc.get_meta("combat_counter_strike_count", 0)) + 1)
    npc.set_meta("combat_last_counter_strike_style", style)

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

static func counter_strike_style(seed: int, counter_index: int) -> StringName:
    match posmod(seed * 13 + counter_index * 7, 3):
        0:
            return &"jab"
        1:
            return &"cross"
        _:
            return &"hook"

static func counter_strike_profile(style: StringName) -> Dictionary:
    match style:
        &"jab":
            return {
                "windup_pitch": -0.08,
                "windup_yaw": 0.05,
                "windup_arm_x": 0.18,
                "windup_arm_z": 0.07,
                "arm_x": -0.88,
                "arm_z": 0.08,
                "body_yaw": 0.10,
                "body_roll": -0.025,
            }
        &"hook":
            return {
                "windup_pitch": -0.18,
                "windup_yaw": 0.16,
                "windup_arm_x": 0.28,
                "windup_arm_z": 0.28,
                "arm_x": -0.72,
                "arm_z": 0.55,
                "body_yaw": 0.30,
                "body_roll": -0.09,
            }
        _:
            return {
                "windup_pitch": -0.14,
                "windup_yaw": 0.10,
                "windup_arm_x": 0.34,
                "windup_arm_z": 0.16,
                "arm_x": -1.18,
                "arm_z": 0.18,
                "body_yaw": 0.22,
                "body_roll": -0.055,
            }

static func melee_recovery_ms(move_id: StringName, landed: bool) -> int:
    match move_id:
        &"jab_left":
            return 340 if landed else 385
        &"cross_right":
            return 370 if landed else 415
        &"hook_left":
            return 435 if landed else 485
        &"hook_right":
            return 440 if landed else 495
        &"uppercut_right":
            return 455 if landed else 515
        &"body_hook_left":
            return 420 if landed else 475
        &"front_kick_right":
            return 485 if landed else 545
        &"low_kick_left":
            return 450 if landed else 515
        &"push_kick_right":
            return 480 if landed else 550
        &"elbow_right":
            return 400 if landed else 455
        _:
            return ATTACK_COOLDOWN_MS

static func melee_reaction_profile(move_id: StringName) -> Dictionary:
    match move_id:
        &"jab_left":
            return {"side": "right", "roll_deg": 5.0, "yaw_deg": -3.0, "stagger_ms": 360}
        &"cross_right":
            return {"side": "left", "roll_deg": -7.0, "yaw_deg": 4.0, "stagger_ms": 420}
        &"hook_left":
            return {"side": "right", "roll_deg": 11.0, "yaw_deg": -8.0, "stagger_ms": 500}
        &"hook_right":
            return {"side": "left", "roll_deg": -11.0, "yaw_deg": 8.0, "stagger_ms": 500}
        &"uppercut_right":
            return {"side": "center", "roll_deg": -6.0, "yaw_deg": 4.0, "stagger_ms": 560}
        &"body_hook_left":
            return {"side": "right", "roll_deg": 8.0, "yaw_deg": -6.0, "stagger_ms": 470}
        &"front_kick_right":
            return {"side": "center", "roll_deg": -4.0, "yaw_deg": 3.0, "stagger_ms": 620}
        &"low_kick_left":
            return {"side": "left", "roll_deg": 6.0, "yaw_deg": -5.0, "stagger_ms": 520}
        &"push_kick_right":
            return {"side": "center", "roll_deg": -8.0, "yaw_deg": 2.0, "stagger_ms": 650}
        &"elbow_right":
            return {"side": "left", "roll_deg": -9.0, "yaw_deg": 7.0, "stagger_ms": 480}
        _:
            return {"side": "center", "roll_deg": 4.0, "yaw_deg": 0.0, "stagger_ms": 360}