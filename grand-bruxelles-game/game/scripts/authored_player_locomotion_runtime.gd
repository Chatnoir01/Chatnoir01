extends Node

const IDLE_ENTER_SPEED_MPS := 0.14
const IDLE_EXIT_SPEED_MPS := 0.26
const RUN_ENTER_SPEED_MPS := 5.20
const RUN_EXIT_SPEED_MPS := 4.50
const WALK_REFERENCE_SPEED_MPS := 2.50
const RUN_REFERENCE_SPEED_MPS := 7.00
const WALK_PLAYBACK_MIN := 0.65
const WALK_PLAYBACK_MAX := 1.50
const RUN_PLAYBACK_MIN := 0.82
const RUN_PLAYBACK_MAX := 1.24
const LOCOMOTION_BLEND_SECONDS := 0.12
const VISUAL_FACING_MIN_SPEED_MPS := 0.20
const VISUAL_FACING_TURN_SPEED_RAD_PER_S := deg_to_rad(540.0)
const VISUAL_FACING_RUN_TURN_SPEED_RAD_PER_S := deg_to_rad(1080.0)
const REJECT_ACTION_TOKENS: Array[String] = ["attack", "combat", "melee", "sword", "staff", "bow", "gun", "shoot", "hit", "hurt", "death", "jump"]

var _player: CharacterBody3D
var _visual: Node
var _authored_character: Node3D
var _authored_base_yaw: float = 0.0
var _animation_player: AnimationPlayer
var _locomotion: Dictionary = {"idle": "", "walk": "", "run": ""}
var _current_animation: String = ""
var _current_state: String = "idle"
var _current_playback_speed_scale: float = 1.0
var _current_visual_facing_offset: float = 0.0

func _process(delta: float) -> void:
    if not _ensure_bound():
        return
    update_from_speed(delta)

func _ensure_bound() -> bool:
    if is_instance_valid(_player) and is_instance_valid(_visual) and is_instance_valid(_animation_player) and is_instance_valid(_authored_character):
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
    var authored_character := visual.get_node_or_null("AuthoredCharacter") as Node3D
    if authored_character == null:
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
    _authored_character = authored_character
    _authored_base_yaw = authored_character.rotation.y
    _animation_player = animation_player
    _locomotion = resolved
    _configure_locomotion_loops()
    set_meta("authored_locomotion_ready", true)
    set_meta("authored_locomotion_idle", String(_locomotion["idle"]))
    set_meta("authored_locomotion_walk", String(_locomotion["walk"]))
    set_meta("authored_locomotion_run", String(_locomotion["run"]))
    set_meta("authored_locomotion_hysteresis", true)
    set_meta("authored_locomotion_speed_sync", true)
    set_meta("authored_locomotion_velocity_facing", true)
    set_meta("authored_locomotion_idle_facing_hold", true)
    set_meta("authored_locomotion_speed_scaled_facing", true)
    update_from_speed()
    return true

func _clear_binding() -> void:
    if is_instance_valid(_authored_character):
        _authored_character.rotation.y = _authored_base_yaw
    _player = null
    _visual = null
    _authored_character = null
    _authored_base_yaw = 0.0
    _animation_player = null
    _locomotion = {"idle": "", "walk": "", "run": ""}
    _current_animation = ""
    _current_state = "idle"
    _current_playback_speed_scale = 1.0
    _current_visual_facing_offset = 0.0
    remove_meta("authored_locomotion_ready")
    remove_meta("authored_locomotion_hysteresis")
    remove_meta("authored_locomotion_speed_sync")
    remove_meta("authored_locomotion_velocity_facing")
    remove_meta("authored_locomotion_idle_facing_hold")
    remove_meta("authored_locomotion_speed_scaled_facing")

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

func _resolve_state(speed: float) -> String:
    match _current_state:
        "run":
            if speed < RUN_EXIT_SPEED_MPS:
                return "idle" if speed < IDLE_ENTER_SPEED_MPS else "walk"
            return "run"
        "walk":
            if speed >= RUN_ENTER_SPEED_MPS:
                return "run"
            if speed < IDLE_ENTER_SPEED_MPS:
                return "idle"
            return "walk"
        _:
            if speed >= RUN_ENTER_SPEED_MPS:
                return "run"
            if speed > IDLE_EXIT_SPEED_MPS:
                return "walk"
            return "idle"

func _playback_scale_for_state(state: String, speed: float) -> float:
    match state:
        "walk":
            return clampf(speed / WALK_REFERENCE_SPEED_MPS, WALK_PLAYBACK_MIN, WALK_PLAYBACK_MAX)
        "run":
            return clampf(speed / RUN_REFERENCE_SPEED_MPS, RUN_PLAYBACK_MIN, RUN_PLAYBACK_MAX)
        _:
            return 1.0

func _visual_facing_turn_speed(speed: float) -> float:
    var run_weight := clampf(speed / RUN_REFERENCE_SPEED_MPS, 0.0, 1.0)
    return lerpf(VISUAL_FACING_TURN_SPEED_RAD_PER_S, VISUAL_FACING_RUN_TURN_SPEED_RAD_PER_S, run_weight)

func _update_visual_facing(delta: float) -> void:
    if not is_instance_valid(_player) or not is_instance_valid(_authored_character):
        return
    var horizontal_velocity := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
    var speed := horizontal_velocity.length()
    var target_offset := _current_visual_facing_offset
    if speed >= VISUAL_FACING_MIN_SPEED_MPS:
        var local_velocity := _player.global_transform.basis.inverse() * horizontal_velocity.normalized()
        target_offset = atan2(-local_velocity.x, -local_velocity.z)
    var max_step := _visual_facing_turn_speed(speed) * maxf(delta, 0.0)
    _current_visual_facing_offset = rotate_toward(_current_visual_facing_offset, target_offset, max_step)
    _authored_character.rotation.y = _authored_base_yaw + _current_visual_facing_offset

func update_from_speed(delta: float = 1.0 / 60.0) -> void:
    if not is_instance_valid(_player) or not is_instance_valid(_animation_player):
        return
    var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
    var target_state := _resolve_state(speed)
    var target := String(_locomotion.get(target_state, ""))
    if target.is_empty():
        return

    var target_scale := _playback_scale_for_state(target_state, speed)
    _animation_player.speed_scale = target_scale
    _current_playback_speed_scale = target_scale

    if _current_animation != target or _animation_player.current_animation != target or not _animation_player.is_playing():
        _animation_player.play(target, LOCOMOTION_BLEND_SECONDS)
        _current_animation = target
    _current_state = target_state
    _update_visual_facing(delta)

func resolved_locomotion_animations() -> Dictionary:
    return _locomotion.duplicate(true)

func current_animation() -> String:
    return _current_animation

func current_locomotion_state() -> String:
    return _current_state

func current_playback_speed_scale() -> float:
    return _current_playback_speed_scale

func current_visual_facing_offset_radians() -> float:
    return _current_visual_facing_offset

func bound_animation_player() -> AnimationPlayer:
    return _animation_player
