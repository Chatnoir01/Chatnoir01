extends Node

# Safe authored combat animation layer for the real fallback player.
# Important: this runtime deliberately does NOT write Skeleton3D bone overrides.
# The KayKit Rogue already ships with a full authored animation library; using
# those clips preserves the rig hierarchy and avoids parent/child pose tearing.

const SIGNATURE := "combat_authored_animation_v2_safe"
const ACTION_META := "combat_action_lock_until_ms"
const WEAPON_META := "combat_weapon_id"
const TRANSIENT_BLEND_S := 0.07
const SHOT_LOCK_MS := 180
const SHOT_RESTART_GUARD_MS := 95

var _bound_player_id := 0
var _animation_player: AnimationPlayer = null
var _animation_names: PackedStringArray = PackedStringArray()
var _last_shot_animation_ms := -100000

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
    if animation == &"":
        player.set_meta("combat_pose_safe_fallback", true)
        return

    var total_ms := int(round((
        float(move.get("windup_s", 0.07))
        + float(move.get("active_s", 0.09))
        + float(move.get("recover_s", 0.20))
    ) * 1000.0))
    _extend_action_lock(player, maxi(total_ms + 60, 220))
    _play_transient(animation, 1.10)
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
        # Safe fallback: keep the imported locomotion pose. Grip + muzzle/tracer
        # FX still work, but we never deform the rig to fake a missing gun clip.
        player.set_meta("combat_pose_shot_safe_fallback", true)
        return

    var now := Time.get_ticks_msec()
    if now - _last_shot_animation_ms < SHOT_RESTART_GUARD_MS:
        return
    _last_shot_animation_ms = now
    _extend_action_lock(player, SHOT_LOCK_MS)
    _play_transient(animation, 1.22 if weapon_id == &"sct8" else 1.34)
    player.set_meta("combat_pose_shot_safe_fallback", false)

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
    _bound_player_id = 0
    _animation_player = null
    _animation_names = PackedStringArray()
    _last_shot_animation_ms = -100000

static func resolve_melee_animation(names: PackedStringArray, move_id: StringName) -> StringName:
    var lowered_id := String(move_id).to_lower()
    if lowered_id.contains("kick"):
        var kick := _best_animation(names, ["kick"], ["unarmed", "melee"], _combat_reject_tokens())
        if kick != &"":
            return kick
    if lowered_id.contains("elbow"):
        var elbow := _best_animation(names, ["elbow", "punch"], ["unarmed", "melee", "attack"], _combat_reject_tokens())
        if elbow != &"":
            return elbow
    var punch := _best_animation(names, ["punch", "unarmed"], ["melee", "attack"], _combat_reject_tokens())
    if punch != &"":
        return punch
    # KayKit Rogue is known to expose 1H_Melee_Attack_* clips. They are a safe
    # authored last resort: preferable to corrupting the skeleton hierarchy.
    return _best_animation(names, ["melee", "attack"], ["1h", "attack"], _combat_reject_tokens())

static func resolve_weapon_shot_animation(names: PackedStringArray, weapon_id: StringName) -> StringName:
    var preferred := ["1h", "ranged"] if weapon_id == &"bx9" else ["2h", "ranged"]
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
