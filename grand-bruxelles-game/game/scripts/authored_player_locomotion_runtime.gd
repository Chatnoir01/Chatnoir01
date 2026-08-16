extends Node

const IDLE_MAX_SPEED_MPS := 0.20
const RUN_MIN_SPEED_MPS := 5.0
const LOCOMOTION_BLEND_SECONDS := 0.12
const REJECT_ACTION_TOKENS: Array[String] = ["attack", "combat", "melee", "sword", "staff", "bow", "gun", "shoot", "hit", "hurt", "death", "jump"]

var _player: CharacterBody3D
var _visual: Node
var _animation_player: AnimationPlayer
var _locomotion: Dictionary = {"idle": "", "walk": "", "run": ""}
var _current_animation: String = ""

func _process(_delta: float) -> void:
    if not _ensure_bound():
        return
    update_from_speed()

func _ensure_bound() -> bool:
    if is_instance_valid(_player) and is_instance_valid(_visual) and is_instance_valid(_animation_player):
        return true
    var scene := get_tree().current_scene
    if scene == null:
        return false
    var player := scene.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        return false
    var visual := player.get_node_or_null("VisualUpgrade")
    if visual == null:
        return false
    return bind_target(player, visual)

func bind_target(player: CharacterBody3D, visual: Node) -> bool:
    _clear_binding()
    if player == null or visual == null:
        return false
    if not visual.has_method("is_using_authored_character") or not bool(visual.call("is_using_authored_character")):
        return false
    var animation_player := _find_animation_player(visual)
    if animation_player == null:
        return false
    var resolved := _resolve_locomotion(animation_player)
    if String(resolved.get("idle", "")).is_empty() or String(resolved.get("walk", "")).is_empty() or String(resolved.get("run", "")).is_empty():
        push_error("Authored player locomotion: required idle/walk/run clips were not resolved from %s" % [animation_player.get_animation_list()])
        return false
    _player = player
    _visual = visual
    _animation_player = animation_player
    _locomotion = resolved
    _configure_locomotion_loops()
    set_meta("authored_locomotion_ready", true)
    set_meta("authored_locomotion_idle", String(_locomotion["idle"]))
    set_meta("authored_locomotion_walk", String(_locomotion["walk"]))
    set_meta("authored_locomotion_run", String(_locomotion["run"]))
    update_from_speed()
    return true

func _clear_binding() -> void:
    _player = null
    _visual = null
    _animation_player = null
    _locomotion = {"idle": "", "walk": "", "run": ""}
    _current_animation = ""
    remove_meta("authored_locomotion_ready")

func _find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer
    for child in node.get_children():
        var found := _find_animation_player(child)
        if found != null:
            return found
    return null

func _resolve_locomotion(animation_player: AnimationPlayer) -> Dictionary:
    var names: PackedStringArray = animation_player.get_animation_list()
    return {
        "idle": _choose_animation(names, ["idle"]),
        "walk": _choose_animation(names, ["walk"]),
        "run": _choose_animation(names, ["run"]),
    }

func _choose_animation(names: PackedStringArray, required_tokens: Array[String]) -> String:
    var fallback := ""
    for animation_name: String in names:
        if animation_name == "RESET":
            continue
        var lowered := animation_name.to_lower()
        var required := true
        for token: String in required_tokens:
            if not lowered.contains(token):
                required = false
                break
        if not required:
            continue
        if fallback.is_empty():
            fallback = animation_name
        var rejected := false
        for token: String in REJECT_ACTION_TOKENS:
            if lowered.contains(token):
                rejected = true
                break
        if not rejected:
            return animation_name
    return fallback

func _configure_locomotion_loops() -> void:
    if _animation_player == null:
        return
    for key: String in ["idle", "walk", "run"]:
        var animation_name := String(_locomotion.get(key, ""))
        if animation_name.is_empty() or not _animation_player.has_animation(animation_name):
            continue
        var animation := _animation_player.get_animation(animation_name)
        if animation != null:
            animation.loop_mode = Animation.LOOP_LINEAR

func update_from_speed() -> void:
    if not is_instance_valid(_player) or not is_instance_valid(_animation_player):
        return
    var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
    var target := String(_locomotion["idle"])
    if speed >= RUN_MIN_SPEED_MPS:
        target = String(_locomotion["run"])
    elif speed > IDLE_MAX_SPEED_MPS:
        target = String(_locomotion["walk"])
    if target.is_empty():
        return
    if _current_animation != target or _animation_player.current_animation != target or not _animation_player.is_playing():
        _animation_player.play(target, LOCOMOTION_BLEND_SECONDS)
        _current_animation = target

func resolved_locomotion_animations() -> Dictionary:
    return _locomotion.duplicate(true)

func current_animation() -> String:
    return _current_animation

func bound_animation_player() -> AnimationPlayer:
    return _animation_player
