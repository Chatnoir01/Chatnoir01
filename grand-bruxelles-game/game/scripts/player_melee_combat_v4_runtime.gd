extends "res://game/scripts/player_melee_combat_hardened_runtime.gd"

# V4 adds collision-aware body footwork, late defensive cancels and local
# authored-animation hit-stop while preserving the V3 contact-timed resolver.
const ATTACK_LUNGE_MAX_M := 0.24
const ATTACK_MOTION_PRE_IMPACT_MS := 42
const ATTACK_MOTION_POST_IMPACT_MS := 54
const ATTACK_CANCEL_POST_IMPACT_MS := 28
const ATTACK_CANCEL_RECOVERY_MS := 90
const HITSTOP_LIGHT_MS := 42
const HITSTOP_MEDIUM_MS := 54
const HITSTOP_HEAVY_MS := 66

var _lunge_player: WeakRef = null
var _lunge_direction := Vector3.ZERO
var _lunge_remaining_m := 0.0
var _lunge_start_ms := 0
var _lunge_until_ms := 0

func request_attack_with_move(player: CharacterBody3D, move: Dictionary) -> Dictionary:
    var result := super.request_attack_with_move(player, move)
    if player == null or not is_instance_valid(player) or not bool(result.get("pending", false)):
        return result

    var started_ms := int(player.get_meta("combat_attack_started_ms", Time.get_ticks_msec()))
    var impact_ms := int(player.get_meta("combat_attack_impact_at_ms", started_ms + 1))
    var active_until_ms := int(player.get_meta("combat_attack_active_until_ms", impact_ms + 1))
    var raw_lunge := maxf(0.0, float(move.get("lunge_m", 0.0)))
    var lunge_m := minf(raw_lunge, ATTACK_LUNGE_MAX_M)
    var direction := -player.global_transform.basis.z
    direction.y = 0.0
    if direction.length_squared() > 0.0001:
        direction = direction.normalized()
    else:
        direction = Vector3.ZERO

    _lunge_player = weakref(player)
    _lunge_direction = direction
    _lunge_remaining_m = lunge_m
    _lunge_start_ms = maxi(started_ms, impact_ms - ATTACK_MOTION_PRE_IMPACT_MS)
    _lunge_until_ms = mini(active_until_ms, impact_ms + ATTACK_MOTION_POST_IMPACT_MS)
    if _lunge_until_ms <= _lunge_start_ms:
        _lunge_until_ms = _lunge_start_ms + 1

    var cancel_ready_ms := mini(
        int(player.get_meta("combat_attack_recovery_until_ms", active_until_ms + 1)) - 1,
        impact_ms + ATTACK_CANCEL_POST_IMPACT_MS
    )
    player.set_meta("combat_attack_lunge_m", lunge_m)
    player.set_meta("combat_attack_lunge_remaining_m", lunge_m)
    player.set_meta("combat_attack_lunge_direction", direction)
    player.set_meta("combat_attack_motion_start_ms", _lunge_start_ms)
    player.set_meta("combat_attack_motion_until_ms", _lunge_until_ms)
    player.set_meta("combat_attack_cancel_ready_ms", cancel_ready_ms)
    player.set_meta("combat_attack_input_scale", 0.34)
    player.set_meta("combat_attack_cancel_actions", PackedStringArray(["dodge", "guard"]))
    result["cancel_ready_ms"] = cancel_ready_ms
    result["physical_lunge_m"] = lunge_m
    return result

func _physics_process(delta: float) -> void:
    if _lunge_player == null or _lunge_remaining_m <= 0.0:
        return
    var player := _lunge_player.get_ref() as CharacterBody3D
    if player == null or not is_instance_valid(player) or not player.is_inside_tree():
        _clear_lunge()
        return
    var now := Time.get_ticks_msec()
    if now < _lunge_start_ms:
        return
    if now >= _lunge_until_ms:
        player.set_meta("combat_attack_lunge_remaining_m", 0.0)
        _clear_lunge()
        return
    if _lunge_direction.length_squared() <= 0.0001:
        _clear_lunge()
        return

    var duration_s := maxf(float(_lunge_until_ms - _lunge_start_ms) / 1000.0, 0.001)
    var speed_mps := maxf(float(player.get_meta("combat_attack_lunge_m", 0.0)) / duration_s, 0.0)
    var step_distance := minf(_lunge_remaining_m, speed_mps * maxf(delta, 0.0))
    if step_distance <= 0.0:
        return
    var before := player.global_position
    var collision := player.move_and_collide(_lunge_direction * step_distance)
    var travelled := player.global_position.distance_to(before)
    _lunge_remaining_m = maxf(0.0, _lunge_remaining_m - travelled)
    player.set_meta("combat_attack_lunge_remaining_m", _lunge_remaining_m)
    player.set_meta("combat_attack_lunge_travelled_m", float(player.get_meta("combat_attack_lunge_m", 0.0)) - _lunge_remaining_m)
    if collision != null or travelled < step_distance * 0.2:
        player.set_meta("combat_attack_lunge_blocked", true)
        _clear_lunge()

func set_guarding(player: CharacterBody3D, enabled: bool) -> void:
    if enabled and player != null and is_instance_valid(player):
        var phase := String(player.get_meta("combat_attack_phase", "ready"))
        if phase != "ready" and phase != "cancelled":
            if not request_action_cancel(player, &"guard"):
                return
    super.set_guarding(player, enabled)

func request_action_cancel(player: CharacterBody3D, action: StringName) -> bool:
    if player == null or not is_instance_valid(player):
        return false
    if action != &"dodge" and action != &"guard":
        return false
    var now := Time.get_ticks_msec()
    var cancel_ready_ms := int(player.get_meta("combat_attack_cancel_ready_ms", 2147483647))
    var recovery_until_ms := int(player.get_meta("combat_attack_recovery_until_ms", 0))
    if not can_cancel_attack(now, cancel_ready_ms, recovery_until_ms):
        return false

    if not _pending_player_attack.is_empty():
        var active_ref: WeakRef = _pending_player_attack.get("player")
        var active_player := active_ref.get_ref() as CharacterBody3D if active_ref != null else null
        if active_player == player:
            _pending_player_attack.clear()

    var short_recovery_until := now + ATTACK_CANCEL_RECOVERY_MS
    _next_attack_allowed_ms = short_recovery_until
    player.set_meta("combat_attack_pending", false)
    player.set_meta("combat_attack_phase", "cancelled")
    player.set_meta("combat_attack_recovery_until_ms", short_recovery_until)
    player.set_meta("combat_attack_lunge_remaining_m", 0.0)
    player.set_meta("combat_attack_input_scale", 1.0)
    player.set_meta("combat_last_cancel_action", action)
    player.set_meta("combat_last_cancel_ms", now)
    _clear_lunge()
    return true

func _apply_hit(npc: NpcAgent, player: CharacterBody3D, damage: float) -> StringName:
    var weapon_inflight := player != null and bool(player.get_meta("combat_weapon_hit_inflight", false))
    var reaction := super._apply_hit(npc, player, damage)
    if player == null or not is_instance_valid(player) or weapon_inflight:
        return reaction
    var move_id := StringName(player.get_meta("combat_move_id", &""))
    var duration_ms := melee_hitstop_ms(move_id, reaction != &"miss")
    if duration_ms <= 0:
        return reaction
    var now := Time.get_ticks_msec()
    player.set_meta("combat_hitstop_until_ms", now + duration_ms)
    player.set_meta("combat_last_hitstop_ms", duration_ms)
    var pose_runtime := get_node_or_null("/root/CombatAuthoredPoseRuntime")
    if pose_runtime != null and pose_runtime.has_method("request_hitstop"):
        pose_runtime.call("request_hitstop", player, duration_ms)
    return reaction

func _clear_lunge() -> void:
    _lunge_player = null
    _lunge_direction = Vector3.ZERO
    _lunge_remaining_m = 0.0
    _lunge_start_ms = 0
    _lunge_until_ms = 0

static func can_cancel_attack(now_ms: int, cancel_ready_ms: int, recovery_until_ms: int) -> bool:
    return now_ms >= cancel_ready_ms and now_ms < recovery_until_ms

static func melee_hitstop_ms(move_id: StringName, landed: bool) -> int:
    if not landed:
        return 0
    match move_id:
        &"front_kick_right", &"push_kick_right", &"uppercut_right":
            return HITSTOP_HEAVY_MS
        &"hook_left", &"hook_right", &"body_hook_left", &"elbow_right":
            return HITSTOP_MEDIUM_MS
        _:
            return HITSTOP_LIGHT_MS
