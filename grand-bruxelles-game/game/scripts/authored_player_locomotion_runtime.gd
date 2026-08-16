extends Node

const IDLE_MAX_SPEED_MPS := 0.20
const RUN_MIN_SPEED_MPS := 4.80
const BLEND_SECONDS := 0.16
const BAD_LOCOMOTION_TOKENS := [
    "attack", "block", "cast", "combat", "death", "die", "hit", "jump", "melee",
    "roll", "shoot", "sit", "spell", "strafe", "sword", "weapon", "1h", "2h",
]

var _clip_cache: Dictionary = {}

func _process(_delta: float) -> void:
    var actor := _production_player()
    if actor != null:
        drive_player(actor)

func _production_player() -> CharacterBody3D:
    var scene := get_tree().current_scene
    if scene != null:
        var direct := scene.get_node_or_null("Player") as CharacterBody3D
        if direct != null:
            return direct
        var nested := scene.find_child("Player", true, false) as CharacterBody3D
        if nested != null:
            return nested
    for child: Node in get_tree().root.get_children():
        if child == self:
            continue
        if child is CharacterBody3D and child.name == "Player":
            return child as CharacterBody3D
        var nested := child.find_child("Player", true, false) as CharacterBody3D
        if nested != null:
            return nested
    return null

func drive_player(actor: CharacterBody3D) -> String:
    if actor == null:
        return ""
    var visual := actor.get_node_or_null("VisualUpgrade")
    if visual == null or not visual.has_method("is_using_authored_character"):
        return ""
    if not bool(visual.call("is_using_authored_character")):
        return ""

    var animation_player := _find_animation_player(visual)
    if animation_player == null:
        return ""

    var clips := _clips_for(animation_player)
    var horizontal_speed := Vector2(actor.velocity.x, actor.velocity.z).length()
    var state := "idle"
    if horizontal_speed >= RUN_MIN_SPEED_MPS:
        state = "run"
    elif horizontal_speed > IDLE_MAX_SPEED_MPS:
        state = "walk"

    var clip := String(clips.get(state, ""))
    if clip.is_empty():
        return ""
    if animation_player.current_animation != clip:
        animation_player.play(StringName(clip), BLEND_SECONDS)
    return clip

func _find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer
    for child: Node in node.get_children():
        var found := _find_animation_player(child)
        if found != null:
            return found
    return null

func _clips_for(player: AnimationPlayer) -> Dictionary:
    var key := player.get_instance_id()
    if _clip_cache.has(key):
        return _clip_cache[key]
    var names: Array[String] = []
    for animation_name: String in player.get_animation_list():
        if animation_name != "RESET":
            names.append(animation_name)
    var clips := {
        "idle": _best_clip(names, ["idle"]),
        "walk": _best_clip(names, ["walk"]),
        "run": _best_clip(names, ["run", "sprint"]),
    }
    _clip_cache[key] = clips
    return clips

func _best_clip(names: Array[String], tokens: Array[String]) -> String:
    var best := ""
    var best_score := -100000
    for name_value: String in names:
        var lower := name_value.to_lower()
        var matched_token := ""
        for token: String in tokens:
            if token in lower:
                matched_token = token
                break
        if matched_token.is_empty():
            continue
        var score := 100
        if lower.begins_with(matched_token):
            score += 80
        if lower == matched_token:
            score += 120
        if "_a" in lower or lower.ends_with("a"):
            score += 8
        for bad_token: String in BAD_LOCOMOTION_TOKENS:
            if bad_token in lower:
                score -= 70
        score -= name_value.length()
        if score > best_score or (score == best_score and (best.is_empty() or name_value < best)):
            best_score = score
            best = name_value
    return best

func resolved_locomotion_clips(actor: CharacterBody3D) -> Dictionary:
    if actor == null:
        return {}
    var visual := actor.get_node_or_null("VisualUpgrade")
    if visual == null:
        return {}
    var animation_player := _find_animation_player(visual)
    if animation_player == null:
        return {}
    return _clips_for(animation_player).duplicate()

func truth_contract() -> Dictionary:
    return {
        "movement_source": "production Player CharacterBody3D horizontal velocity",
        "controller_physics_changed": false,
        "animation_source": "authored imported AnimationPlayer library",
        "states": ["idle", "walk", "run"],
        "run_threshold_mps": RUN_MIN_SPEED_MPS,
        "idle_threshold_mps": IDLE_MAX_SPEED_MPS,
        "combat_animation_penalty": true,
    }
