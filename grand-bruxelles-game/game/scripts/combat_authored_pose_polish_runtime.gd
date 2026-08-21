extends "res://game/scripts/combat_authored_pose_runtime.gd"

# Extends the safe imported-animation layer for the native knife without any
# direct bone overrides. All existing gun/unarmed animation resolution remains
# unchanged.

func request_melee_pose(player: CharacterBody3D, move: Dictionary) -> void:
    var move_id := StringName(move.get("id", &""))
    if not String(move_id).begins_with("knife_"):
        super.request_melee_pose(player, move)
        return
    if player == null or not is_instance_valid(player) or not _ensure_bound(player):
        return

    var animation := resolve_knife_animation(_animation_names)
    if animation == &"":
        super.request_melee_pose(player, move)
        return

    player.set_meta("combat_pose_signature", SIGNATURE)
    player.set_meta("combat_pose_move_id", move_id)
    player.set_meta("combat_pose_mode", "authored_animation")
    player.set_meta("combat_pose_selected_animation", animation)
    player.set_meta("combat_pose_variant_hint", "knife_1h")
    player.set_meta("combat_pose_safe_fallback", false)
    var total_ms := int(round((
        float(move.get("windup_s", 0.085))
        + float(move.get("active_s", 0.105))
        + float(move.get("recover_s", 0.235))
    ) * 1000.0))
    _extend_action_lock(player, maxi(total_ms + 60, 240))
    _play_transient(animation, 1.08)

static func resolve_knife_animation(names: PackedStringArray) -> StringName:
    var best: StringName = &""
    var best_score := -100000
    for raw_name: String in names:
        if raw_name == "RESET":
            continue
        var lowered := raw_name.to_lower()
        if _contains_any(lowered, ["idle", "walk", "run", "death", "die", "hurt", "hit", "block", "defend", "ranged", "shoot", "bow", "crossbow", "spell"]):
            continue
        var score := 0
        if lowered.contains("knife"):
            score += 70
        if lowered.contains("1h"):
            score += 28
        if lowered.contains("melee"):
            score += 32
        if lowered.contains("slash") or lowered.contains("slice"):
            score += 26
        if lowered.contains("attack"):
            score += 18
        if lowered.contains("sword"):
            score += 8
        if score >= 50 and score > best_score:
            best_score = score
            best = StringName(raw_name)
    return best

static func _contains_any(value: String, tokens: Array[String]) -> bool:
    for token: String in tokens:
        if value.contains(token):
            return true
    return false
