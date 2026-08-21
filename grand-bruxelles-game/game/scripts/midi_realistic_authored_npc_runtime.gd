extends Node

# Visual/animation-only adapter for production-authorized authored NPCs.
# Existing ambient pedestrian transforms remain the sole movement/navigation truth.
const AUTHORED_CHARACTER_PATH := NodePath("ProfiledNpcProxy/AuthoredCharacter")
const BANNED_PLAYER_ASSET := "res://assets/characters/player_character.glb"
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
const REJECT_ACTION_TOKENS: Array[String] = ["attack", "combat", "melee", "shoot", "fire", "hit", "hurt", "death", "die", "jump", "fall", "sword", "staff", "bow", "spell", "reload"]
const REJECT_LOCOMOTION_VARIANT_TOKENS: Array[String] = ["to", "transition", "start", "stop", "turn", "strafe", "back", "backward", "reverse"]

var _bindings: Dictionary = {}
var _binding_rejections: Dictionary = {}
var _last_positions: Dictionary = {}
var _states: Dictionary = {}
var _current_animations: Dictionary = {}
var _playback_scales: Dictionary = {}
var _authorized_bindings := 0
var _unauthorized_rejections := 0
var _incomplete_clip_rejections := 0
var _player_reuse_rejections := 0
var _tracked_pedestrians := 0
var _animated_pedestrians := 0
var _last_max_observed_speed_mps := 0.0

func _process(delta: float) -> void:
    _update_all(delta)

func _update_all(delta: float) -> void:
    if delta <= 0.0:
        return
    var tree := get_tree()
    if tree == null:
        return
    var live_ids: Dictionary = {}
    var tracked := 0
    var animated := 0
    var max_speed := 0.0
    for raw: Node in tree.get_nodes_in_group("ambient_pedestrian"):
        var person := raw as Node3D
        if person == null:
            continue
        var instance_id := person.get_instance_id()
        live_ids[instance_id] = true
        if not _binding_valid(instance_id):
            _clear_binding_state(instance_id, false)
            if _rejection_still_blocks(person, instance_id):
                continue
            if not bind_person(person):
                continue
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
        var planar_delta := Vector2(current_position.x - previous.x, current_position.z - previous.z)
        var displacement := planar_delta.length()
        var speed := 0.0
        if displacement <= TELEPORT_GUARD_M:
            speed = clampf(displacement / delta, 0.0, MAX_OBSERVED_SPEED_MPS)
        max_speed = maxf(max_speed, speed)
        if update_person_from_observed_speed(person, speed, delta) and str(_states.get(instance_id, "idle")) != "idle":
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
    _clear_binding_state(instance_id, false)
    var authored := person.get_node_or_null(AUTHORED_CHARACTER_PATH) as Node3D
    if authored == null:
        _record_rejection(instance_id, "missing_authored_character", false)
        return false
    if str(authored.get_meta("source_asset", "")) == BANNED_PLAYER_ASSET:
        _record_rejection(instance_id, "player_character_reuse_forbidden", false)
        _player_reuse_rejections += 1
        return false
    if not bool(authored.get_meta("production_authorized", false)):
        _record_rejection(instance_id, "production_unauthorized", true)
        return false
    if _find_animation_player(authored) == null:
        _record_rejection(instance_id, "missing_animation_player", false)
        _incomplete_clip_rejections += 1
        return false
    var animation_player := _find_locomotion_animation_player(authored)
    if animation_player == null:
        _record_rejection(instance_id, "missing_idle_walk_run", false)
        _incomplete_clip_rejections += 1
        return false
    var clips := _resolve_locomotion(animation_player)
    _localize_animation_libraries(animation_player)
    clips = _resolve_locomotion(animation_player)
    _configure_loops(animation_player, clips)
    _bindings[instance_id] = {"person": person, "authored": authored, "animation_player": animation_player, "clips": clips}
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
    if not _binding_valid(instance_id) and not bind_person(person):
        return false
    if not _binding_valid(instance_id):
        return false
    var binding: Dictionary = _bindings[instance_id]
    var authored := binding.get("authored") as Node3D
    var animation_player := binding.get("animation_player") as AnimationPlayer
    var clips := binding.get("clips", {}) as Dictionary
    if authored == null or animation_player == null:
        _clear_binding_state(instance_id, false)
        return false
    if not bool(authored.get_meta("production_authorized", false)):
        animation_player.stop()
        _clear_binding_state(instance_id, false)
        _record_rejection(instance_id, "authorization_revoked", true)
        return false
    if str(authored.get_meta("source_asset", "")) == BANNED_PLAYER_ASSET:
        animation_player.stop()
        _clear_binding_state(instance_id, false)
        _record_rejection(instance_id, "player_character_reuse_forbidden", false)
        _player_reuse_rejections += 1
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
    var _unused_delta := maxf(delta, 0.0)
    return true

func resolved_locomotion_for(person: Node3D) -> Dictionary:
    if person == null:
        return {}
    var instance_id := person.get_instance_id()
    if not _binding_valid(instance_id) and not bind_person(person):
        return {}
    var binding: Dictionary = _bindings.get(instance_id, {})
    return (binding.get("clips", {}) as Dictionary).duplicate(true)

func current_locomotion_state_for(person: Node3D) -> String:
    return "" if person == null else str(_states.get(person.get_instance_id(), ""))

func current_animation_for(person: Node3D) -> String:
    return "" if person == null else str(_current_animations.get(person.get_instance_id(), ""))

func current_playback_speed_scale_for(person: Node3D) -> float:
    return 1.0 if person == null else float(_playback_scales.get(person.get_instance_id(), 1.0))

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
    if not is_instance_valid(person) or not is_instance_valid(authored) or not is_instance_valid(animation_player):
        return false
    if person.get_node_or_null(AUTHORED_CHARACTER_PATH) != authored:
        return false
    if not authored.is_ancestor_of(animation_player):
        return false
    var clips := binding.get("clips", {}) as Dictionary
    for state: String in ["idle", "walk", "run"]:
        var clip_name := String(clips.get(state, ""))
        if clip_name.is_empty() or not animation_player.has_animation(clip_name):
            return false
    return true

func _rejection_still_blocks(person: Node3D, instance_id: int) -> bool:
    if not _binding_rejections.has(instance_id):
        return false
    var reason := str(_binding_rejections.get(instance_id, ""))
    var authored := person.get_node_or_null(AUTHORED_CHARACTER_PATH) as Node3D
    if reason == "missing_authored_character" and authored != null:
        _binding_rejections.erase(instance_id)
        return false
    if authored == null:
        return true
    if (reason == "production_unauthorized" or reason == "authorization_revoked") and bool(authored.get_meta("production_authorized", false)):
        _binding_rejections.erase(instance_id)
        return false
    if reason == "player_character_reuse_forbidden" and str(authored.get_meta("source_asset", "")) != BANNED_PLAYER_ASSET:
        _binding_rejections.erase(instance_id)
        return false
    if reason == "missing_animation_player" and _find_animation_player(authored) != null:
        _binding_rejections.erase(instance_id)
        return false
    if reason == "missing_idle_walk_run" and _find_locomotion_animation_player(authored) != null:
        _binding_rejections.erase(instance_id)
        return false
    return true

func _record_rejection(instance_id: int, reason: String, unauthorized: bool) -> void:
    if str(_binding_rejections.get(instance_id, "")) == reason:
        return
    _binding_rejections[instance_id] = reason
    if unauthorized:
        _unauthorized_rejections += 1

func _clear_binding_state(instance_id: int, clear_rejection: bool) -> void:
    _bindings.erase(instance_id)
    _states.erase(instance_id)
    _current_animations.erase(instance_id)
    _playback_scales.erase(instance_id)
    _last_positions.erase(instance_id)
    if clear_rejection:
        _binding_rejections.erase(instance_id)

func _find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer
    for child: Node in node.get_children():
        var found := _find_animation_player(child)
        if found != null:
            return found
    return null

func _find_locomotion_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        var candidate := node as AnimationPlayer
        var clips := _resolve_locomotion(candidate)
        if _clips_complete(clips):
            return candidate
    for child: Node in node.get_children():
        var found := _find_locomotion_animation_player(child)
        if found != null:
            return found
    return null

func _clips_complete(clips: Dictionary) -> bool:
    return not String(clips.get("idle", "")).is_empty() and not String(clips.get("walk", "")).is_empty() and not String(clips.get("run", "")).is_empty()

func _resolve_locomotion(animation_player: AnimationPlayer) -> Dictionary:
    var names: PackedStringArray = animation_player.get_animation_list()
    return {"idle": _choose_animation(names, "idle"), "walk": _choose_animation(names, "walk"), "run": _choose_animation(names, "run")}

func _normalize_animation_name(animation_name: String) -> String:
    return animation_name.to_lower().replace("-", "_").replace(" ", "_").replace(".", "_").replace("/", "_").replace(":", "_")

func _token_parts(normalized_name: String) -> PackedStringArray:
    return normalized_name.split("_", false)

func _has_exact_token(normalized_name: String, required_token: String) -> bool:
    for part: String in _token_parts(normalized_name):
        if part == required_token:
            return true
    return false

func _has_any_exact_token(normalized_name: String, rejected_tokens: Array[String]) -> bool:
    for part: String in _token_parts(normalized_name):
        if rejected_tokens.has(part):
            return true
    return false

func _choose_animation(names: PackedStringArray, required_token: String) -> String:
    for animation_name: String in names:
        if animation_name == "RESET":
            continue
        var lowered := _normalize_animation_name(animation_name)
        if not _has_exact_token(lowered, required_token):
            continue
        if _has_any_exact_token(lowered, REJECT_ACTION_TOKENS):
            continue
        if _has_any_exact_token(lowered, REJECT_LOCOMOTION_VARIANT_TOKENS):
            continue
        return animation_name
    return ""

func _localize_animation_libraries(animation_player: AnimationPlayer) -> void:
    var library_names := animation_player.get_animation_library_list()
    for library_name: StringName in library_names:
        var shared_library := animation_player.get_animation_library(library_name)
        if shared_library == null:
            continue
        var local_library := shared_library.duplicate(true) as AnimationLibrary
        if local_library == null:
            continue
        animation_player.remove_animation_library(library_name)
        var error := animation_player.add_animation_library(library_name, local_library)
        if error != OK:
            animation_player.add_animation_library(library_name, shared_library)

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
        "walk": return clampf(speed / WALK_REFERENCE_SPEED_MPS, WALK_PLAYBACK_MIN, WALK_PLAYBACK_MAX)
        "run": return clampf(speed / RUN_REFERENCE_SPEED_MPS, RUN_PLAYBACK_MIN, RUN_PLAYBACK_MAX)
        _: return 1.0

func _prune_stale(live_ids: Dictionary) -> void:
    for key: Variant in _bindings.keys():
        if not live_ids.has(key): _clear_binding_state(int(key), true)
    for key: Variant in _binding_rejections.keys():
        if not live_ids.has(key): _binding_rejections.erase(key)
    for key: Variant in _last_positions.keys():
        if not live_ids.has(key): _last_positions.erase(key)

func locomotion_stats() -> Dictionary:
    return {
        "tracked_pedestrians": _tracked_pedestrians,
        "animated_pedestrians": _animated_pedestrians,
        "max_observed_speed_mps": _last_max_observed_speed_mps,
        "authorized_bindings": _authorized_bindings,
        "unauthorized_rejections": _unauthorized_rejections,
        "incomplete_clip_rejections": _incomplete_clip_rejections,
        "player_reuse_rejections": _player_reuse_rejections,
        "active_binding_count": _bindings.size(),
        "changes_movement_owner": false,
        "changes_navigation": false,
        "movement_source": "planar XZ transform delta from existing ambient pedestrian owner",
        "production_authorization_required": true,
        "requires_idle_walk_run": true,
        "speed_sync": true,
        "state_hysteresis": true,
        "planar_speed_observation": true,
        "vertical_motion_affects_locomotion": false,
        "action_clip_fallback_allowed": false,
        "directional_transition_clip_fallback_allowed": false,
        "exact_locomotion_token_matching": true,
        "exact_rejection_token_matching": true,
        "player_character_reuse_allowed": false,
        "authorization_revocation_stops_animation": true,
        "dynamic_rejection_recovery": true,
        "binding_identity_guard": true,
        "rebind_resets_motion_history": true,
        "multi_animation_player_selection": true,
        "localized_animation_resources": true,
        "authored_character_path": str(AUTHORED_CHARACTER_PATH),
        "teleport_guard_m": TELEPORT_GUARD_M,
        "max_observed_speed_mps_limit": MAX_OBSERVED_SPEED_MPS,
    }
