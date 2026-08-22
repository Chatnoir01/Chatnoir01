extends Node

const DODGE_KEY := KEY_X
const DODGE_DISTANCE_M := 1.65
const DODGE_DURATION_MS := 220
const DODGE_COOLDOWN_MS := 780
const DODGE_EVADE_WINDOW_MS := 260
const DODGE_MIN_EFFECTIVE_M := 0.22
const COMBAT_PHYSICS_PRIORITY := 100
const BASE_WALK_META := "combat_controller_base_walk_speed"
const BASE_SPRINT_META := "combat_controller_base_sprint_speed"

var _feedback_label: Label = null
var _feedback_hide_ms := 0

func _ready() -> void:
    process_physics_priority = COMBAT_PHYSICS_PRIORITY
    set_process(true)
    set_physics_process(true)
    set_process_input(true)

func _process(_delta: float) -> void:
    if _feedback_label != null and Time.get_ticks_msec() >= _feedback_hide_ms:
        _feedback_label.visible = false

func _physics_process(delta: float) -> void:
    var player := _current_player()
    if player == null or not is_instance_valid(player):
        return
    var dodge_motion_active := bool(player.get_meta("combat_dodge_motion_active", false))
    if dodge_motion_active:
        _tick_dodge_motion(player, delta)
        return
    _tick_attack_footwork(player, delta)
    apply_combat_input_scale(player, float(player.get_meta("combat_attack_input_scale", 1.0)))

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

func _current_player() -> CharacterBody3D:
    var scene := get_tree().current_scene
    if scene == null:
        return null
    return scene.get_node_or_null("Player") as CharacterBody3D

func _input_dodge_direction(player: CharacterBody3D) -> Vector3:
    var direction := Vector3.ZERO
    var basis := player.global_transform.basis
    var forward := -basis.z
    var right := basis.x
    if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_UP):
        direction += forward
    if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
        direction -= forward
    if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
        direction += right
    if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_LEFT):
        direction -= right
    direction.y = 0.0
    if direction.length_squared() <= 0.0001:
        direction = basis.z
        direction.y = 0.0
    return direction.normalized()

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

    var attack_phase := StringName(player.get_meta("combat_attack_phase", &"ready"))
    if attack_phase != &"ready":
        var melee_runtime := get_node_or_null("/root/PlayerMeleeCombatRuntime")
        if melee_runtime == null or not melee_runtime.has_method("request_action_cancel"):
            return {"dodged": false, "reason": "attack_locked"}
        var cancel_variant: Variant = melee_runtime.call("request_action_cancel", player, &"dodge")
        if not cancel_variant is Dictionary or not bool((cancel_variant as Dictionary).get("allowed", false)):
            var cancel_reason := "attack_locked"
            var remaining_ms := 0
            if cancel_variant is Dictionary:
                cancel_reason = String((cancel_variant as Dictionary).get("reason", cancel_reason))
                remaining_ms = int((cancel_variant as Dictionary).get("remaining_ms", 0))
            return {"dodged": false, "reason": cancel_reason, "remaining_ms": remaining_ms}

    var direction := requested_direction
    direction.y = 0.0
    if direction.length_squared() <= 0.0001:
        direction = player.global_transform.basis.z
        direction.y = 0.0
    if direction.length_squared() <= 0.0001:
        return {"dodged": false, "reason": "no_direction"}
    direction = direction.normalized()

    var until_ms := now + DODGE_DURATION_MS
    _capture_controller_speeds(player)
    apply_combat_input_scale(player, 0.0)
    player.velocity.x = 0.0
    player.velocity.z = 0.0
    player.set_meta("combat_next_dodge_ms", now + DODGE_COOLDOWN_MS)
    player.set_meta("combat_dodge_until_ms", now + DODGE_EVADE_WINDOW_MS)
    player.set_meta("combat_dodge_motion_started_ms", now)
    player.set_meta("combat_dodge_motion_until_ms", until_ms)
    player.set_meta("combat_dodge_motion_active", true)
    player.set_meta("combat_dodge_direction", direction)
    player.set_meta("combat_dodge_target_distance_m", DODGE_DISTANCE_M)
    player.set_meta("combat_dodge_distance_travelled_m", 0.0)
    player.set_meta("combat_dodge_blocked", false)
    player.set_meta("combat_dodge_failed_effective", false)
    player.set_meta("combat_dodge_count", int(player.get_meta("combat_dodge_count", 0)) + 1)
    player.set_meta("combat_last_dodge_direction", direction)
    player.set_meta("combat_last_dodge_distance_m", 0.0)
    _animate_dodge(player, direction)
    _show_feedback("ESQUIVE", 200)
    return {
        "dodged": true,
        "direction": direction,
        "distance_m": 0.0,
        "target_distance_m": DODGE_DISTANCE_M,
        "duration_ms": DODGE_DURATION_MS,
        "evade_window_ms": DODGE_EVADE_WINDOW_MS,
        "motion_until_ms": until_ms,
        "collided": false,
    }

func _tick_dodge_motion(player: CharacterBody3D, delta: float) -> void:
    var now := Time.get_ticks_msec()
    var until_ms := int(player.get_meta("combat_dodge_motion_until_ms", 0))
    if until_ms <= 0:
        _finish_dodge_motion(player, false)
        return
    if now >= until_ms:
        _finish_dodge_motion(player, false)
        return

    var direction: Vector3 = player.get_meta("combat_dodge_direction", Vector3.ZERO)
    direction.y = 0.0
    if direction.length_squared() <= 0.0001:
        _finish_dodge_motion(player, true)
        return
    direction = direction.normalized()

    var travelled := float(player.get_meta("combat_dodge_distance_travelled_m", 0.0))
    var remaining := maxf(DODGE_DISTANCE_M - travelled, 0.0)
    if remaining <= 0.0005:
        _finish_dodge_motion(player, false)
        return
    var step_distance := minf(dodge_speed_mps() * maxf(delta, 0.0), remaining)
    if step_distance <= 0.00001:
        return

    var before := player.global_position
    var collision := player.move_and_collide(direction * step_distance)
    var moved := player.global_position.distance_to(before)
    travelled += moved
    player.set_meta("combat_dodge_distance_travelled_m", travelled)
    player.set_meta("combat_last_dodge_distance_m", travelled)
    if collision != null or moved < step_distance * 0.25:
        _finish_dodge_motion(player, true)

func _finish_dodge_motion(player: CharacterBody3D, blocked: bool) -> void:
    var travelled := float(player.get_meta("combat_dodge_distance_travelled_m", 0.0))
    var ineffective := blocked and travelled < DODGE_MIN_EFFECTIVE_M
    player.set_meta("combat_dodge_motion_until_ms", 0)
    player.set_meta("combat_dodge_motion_active", false)
    player.set_meta("combat_dodge_blocked", blocked)
    player.set_meta("combat_dodge_failed_effective", ineffective)
    player.set_meta("combat_last_dodge_distance_m", travelled)
    var attack_scale := clampf(float(player.get_meta("combat_attack_input_scale", 1.0)), 0.0, 1.0)
    apply_combat_input_scale(player, attack_scale)
    if ineffective:
        player.set_meta("combat_dodge_until_ms", Time.get_ticks_msec())
        _show_feedback("ESQUIVE BLOQUÉE", 180)

func apply_combat_input_scale(player: CharacterBody3D, scale: float) -> void:
    if player == null or not is_instance_valid(player):
        return
    _set_controller_speed_scale(player, scale)

func _capture_controller_speeds(player: CharacterBody3D) -> void:
    if _has_property(player, &"walk_speed") and not player.has_meta(BASE_WALK_META):
        player.set_meta(BASE_WALK_META, maxf(float(player.get("walk_speed")), 0.0))
    if _has_property(player, &"sprint_speed") and not player.has_meta(BASE_SPRINT_META):
        player.set_meta(BASE_SPRINT_META, maxf(float(player.get("sprint_speed")), 0.0))

func _set_controller_speed_scale(player: CharacterBody3D, scale: float) -> void:
    _capture_controller_speeds(player)
    var clamped_scale := clampf(scale, 0.0, 1.0)
    if _has_property(player, &"walk_speed") and player.has_meta(BASE_WALK_META):
        player.set("walk_speed", float(player.get_meta(BASE_WALK_META, 0.0)) * clamped_scale)
    if _has_property(player, &"sprint_speed") and player.has_meta(BASE_SPRINT_META):
        player.set("sprint_speed", float(player.get_meta(BASE_SPRINT_META, 0.0)) * clamped_scale)
    player.set_meta("combat_controller_speed_scale", clamped_scale)

func _has_property(object: Object, property_name: StringName) -> bool:
    for property: Dictionary in object.get_property_list():
        if StringName(property.get("name", &"")) == property_name:
            return true
    return false

func _tick_attack_footwork(player: CharacterBody3D, delta: float) -> void:
    var now := Time.get_ticks_msec()
    var started_ms := int(player.get_meta("combat_attack_footwork_started_ms", 0))
    var until_ms := int(player.get_meta("combat_attack_footwork_until_ms", 0))
    if started_ms <= 0 or until_ms <= started_ms or now < started_ms or now >= until_ms:
        return
    if bool(player.get_meta("combat_attack_footwork_blocked", false)):
        return

    var target_distance := maxf(float(player.get_meta("combat_attack_lunge_m", 0.0)), 0.0)
    var travelled := maxf(float(player.get_meta("combat_attack_footwork_travelled_m", 0.0)), 0.0)
    var remaining := maxf(target_distance - travelled, 0.0)
    if remaining <= 0.0005:
        return

    var direction: Vector3 = player.get_meta("combat_attack_forward", Vector3.ZERO)
    direction.y = 0.0
    if direction.length_squared() <= 0.0001:
        return
    direction = direction.normalized()
    var duration_s := maxf(float(until_ms - started_ms) / 1000.0, 0.001)
    var speed := target_distance / duration_s
    var step_distance := minf(speed * maxf(delta, 0.0), remaining)
    var before := player.global_position
    var collision := player.move_and_collide(direction * step_distance)
    var moved := player.global_position.distance_to(before)
    travelled += moved
    player.set_meta("combat_attack_footwork_travelled_m", travelled)
    if collision != null or moved < step_distance * 0.25:
        player.set_meta("combat_attack_footwork_blocked", true)
        player.set_meta("combat_attack_footwork_until_ms", now)

func _animate_dodge(player: CharacterBody3D, direction: Vector3) -> void:
    var visual := player.get_node_or_null("VisualUpgrade") as Node3D
    if visual == null:
        return
    var local_right := player.global_transform.basis.x.normalized()
    var side := clampf(local_right.dot(direction), -1.0, 1.0)
    var base_z := visual.rotation.z
    var target_z := base_z - side * 0.16
    var tween := create_tween()
    tween.tween_property(visual, "rotation:z", target_z, 0.07)
    tween.tween_property(visual, "rotation:z", base_z, 0.15)

func _show_feedback(text: String, duration_ms: int) -> void:
    if _feedback_label == null:
        var layer := CanvasLayer.new()
        layer.name = "DodgeFeedbackLayer"
        add_child(layer)
        _feedback_label = Label.new()
        _feedback_label.name = "DodgeFeedback"
        _feedback_label.position = Vector2(520.0, 390.0)
        _feedback_label.size = Vector2(320.0, 44.0)
        _feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _feedback_label.add_theme_font_size_override("font_size", 21)
        layer.add_child(_feedback_label)
    _feedback_label.text = text
    _feedback_label.visible = true
    _feedback_hide_ms = Time.get_ticks_msec() + duration_ms

static func dodge_speed_mps() -> float:
    return DODGE_DISTANCE_M / maxf(float(DODGE_DURATION_MS) / 1000.0, 0.001)
