extends Node

# Authored civilian/police locomotion adapter. This runtime never owns movement or
# navigation: it observes the existing ambient-pedestrian transform delta and only
# selects animation clips on an explicitly production-authorized AuthoredCharacter.
const AUTHORED_CHARACTER_PATH := NodePath("ProfiledNpcProxy/AuthoredCharacter")
const TELEPORT_GUARD_M := 6.0
const MAX_OBSERVED_SPEED_MPS := 2.4
const IDLE_ENTER_SPEED_MPS := 0.10
const IDLE_EXIT_SPEED_MPS := 0.20
const RUN_ENTER_SPEED_MPS := 1.65
const RUN_EXIT_SPEED_MPS := 1.45
const WALK_REFERENCE_SPEED_MPS := 1.0
const RUN_REFERENCE_SPEED_MPS := 1.85
const WALK_PLAYBACK_MIN := 0.68
const WALK_PLAYBACK_MAX := 1.45
const RUN_PLAYBACK_MIN := 0.82
const RUN_PLAYBACK_MAX := 1.22
const LOCOMOTION_BLEND_SECONDS := 0.14
const REJECT_ACTION_TOKENS: Array[String] = [
    "attack", "combat", "melee", "shoot", "fire", "hit", "hurt", "death",
    "die", "jump", "fall", "sword", "staff", "bow", "spell", "reload"
]

var _bindings: Dictionary = {}
var _binding_rejections: Dictionary = {}
var _last_positions: Dictionary = {}
var _states: Dictionary = {}
var _current_animations: Dictionary = {}
var _playback_scales: Dictionary = {}
var _authorized_bindings: int = 0
var _unauthorized_rejections: int = 0
var _incomplete_clip_rejections: int = 0
var _tracked_pedestrians: int = 0
var _animated_pedestrians: int = 0
var _last_max_observed_speed_mps: float = 0.0

func _process(delta: float) -> void:
    _update_all(delta)

func _update_all(delta: float) -> void:
    if delta <= 0.0:
        return
    var live_ids: Dictionary = {}
    var tracked := 0
    var animated := 0
    var max_speed := 0.0

    for raw: Node in get_tree().get_nodes_in_group("ambient_pedestrian"):
        var person := raw as Node3D
        if person == null:
            continue
        var instance_id := person.get_instance_id()
        live_ids[instance_id] = true

        if not _bindings.has(instance_id):
            if _binding_rejections.has(instance_id):
                continue
            bind_person(person)
        if not _binding_valid(instance_id):
            continue

        tracked += 1
        var current_position := person.global_position
        if not _last_positions.has(instance_id):
            _last_positions[instance_id] = current_position
            update_person_from_observed_speed(person, 0.0, delta)
            continue

        var previous: Vector3 = _last_positions[instance_id]
        _last_positions[instance_id] = current_position
        var displacement := current_position.distance_to(previous)
        var speed := 0.0
        if displacement <= TELEPORT_GUARD_M:
            speed = clampf(displacement / delta, 0.0, MAX_OBSERVED_SPEED_MPS)
        max_speed = maxf(max_speed, speed)
        if update_person_from_observed_speed(person, speed, delta):
            if str(_states.get(instance_id, "idle")) != "idle":
                animated += 1

    _tracked_pedestrians = tracked
    _animated_pedestrians = animated
    _last_max_observed_speed_mps = max_speed
    _prune_stale(live_ids)

func bind_person(person: Node3D) -> bool:
    if person == null:
        return false
    var instance_id := person.get_instance_id()
    if _binding_valid(instance_id):
        return true

    _bindings.erase(instance_id)
    _states.erase(instance_id)
    _current_animations.erase(instance_id)
    _playback_scales.erase(instance_id)

    var authored := person.get_node_or_null(AUTHORED_CHARACTER_PATH) as Node3D
    if authored == null:
        _record_rejection(instance_id, "missing_authored_character", false)
        return false
    if not bool(authored.get_meta("production_authorized", false)):
        _record_rejection(instance_id, "production_unauthorized", true)
        return false

    var animation_player := _find_animation_player(authored)
    if animation_player == null:
        _record_rejection(instance_id, "missing_animation_player", false)
        _incomplete_clip_rejections += 1
        return false

    var clips := _resolve_locomotion(animation_player)
    if String(clips.get("idle", "")).is_empty() or String(clips.get("walk", "")).is_empty() or String(clips.get("run", "")).is_empty():
        _record_rejection(instance_id, "missing_idle_walk_run", false)
        _incomplete_clip_rejections += 1
        return false

    _configure_loops(animation_player, clips)
    _bindings[instance_id] = {
        "person": person,
        "authored": authored,
        "animation_player": animation_player,
        "clips": clips,
    }
    _binding_rejections.erase(instance_id)
    _states[instance_id] = "idle"
    _current_animations[instance_id] = ""
    _playback_scales[instance_id] = 1.0
    _authorized_bindings += 1
    return true

func update_person_from_observed_speed(person: Node3D, observed_speed_mps: float, delta: float = 1.0 / 60.0) -> bool:
    if person == null:
        return false
    var instance_id := person.get_instance_id()
    if not _binding_valid(instance_id):
        if not bind_person(person):
            return false
    if not _binding_valid(instance_id):
        return false

    var binding: Dictionary = _bindings[instance_id]
    var authored := binding.get("authored") as Node3D
    var animation_player := binding.get("animation_player") as AnimationPlayer
    var clips := binding.get("clips", {}) as Dictionary
    if authored == null or animation_player == null:
        _bindings.erase(instance_id)
        return false
    if not bool(authored.get_meta("production_authorized", false)):
        _bindings.erase(instance_id)
        _record_rejection(instance_id, "authorization_revoked", true)
        return false

    var speed := clampf(maxf(observed_speed_mps, 0.0), 0.0, MAX_OBSERVED_SPEED_MPS)
    var current_state := str(_states.get(instance_id, "idle"))
    var target_state := _resolve_state(current_state, speed)
    var target_animation := String(clips.get(target_state, ""))
    if target_animation.is_empty() or not animation_player.has_animation(target_animation):
        return false

    var playback_scale := _playback_scale_for_state(target_state, speed)
    animation_player.speed_scale = playback_scale
    _playback_scales[instance_id] = playback_scale
    if str(_current_animations.get(instance_id, "")) != target_animation or animation_player.current_animation != target_animation or not animation_player.is_playing():
        animation_player.play(target_animation, LOCOMOTION_BLEND_SECONDS)
        _current_animations[instance_id] = target_animation
    _states[instance_id] = target_state

    # delta is intentionally accepted to mirror the production process call and to
    # keep future blend/facing work deterministic, but this adapter never modifies
    # the pedestrian transform itself.
    var _unused_delta := maxf(delta, 0.0)
    return true

func resolved_locomotion_for(person: Node3D) -> Dictionary:
    if person == null:
        return {}
    var instance_id := person.get_instance_id()
    if not _binding_valid(instance_id):
        if not bind_person(person):
            return {}
    var binding: Dictionary = _bindings.get(instance_id, {})
    var clips: Dictionary = binding.get("clips", {})
    return clips.duplicate(true)

func current_locomotion_state_for(person: Node3D) -> String:
    if person == null:
        return ""
    return str(_states.get(person.get_instance_id(), ""))

func current_animation_for(person: Node3D) -> String:
    if person == null:
        return ""
    return str(_current_animations.get(person.get_instance_id(), ""))

func current_playback_speed_scale_for(person: Node3D) -> float:
    if person == null:
        return 1.0
    return float(_playback_scales.get(person.get_instance_id(), 1.0))

func _binding_valid(instance_id: int) -> bool:
    var binding_variant: Variant = _bindings.get(instance_id, {})
    if not binding_variant is Dictionary:
        return false
    var binding := binding_variant as Dictionary
    if binding.is_empty():
        return false
    var person := binding.get("person") as Node3D
    var authored := binding.get("authored") as Node3D
    var animation_player := binding.get("animation_player") as AnimationPlayer
    return is_instance_valid(person) and is_instance_valid(authored) and is_instance_valid(animation_player)

func _record_rejection(instance_id: int, reason: String, unauthorized: bool) -> void:
    if _binding_rejections.has(instance_id):
        return
    _binding_rejections[instance_id] = reason
    if unauthorized:
        _unauthorized_rejections += 1

func _find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer
    for child: Node in node.get_children():
        var found := _find_animation_player(child)
        if found != null:
            return found
    return null

func _resolve_locomotion(animation_player: AnimationPlayer) -> Dictionary:
    var names: PackedStringArray = animation_player.get_animation_list()
    return {
        "idle": _choose_animation(names, "idle"),
        "walk": _choose_animation(names, "walk"),
        "run": _choose_animation(names, "run"),
    }

func _choose_animation(names: PackedStringArray, required_token: String) -> String:
    var fallback := ""
    for animation_name: String in names:
        if animation_name == "RESET":
            continue
        var lowered := animation_name.to_lower()
        if not lowered.contains(required_token):
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

func _configure_loops(animation_player: AnimationPlayer, clips: Dictionary) -> void:
    for state: String in ["idle", "walk", "run"]:
        var animation_name := String(clips.get(state, ""))
        if animation_name.is_empty() or not animation_player.has_animation(animation_name):
            continue
        var animation := animation_player.get_animation(animation_name)
        if animation != null:
            animation.loop_mode = Animation.LOOP_LINEAR

func _resolve_state(current_state: String, speed: float) -> String:
    match current_state:
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

func _prune_stale(live_ids: Dictionary) -> void:
    for key: Variant in _last_positions.keys():
        if live_ids.has(key):
            continue
        _last_positions.erase(key)
        _bindings.erase(key)
        _binding_rejections.erase(key)
        _states.erase(key)
        _current_animations.erase(key)
        _playback_scales.erase(key)

func locomotion_stats() -> Dictionary:
    return {
        "tracked_pedestrians": _tracked_pedestrians,
        "animated_pedestrians": _animated_pedestrians,
        "max_observed_speed_mps": _last_max_observed_speed_mps,
        "authorized_bindings": _authorized_bindings,
        "unauthorized_rejections": _unauthorized_rejections,
        "incomplete_clip_rejections": _incomplete_clip_rejections,
        "active_binding_count": _bindings.size(),
        "changes_movement_owner": false,
        "changes_navigation": false,
        "movement_source": "observed transform delta from existing ambient pedestrian owner",
        "production_authorization_required": true,
        "requires_idle_walk_run": true,
        "speed_sync": true,
        "state_hysteresis": true,
        "authored_character_path": str(AUTHORED_CHARACTER_PATH),
        "teleport_guard_m": TELEPORT_GUARD_M,
        "max_observed_speed_mps_limit": MAX_OBSERVED_SPEED_MPS,
    }
