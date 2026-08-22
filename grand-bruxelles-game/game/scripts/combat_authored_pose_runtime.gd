extends Node

# Rig-safe combat animation layer for the authored player.
# It only plays imported AnimationPlayer clips and never writes Skeleton3D bone overrides.

const SIGNATURE := "combat_authored_animation_v3_safe"
const ACTION_META := "combat_action_lock_until_ms"
const TRANSIENT_BLEND_S := 0.055
const SHOT_LOCK_MS := 180
const SHOT_RESTART_GUARD_MS := 95
const HITSTOP_MIN_MS := 24
const HITSTOP_MAX_MS := 72

var _bound_player_id := 0
var _animation_player: AnimationPlayer = null
var _animation_names: PackedStringArray = PackedStringArray()
var _last_shot_animation_ms := -100000
var _hitstop_active := false
var _hitstop_token := 0
var _hitstop_restore_speed := 1.0

func _ready() -> void:
    process_priority = 50
    set_process(true)

func _process(_delta: float) -> void:
    var player := _current_player()
    if player == null:
        _clear_binding()
        return
    _ensure_bound(player)

func request_melee_pose(player: CharacterBody3D, move: Dictionary) -> void:
    if player == null or not is_instance_valid(player) or not _ensure_bound(player):
        return
    var move_id := StringName(move.get("id", &""))
    var animation := resolve_melee_animation(_animation_names, move_id)
    player.set_meta("combat_pose_signature", SIGNATURE)
    player.set_meta("combat_pose_move_id", move_id)
    player.set_meta("combat_pose_mode", "authored_animation")
    player.set_meta("combat_pose_selected_animation", animation)
    player.set_meta("combat_pose_variant_hint", melee_variant_hint(move_id))
    if animation == &"":
        player.set_meta("combat_pose_safe_fallback", true)
        return

    var total_ms := int(round((
        float(move.get("windup_s", 0.07))
        + float(move.get("active_s", 0.09))
        + float(move.get("recover_s", 0.20))
    ) * 1000.0))
    _extend_action_lock(player, maxi(total_ms + 60, 220))
    _play_transient(animation, melee_playback_speed(move_id))
    player.set_meta("combat_pose_safe_fallback", false)

func request_shot_pose(player: CharacterBody3D, weapon_id: StringName) -> void:
    if player == null or not is_instance_valid(player) or not _ensure_bound(player):
        return
    var animation := resolve_weapon_shot_animation(_animation_names, weapon_id)
    player.set_meta("combat_pose_signature", SIGNATURE)
    player.set_meta("combat_pose_last_shot_weapon", weapon_id)
    player.set_meta("combat_pose_shot_animation", animation)
    player.set_meta("combat_pose_mode", "authored_animation")
    if animation == &"":
        player.set_meta("combat_pose_shot_safe_fallback", true)
        return

    var now := Time.get_ticks_msec()
    if now - _last_shot_animation_ms < SHOT_RESTART_GUARD_MS:
        return
    _last_shot_animation_ms = now
    _extend_action_lock(player, SHOT_LOCK_MS)
    _play_transient(animation, 1.22 if weapon_id == &"sct8" else 1.34)
    player.set_meta("combat_pose_shot_safe_fallback", false)

func request_hitstop(player: CharacterBody3D, duration_ms: int) -> void:
    if player == null or not is_instance_valid(player) or not _ensure_bound(player):
        return
    var clamped_ms := clampi(duration_ms, HITSTOP_MIN_MS, HITSTOP_MAX_MS)
    _hitstop_token += 1
    var token := _hitstop_token
    if not _hitstop_active:
        _hitstop_restore_speed = maxf(_animation_player.speed_scale, 0.01)
    _hitstop_active = true
    _animation_player.speed_scale = 0.0
    var now := Time.get_ticks_msec()
    player.set_meta("combat_hitstop_active", true)
    player.set_meta("combat_hitstop_until_ms", now + clamped_ms)
    player.set_meta("combat_hitstop_animation_speed_before", _hitstop_restore_speed)
    var timer := get_tree().create_timer(float(clamped_ms) / 1000.0, true, false, true)
    await timer.timeout
    if token != _hitstop_token:
        return
    if is_instance_valid(_animation_player):
        _animation_player.speed_scale = maxf(_hitstop_restore_speed, 0.01)
    _hitstop_active = false
    if player != null and is_instance_valid(player):
        player.set_meta("combat_hitstop_active", false)
        player.set_meta("combat_hitstop_released_ms", Time.get_ticks_msec())

func _ensure_bound(player: CharacterBody3D) -> bool:
    if _bound_player_id == player.get_instance_id() and is_instance_valid(_animation_player):
        return true
    _clear_binding()
    var visual := player.get_node_or_null("VisualUpgrade")
    if visual == null:
        return false
    var authored := visual.get_node_or_null("AuthoredCharacter")
    if authored == null:
        return false
    _animation_player = _find_animation_player(authored)
    if _animation_player == null:
        return false
    _bound_player_id = player.get_instance_id()
    _animation_names = _animation_player.get_animation_list()
    player.set_meta("combat_pose_signature", SIGNATURE)
    player.set_meta("combat_pose_animation_count", _animation_names.size())
    return true

func _find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer
    for child: Node in node.get_children():
        var found := _find_animation_player(child)
        if found != null:
            return found
    return null

func _play_transient(animation_name: StringName, speed: float) -> void:
    if _animation_player == null or animation_name == &"" or not _animation_player.has_animation(animation_name):
        return
    var animation := _animation_player.get_animation(animation_name)
    if animation != null:
        animation.loop_mode = Animation.LOOP_NONE
    _animation_player.play(animation_name, TRANSIENT_BLEND_S, speed)

func _extend_action_lock(player: CharacterBody3D, duration_ms: int) -> void:
    var now := Time.get_ticks_msec()
    var current_until := int(player.get_meta(ACTION_META, 0))
    player.set_meta(ACTION_META, maxi(current_until, now + maxi(duration_ms, 1)))

func _current_player() -> CharacterBody3D:
    var scene := get_tree().current_scene
    if scene == null:
        return null
    return scene.get_node_or_null("Player") as CharacterBody3D

func _clear_binding() -> void:
    if _hitstop_active and is_instance_valid(_animation_player):
        _animation_player.speed_scale = maxf(_hitstop_restore_speed, 0.01)
    _bound_player_id = 0
    _animation_player = null
    _animation_names = PackedStringArray()
    _last_shot_animation_ms = -100000
    _hitstop_active = false
    _hitstop_token += 1
    _hitstop_restore_speed = 1.0

static func melee_variant_hint(move_id: StringName) -> String:
    match move_id:
        &"jab_left", &"hook_left", &"body_hook_left":
            return "punch_a"
        &"front_kick_right", &"low_kick_left", &"push_kick_right":
            return "kick"
        _:
            return "punch_b"

static func melee_playback_speed(move_id: StringName) -> float:
    match move_id:
        &"jab_left":
            return 1.28
        &"cross_right":
            return 1.18
        &"hook_left", &"hook_right", &"body_hook_left":
            return 1.06
        &"uppercut_right":
            return 0.98
        &"front_kick_right", &"push_kick_right":
            return 0.96
        &"low_kick_left":
            return 1.02
        &"elbow_right":
            return 1.22
        _:
            return 1.10

static func resolve_melee_animation(names: PackedStringArray, move_id: StringName) -> StringName:
    var hint := melee_variant_hint(move_id)
    if hint == "kick":
        var kick := _best_animation(names, ["kick"], ["unarmed", "melee", "attack"], _combat_reject_tokens())
        if kick != &"":
            return kick
    else:
        var preferred_variant: Array[String] = [hint, "unarmed", "melee", "attack"]
        var punch := _best_animation(names, ["punch", "unarmed"], preferred_variant, _combat_reject_tokens())
        if punch != &"":
            return punch
    return _best_animation(names, ["melee", "attack"], ["1h", "attack"], _combat_reject_tokens())

static func resolve_weapon_shot_animation(names: PackedStringArray, weapon_id: StringName) -> StringName:
    var preferred: Array[String] = []
    preferred.append("1h" if weapon_id == &"bx9" else "2h")
    preferred.append("ranged")
    var resolved := _best_animation(names, ["shoot", "fire"], preferred, _weapon_reject_tokens())
    if resolved != &"":
        return resolved
    return _best_animation(names, ["ranged"], preferred, _weapon_reject_tokens())

static func _best_animation(names: PackedStringArray, required_any: Array[String], preferred: Array[String], rejected: Array[String]) -> StringName:
    var best: StringName = &""
    var best_score := -100000
    for raw_name: String in names:
        if raw_name == "RESET":
            continue
        var lowered := raw_name.to_lower()
        var blocked := false
        for token: String in rejected:
            if lowered.contains(token):
                blocked = true
                break
        if blocked:
            continue
        var required_hits := 0
        for token: String in required_any:
            if lowered.contains(token):
                required_hits += 1
        if required_hits == 0:
            continue
        var score := required_hits * 20
        for token: String in preferred:
            if lowered.contains(token):
                score += 8
        if lowered.contains("attack"):
            score += 3
        if score > best_score:
            best_score = score
            best = StringName(raw_name)
    return best

static func _combat_reject_tokens() -> Array[String]:
    return ["idle", "walk", "run", "death", "die", "hurt", "hit", "block", "defend", "ranged", "shoot", "bow", "crossbow", "staff", "spell"]

static func _weapon_reject_tokens() -> Array[String]:
    return ["idle", "walk", "run", "death", "die", "hurt", "hit", "melee", "kick", "punch", "sword", "staff", "spell"]