extends Node

const DODGE_DISTANCE_M := 1.65
const DODGE_COOLDOWN_MS := 780
const DODGE_EVADE_WINDOW_MS := 260
const DODGE_MIN_EFFECTIVE_M := 0.22

var _feedback_label: Label = null
var _feedback_hide_ms := 0

func _ready() -> void:
    set_process(true)
    set_process_input(true)

func _process(_delta: float) -> void:
    if _feedback_label != null and Time.get_ticks_msec() >= _feedback_hide_ms:
        _feedback_label.visible = false

func _input(event: InputEvent) -> void:
    if not event is InputEventKey:
        return
    var key_event := event as InputEventKey
    if key_event.keycode != KEY_Q or not key_event.pressed or key_event.echo:
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
    if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
        direction += forward
    if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
        direction -= forward
    if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
        direction += right
    if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
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

    var direction := requested_direction
    direction.y = 0.0
    if direction.length_squared() <= 0.0001:
        direction = player.global_transform.basis.z
        direction.y = 0.0
    if direction.length_squared() <= 0.0001:
        return {"dodged": false, "reason": "no_direction"}
    direction = direction.normalized()

    var start := player.global_position
    var collision := player.move_and_collide(direction * DODGE_DISTANCE_M)
    var travelled := player.global_position.distance_to(start)
    if travelled < DODGE_MIN_EFFECTIVE_M:
        _show_feedback("ESQUIVE BLOQUÉE", 180)
        return {
            "dodged": false,
            "reason": "blocked",
            "distance_m": travelled,
            "collided": collision != null,
        }

    player.set_meta("combat_next_dodge_ms", now + DODGE_COOLDOWN_MS)
    player.set_meta("combat_dodge_until_ms", now + DODGE_EVADE_WINDOW_MS)
    player.set_meta("combat_dodge_count", int(player.get_meta("combat_dodge_count", 0)) + 1)
    player.set_meta("combat_last_dodge_direction", direction)
    player.set_meta("combat_last_dodge_distance_m", travelled)
    _animate_dodge(player, direction)
    _show_feedback("ESQUIVE", 200)
    return {
        "dodged": true,
        "direction": direction,
        "distance_m": travelled,
        "evade_window_ms": DODGE_EVADE_WINDOW_MS,
        "collided": collision != null,
    }

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
