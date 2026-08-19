extends "res://game/scripts/player_dodge_runtime.gd"

# V4 keeps dodge collision-aware and time-based. Belgian AZERTY Q remains
# movement-left in player_controller.gd; X is the dedicated keyboard dodge key.
const DODGE_KEY := KEY_X
const DODGE_MOTION_MS := 220
const DODGE_BLOCKED_STEP_EPSILON_M := 0.004

var _motion_player: WeakRef = null
var _motion_direction := Vector3.ZERO
var _motion_remaining_m := 0.0
var _motion_until_ms := 0

func _input(event: InputEvent) -> void:
    if not event is InputEventKey:
        return
    var key_event := event as InputEventKey
    if key_event.keycode != DODGE_KEY or not key_event.pressed or key_event.echo:
        return
    var player := _current_player()
    if player == null:
        return
    request_dodge(player, _input_dodge_direction(player))
    get_viewport().set_input_as_handled()

func request_dodge(player: CharacterBody3D, requested_direction: Vector3 = Vector3.ZERO) -> Dictionary:
    if player == null or not is_instance_valid(player) or not player.is_inside_tree():
        return {"dodged": false, "reason": "player_unavailable"}
    if not player.visible:
        return {"dodged": false, "reason": "player_hidden"}
    if bool(player.get_meta("combat_guarding", false)):
        return {"dodged": false, "reason": "guarding"}

    var now := Time.get_ticks_msec()
    var next_allowed := int(player.get_meta("combat_next_dodge_ms", 0))
    if now < next_allowed:
        return {"dodged": false, "reason": "cooldown", "remaining_ms": next_allowed - now}

    var phase := String(player.get_meta("combat_attack_phase", "ready"))
    if phase != "ready" and phase != "cancelled":
        var melee_runtime := get_node_or_null("/root/PlayerMeleeCombatRuntime")
        if melee_runtime == null or not melee_runtime.has_method("request_action_cancel"):
            return {"dodged": false, "reason": "attack_locked"}
        var cancel_variant: Variant = melee_runtime.call("request_action_cancel", player, &"dodge")
        if not bool(cancel_variant):
            return {"dodged": false, "reason": "attack_locked"}

    var direction := requested_direction
    direction.y = 0.0
    if direction.length_squared() <= 0.0001:
        direction = player.global_transform.basis.z
        direction.y = 0.0
    if direction.length_squared() <= 0.0001:
        return {"dodged": false, "reason": "no_direction"}
    direction = direction.normalized()

    _motion_player = weakref(player)
    _motion_direction = direction
    _motion_remaining_m = DODGE_DISTANCE_M
    _motion_until_ms = now + DODGE_MOTION_MS

    player.set_meta("combat_next_dodge_ms", now + DODGE_COOLDOWN_MS)
    player.set_meta("combat_dodge_until_ms", now + DODGE_EVADE_WINDOW_MS)
    player.set_meta("combat_dodge_motion_started_ms", now)
    player.set_meta("combat_dodge_motion_until_ms", _motion_until_ms)
    player.set_meta("combat_dodge_direction", direction)
    player.set_meta("combat_dodge_motion_remaining_m", DODGE_DISTANCE_M)
    player.set_meta("combat_dodge_count", int(player.get_meta("combat_dodge_count", 0)) + 1)
    player.set_meta("combat_last_dodge_direction", direction)
    player.set_meta("combat_last_dodge_distance_m", 0.0)
    player.set_meta("combat_dodge_collided", false)
    _animate_dodge(player, direction)
    _show_feedback("ESQUIVE", 200)
    return {
        "dodged": true,
        "direction": direction,
        "distance_m": 0.0,
        "scheduled_distance_m": DODGE_DISTANCE_M,
        "motion_ms": DODGE_MOTION_MS,
        "evade_window_ms": DODGE_EVADE_WINDOW_MS,
        "collided": false,
    }

func _physics_process(delta: float) -> void:
    if _motion_player == null or _motion_remaining_m <= 0.0:
        return
    var player := _motion_player.get_ref() as CharacterBody3D
    if player == null or not is_instance_valid(player) or not player.is_inside_tree():
        _clear_motion()
        return

    var now := Time.get_ticks_msec()
    if now >= _motion_until_ms:
        _finish_motion(player, false)
        return

    var speed_mps := DODGE_DISTANCE_M / (float(DODGE_MOTION_MS) / 1000.0)
    var step_distance := minf(_motion_remaining_m, speed_mps * maxf(delta, 0.0))
    if step_distance <= 0.0:
        return
    var before := player.global_position
    var collision := player.move_and_collide(_motion_direction * step_distance)
    var travelled := player.global_position.distance_to(before)
    _motion_remaining_m = maxf(0.0, _motion_remaining_m - travelled)
    var total_travelled := DODGE_DISTANCE_M - _motion_remaining_m
    player.set_meta("combat_dodge_motion_remaining_m", _motion_remaining_m)
    player.set_meta("combat_last_dodge_distance_m", total_travelled)

    if collision != null or travelled < minf(step_distance * 0.25, DODGE_BLOCKED_STEP_EPSILON_M):
        player.set_meta("combat_dodge_collided", collision != null)
        _finish_motion(player, true)
        return
    if _motion_remaining_m <= 0.001:
        _finish_motion(player, false)

func _finish_motion(player: CharacterBody3D, blocked: bool) -> void:
    if player != null and is_instance_valid(player):
        player.set_meta("combat_dodge_motion_until_ms", Time.get_ticks_msec())
        player.set_meta("combat_dodge_motion_remaining_m", 0.0)
        if blocked and float(player.get_meta("combat_last_dodge_distance_m", 0.0)) < DODGE_MIN_EFFECTIVE_M:
            _show_feedback("ESQUIVE BLOQUÉE", 180)
    _clear_motion()

func _clear_motion() -> void:
    _motion_player = null
    _motion_direction = Vector3.ZERO
    _motion_remaining_m = 0.0
    _motion_until_ms = 0
