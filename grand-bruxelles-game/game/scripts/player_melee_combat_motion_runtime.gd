extends "res://game/scripts/player_melee_combat_hardened_runtime.gd"

# Combat V4 feel layer.
# Keeps V3 contact resolution intact while adding physical footwork metadata,
# late recovery cancels and local authored-animation hit-stop.

const DODGE_CANCEL_LANDED_FRACTION := 0.35
const DODGE_CANCEL_WHIFF_FRACTION := 0.55
const GUARD_CANCEL_LANDED_FRACTION := 0.48
const GUARD_CANCEL_WHIFF_FRACTION := 0.68
const MIN_LUNGE_M := 0.04
const MAX_LUNGE_M := 0.22
const BASE_WALK_META := "combat_controller_base_walk_speed"
const BASE_SPRINT_META := "combat_controller_base_sprint_speed"

var _last_feel_impact_ms := -1

func _ready() -> void:
    super._ready()
    set_process(true)

func _process(delta: float) -> void:
    super._process(delta)
    var player := _current_player()
    if player == null or not is_instance_valid(player):
        return
    _update_attack_input_scale(player)
    _consume_new_melee_impact(player)

func request_attack_with_move(player: CharacterBody3D, move: Dictionary) -> Dictionary:
    var result := super.request_attack_with_move(player, move)
    if not bool(result.get("pending", false)) or player == null or not is_instance_valid(player):
        return result

    var started_ms := int(player.get_meta("combat_attack_started_ms", Time.get_ticks_msec()))
    var windup_ms := maxi(1, int(round(float(move.get("windup_s", 0.07)) * 1000.0)))
    var active_ms := maxi(1, int(round(float(move.get("active_s", 0.09)) * 1000.0)))
    var active_start_ms := started_ms + windup_ms
    var active_until_ms := active_start_ms + active_ms
    var forward := -player.global_transform.basis.z
    forward.y = 0.0
    if forward.length_squared() <= 0.0001:
        forward = Vector3.FORWARD
    forward = forward.normalized()
    var lunge_m := clampf(float(move.get("lunge_m", 0.08)), MIN_LUNGE_M, MAX_LUNGE_M)

    player.set_meta("combat_attack_active_start_ms", active_start_ms)
    player.set_meta("combat_attack_footwork_started_ms", active_start_ms)
    player.set_meta("combat_attack_footwork_until_ms", active_until_ms)
    player.set_meta("combat_attack_footwork_travelled_m", 0.0)
    player.set_meta("combat_attack_footwork_blocked", false)
    player.set_meta("combat_attack_lunge_m", lunge_m)
    player.set_meta("combat_attack_forward", forward)
    player.set_meta("combat_attack_input_scale", combat_attack_input_scale(&"windup"))
    player.set_meta("combat_attack_dodge_cancel_ready_ms", 0)
    player.set_meta("combat_attack_guard_cancel_ready_ms", 0)
    player.set_meta("combat_attack_cancel_ready_ms", 0)
    _apply_controller_speed_scale(player, combat_attack_input_scale(&"windup"))
    return result

func set_guarding(player: CharacterBody3D, enabled: bool) -> void:
    if enabled and player != null and is_instance_valid(player):
        var phase := StringName(player.get_meta("combat_attack_phase", &"ready"))
        if phase != &"ready":
            var cancel := request_action_cancel(player, &"guard")
            if not bool(cancel.get("allowed", false)):
                return
    super.set_guarding(player, enabled)

func request_action_cancel(player: CharacterBody3D, action: StringName) -> Dictionary:
    if player == null or not is_instance_valid(player):
        return {"allowed": false, "reason": "player_unavailable"}
    if action != &"dodge" and action != &"guard":
        return {"allowed": false, "reason": "unsupported_action"}
    var phase := StringName(player.get_meta("combat_attack_phase", &"ready"))
    if phase == &"ready":
        return {"allowed": true, "reason": "already_ready"}
    if bool(player.get_meta("combat_attack_pending", false)) or phase == &"windup" or phase == &"active":
        return {"allowed": false, "reason": "committed"}
    if phase != &"recovery":
        return {"allowed": false, "reason": "phase_locked"}

    var ready_meta := "combat_attack_guard_cancel_ready_ms" if action == &"guard" else "combat_attack_dodge_cancel_ready_ms"
    var ready_ms := int(player.get_meta(ready_meta, 0))
    var now := Time.get_ticks_msec()
    if ready_ms <= 0 or now < ready_ms:
        return {"allowed": false, "reason": "cancel_window", "remaining_ms": maxi(ready_ms - now, 0)}

    _next_attack_allowed_ms = now
    player.set_meta("combat_attack_recovery_until_ms", now)
    player.set_meta("combat_attack_phase", "ready")
    player.set_meta("combat_attack_pending", false)
    player.set_meta("combat_action_lock_until_ms", now)
    player.set_meta("combat_attack_input_scale", 1.0)
    player.set_meta("combat_last_cancel_action", action)
    player.set_meta("combat_last_cancel_ms", now)
    if not _pending_player_attack.is_empty() and bool(_pending_player_attack.get("resolved", false)):
        _pending_player_attack.clear()
    if not bool(player.get_meta("combat_dodge_motion_active", false)):
        _apply_controller_speed_scale(player, 1.0)
    return {"allowed": true, "reason": "late_recovery", "action": action}

func _update_attack_input_scale(player: CharacterBody3D) -> void:
    var phase := StringName(player.get_meta("combat_attack_phase", &"ready"))
    var scale := combat_attack_input_scale(phase)
    player.set_meta("combat_attack_input_scale", scale)
    if not bool(player.get_meta("combat_dodge_motion_active", false)):
        _apply_controller_speed_scale(player, scale)

func _apply_controller_speed_scale(player: CharacterBody3D, scale: float) -> void:
    if not _has_property(player, &"walk_speed") or not _has_property(player, &"sprint_speed"):
        return
    if not player.has_meta(BASE_WALK_META):
        player.set_meta(BASE_WALK_META, maxf(float(player.get("walk_speed")), 0.0))
    if not player.has_meta(BASE_SPRINT_META):
        player.set_meta(BASE_SPRINT_META, maxf(float(player.get("sprint_speed")), 0.0))
    var clamped_scale := clampf(scale, 0.0, 1.0)
    player.set("walk_speed", float(player.get_meta(BASE_WALK_META, 0.0)) * clamped_scale)
    player.set("sprint_speed", float(player.get_meta(BASE_SPRINT_META, 0.0)) * clamped_scale)
    player.set_meta("combat_controller_speed_scale", clamped_scale)

func _has_property(object: Object, property_name: StringName) -> bool:
    for property: Dictionary in object.get_property_list():
        if StringName(property.get("name", &"")) == property_name:
            return true
    return false

func _consume_new_melee_impact(player: CharacterBody3D) -> void:
    var impact_ms := int(player.get_meta("combat_last_melee_impact_ms", -1))
    if impact_ms <= 0 or impact_ms == _last_feel_impact_ms:
        return
    _last_feel_impact_ms = impact_ms

    var landed := bool(player.get_meta("combat_last_melee_hit", false))
    var move_id := StringName(player.get_meta("combat_move_id", &""))
    var active_until_ms := int(player.get_meta("combat_attack_active_until_ms", impact_ms))
    var recovery_until_ms := int(player.get_meta("combat_attack_recovery_until_ms", active_until_ms + 1))

    if landed:
        var hitstop_ms := melee_hitstop_ms(move_id)
        if hitstop_ms > 0:
            var now := Time.get_ticks_msec()
            player.set_meta("combat_hitstop_until_ms", now + hitstop_ms)
            player.set_meta("combat_last_hitstop_ms", hitstop_ms)
            recovery_until_ms += hitstop_ms
            player.set_meta("combat_attack_recovery_until_ms", recovery_until_ms)
            player.set_meta("combat_action_lock_until_ms", maxi(int(player.get_meta("combat_action_lock_until_ms", 0)), now + hitstop_ms))
            _next_attack_allowed_ms = maxi(_next_attack_allowed_ms, recovery_until_ms)
            if not _pending_player_attack.is_empty():
                _pending_player_attack["recovery_until_ms"] = recovery_until_ms
            var pose_runtime := get_node_or_null("/root/CombatAuthoredPoseRuntime")
            if pose_runtime != null and pose_runtime.has_method("request_hitstop"):
                pose_runtime.call("request_hitstop", player, hitstop_ms)

    var recovery_span := maxi(1, recovery_until_ms - active_until_ms)
    var dodge_ready := active_until_ms + int(round(float(recovery_span) * cancel_recovery_fraction(&"dodge", landed)))
    var guard_ready := active_until_ms + int(round(float(recovery_span) * cancel_recovery_fraction(&"guard", landed)))
    player.set_meta("combat_attack_dodge_cancel_ready_ms", dodge_ready)
    player.set_meta("combat_attack_guard_cancel_ready_ms", guard_ready)
    player.set_meta("combat_attack_cancel_ready_ms", mini(dodge_ready, guard_ready))

static func combat_attack_input_scale(phase: StringName) -> float:
    match phase:
        &"windup":
            return 0.40
        &"active":
            return 0.24
        &"recovery":
            return 0.62
        _:
            return 1.0

static func cancel_recovery_fraction(action: StringName, landed: bool) -> float:
    if action == &"guard":
        return GUARD_CANCEL_LANDED_FRACTION if landed else GUARD_CANCEL_WHIFF_FRACTION
    return DODGE_CANCEL_LANDED_FRACTION if landed else DODGE_CANCEL_WHIFF_FRACTION

static func melee_hitstop_ms(move_id: StringName) -> int:
    match move_id:
        &"jab_left":
            return 36
        &"cross_right":
            return 44
        &"hook_left", &"hook_right", &"body_hook_left":
            return 52
        &"uppercut_right", &"elbow_right":
            return 56
        &"front_kick_right", &"low_kick_left", &"push_kick_right":
            return 62
        _:
            return 42
