extends CharacterBody3D

@export var max_forward_speed: float = 24.0
@export var max_reverse_speed: float = 8.0
@export var acceleration: float = 12.0
@export var braking: float = 20.0
@export var handbrake_strength: float = 30.0
@export var coast_drag: float = 7.5
@export var steering_speed: float = 1.55
@export var exit_distance: float = 2.7
@export var mouse_sensitivity: float = 0.0022
@export var impact_cooldown_ms: int = 350
@export_range(0.1, 1.0, 0.05) var transmitted_impact_factor: float = 0.78
@export var recovery_delay_s: float = 4.0

const DAMAGE_MODEL_SCRIPT := preload("res://game/scripts/vehicle_damage_model.gd")
const RECOVERY_MODEL_SCRIPT := preload("res://game/scripts/vehicle_recovery_model.gd")

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D

var driver: CharacterBody3D = null
var speed: float = 0.0
var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var _exit_unlock_ms: int = 0
var _next_impact_ms: int = 0
var _damage_model: RefCounted
var _recovery_model: RefCounted
var _last_safe_position := Vector3.ZERO
var _safe_position_initialized := false
var _safe_position_elapsed: float = 0.0


func _ready() -> void:
    _damage_model = DAMAGE_MODEL_SCRIPT.new()
    _recovery_model = RECOVERY_MODEL_SCRIPT.new()
    _last_safe_position = global_position
    _safe_position_initialized = true


func _physics_process(delta: float) -> void:
    _process_recovery()

    if not is_on_floor():
        velocity.y -= gravity * delta
    else:
        velocity.y = -0.1

    var throttle: float = 0.0
    var steering: float = 0.0
    var handbrake_pressed: bool = false
    if driver != null and not is_vehicle_disabled() and get_recovery_state() != "requested":
        var forward_pressed: bool = Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_Z)
        var reverse_pressed: bool = Input.is_key_pressed(KEY_S)
        var left_pressed: bool = Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_Q)
        var right_pressed: bool = Input.is_key_pressed(KEY_D)
        handbrake_pressed = Input.is_key_pressed(KEY_SPACE)
        var touch: Node = get_parent().get_node_or_null("MobileControls")
        if touch != null:
            forward_pressed = forward_pressed or bool(touch.get("forward_pressed"))
            reverse_pressed = reverse_pressed or bool(touch.get("backward_pressed"))
            left_pressed = left_pressed or bool(touch.get("left_pressed"))
            right_pressed = right_pressed or bool(touch.get("right_pressed"))
        throttle = float(forward_pressed) - float(reverse_pressed)
        steering = float(right_pressed) - float(left_pressed)

    var performance := get_vehicle_performance_factor()
    var effective_forward_speed := max_forward_speed * performance
    var effective_reverse_speed := max_reverse_speed * maxf(0.55, performance)
    var effective_acceleration := acceleration * maxf(0.48, performance)

    if is_vehicle_disabled() or get_recovery_state() == "requested":
        speed = move_toward(speed, 0.0, braking * delta)
    elif handbrake_pressed:
        speed = move_toward(speed, 0.0, handbrake_strength * delta)
    elif throttle > 0.0:
        speed = move_toward(speed, effective_forward_speed, effective_acceleration * delta)
    elif throttle < 0.0:
        if speed > 1.0:
            speed = move_toward(speed, 0.0, braking * delta)
        else:
            speed = move_toward(speed, -effective_reverse_speed, effective_acceleration * delta)
    else:
        speed = move_toward(speed, 0.0, coast_drag * delta)

    if absf(speed) > 0.15 and absf(steering) > 0.01:
        var speed_ratio: float = clampf(absf(speed) / maxf(0.1, max_forward_speed), 0.18, 1.0)
        var direction_sign: float = 1.0 if speed >= 0.0 else -1.0
        rotation.y -= steering * steering_speed * speed_ratio * direction_sign * delta

    var impact_speed_kmh := absf(speed) * 3.6
    var forward_vector: Vector3 = -global_transform.basis.z
    velocity.x = forward_vector.x * speed
    velocity.z = forward_vector.z * speed
    move_and_slide()

    if is_on_wall():
        _register_wall_impact(impact_speed_kmh, forward_vector)
        speed *= 0.35
        if is_vehicle_disabled():
            speed = 0.0
    else:
        _safe_position_elapsed += delta
        if _safe_position_elapsed >= 1.0 and is_on_floor() and not is_vehicle_disabled():
            _safe_position_elapsed = 0.0
            _last_safe_position = global_position
            _safe_position_initialized = true


func _register_wall_impact(impact_speed_kmh: float, forward_vector: Vector3) -> void:
    if _damage_model == null or Time.get_ticks_msec() < _next_impact_ms:
        return

    var best_alignment := 0.42
    for index: int in range(get_slide_collision_count()):
        var collision := get_slide_collision(index)
        if collision == null:
            continue
        var normal := collision.get_normal()
        if absf(normal.y) > 0.65:
            continue
        normal.y = 0.0
        if normal.length_squared() <= 0.001:
            continue
        normal = normal.normalized()
        var flat_forward := forward_vector
        flat_forward.y = 0.0
        if flat_forward.length_squared() > 0.001:
            flat_forward = flat_forward.normalized()
            best_alignment = maxf(best_alignment, absf(flat_forward.dot(normal)))

    _damage_model.call("register_impact", impact_speed_kmh, best_alignment)
    _next_impact_ms = Time.get_ticks_msec() + impact_cooldown_ms
    _transmit_wall_impact(impact_speed_kmh, best_alignment)


func _transmit_wall_impact(impact_speed_kmh: float, alignment: float) -> void:
    var seen := {}
    for index: int in range(get_slide_collision_count()):
        var collision := get_slide_collision(index)
        if collision == null:
            continue
        var collider: Object = collision.get_collider()
        if collider == null or collider == self:
            continue
        var collider_id := collider.get_instance_id()
        if seen.has(collider_id):
            continue
        seen[collider_id] = true
        _transmit_impact_to_collider(
            collider,
            impact_speed_kmh * transmitted_impact_factor,
            alignment
        )


func _transmit_impact_to_collider(collider: Object, speed_kmh: float, alignment: float) -> bool:
    if collider == null or collider == self:
        return false
    if collider.has_method("apply_external_impact"):
        collider.call("apply_external_impact", speed_kmh, alignment)
        return true
    if collider.has_method("apply_external_vehicle_impact"):
        collider.call("apply_external_vehicle_impact", speed_kmh, alignment)
        return true
    return false


func apply_external_vehicle_impact(speed_kmh: float, alignment: float = 1.0) -> Dictionary:
    if _damage_model == null:
        _damage_model = DAMAGE_MODEL_SCRIPT.new()
    if Time.get_ticks_msec() < _next_impact_ms:
        return {"ignored_cooldown": true, "health": get_vehicle_health()}
    var result: Dictionary = _damage_model.call("register_impact", speed_kmh, alignment)
    _next_impact_ms = Time.get_ticks_msec() + impact_cooldown_ms
    if is_vehicle_disabled():
        speed = 0.0
        velocity = Vector3.ZERO
    else:
        var performance := get_vehicle_performance_factor()
        speed = clampf(
            speed,
            -max_reverse_speed * maxf(0.55, performance),
            max_forward_speed * performance
        )
    return result


func _process_recovery() -> void:
    if _recovery_model == null or get_recovery_state() != "requested":
        return
    var now_seconds := float(Time.get_ticks_msec()) / 1000.0
    if not bool(_recovery_model.call("is_ready", now_seconds)):
        return

    speed = 0.0
    velocity = Vector3.ZERO
    if _safe_position_initialized:
        global_position = _last_safe_position + Vector3.UP * 0.55
    if _damage_model != null:
        var repair_amount := float(_recovery_model.call("get_roadside_repair_amount"))
        _damage_model.call("repair", repair_amount)
    _recovery_model.call("complete_recovery", now_seconds)


func _unhandled_input(event: InputEvent) -> void:
    if driver == null:
        return
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        camera_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
        camera_pivot.rotation.y = clampf(camera_pivot.rotation.y, -1.35, 1.35)
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_E and Time.get_ticks_msec() >= _exit_unlock_ms:
            exit_driver()
        elif event.keycode == KEY_R and is_vehicle_disabled():
            request_roadside_recovery()
        elif event.keycode == KEY_ESCAPE:
            Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED


func enter_driver(player: CharacterBody3D) -> void:
    if driver != null:
        return
    driver = player
    speed = 0.0
    _exit_unlock_ms = Time.get_ticks_msec() + 350
    camera_pivot.rotation.y = 0.0
    player.call("set_vehicle_mode", true)
    camera.current = true
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if DisplayServer.is_touchscreen_available() else Input.MOUSE_MODE_CAPTURED


func exit_driver() -> void:
    if driver == null:
        return
    var player: CharacterBody3D = driver
    driver = null
    speed = 0.0
    var side: Vector3 = global_transform.basis.x.normalized()
    player.global_position = global_position + side * exit_distance + Vector3.UP * 0.8
    player.rotation.y = rotation.y
    player.call("set_vehicle_mode", false)


func has_driver() -> bool:
    return driver != null


func get_speed_mps() -> float:
    return speed


func get_speed_kmh() -> float:
    return absf(speed) * 3.6


func get_max_forward_speed_kmh() -> float:
    return max_forward_speed * 3.6


func get_vehicle_health() -> float:
    if _damage_model == null:
        return 100.0
    return float(_damage_model.call("get_health"))


func get_vehicle_body_damage() -> float:
    if _damage_model == null:
        return 0.0
    return float(_damage_model.get("body_damage"))


func get_vehicle_mechanical_damage() -> float:
    if _damage_model == null:
        return 0.0
    return float(_damage_model.get("mechanical_damage"))


func get_vehicle_performance_factor() -> float:
    if _damage_model == null:
        return 1.0
    return float(_damage_model.call("get_performance_factor"))


func is_vehicle_disabled() -> bool:
    if _damage_model == null:
        return false
    return bool(_damage_model.call("is_disabled"))


func apply_test_impact(speed_kmh: float, alignment: float = 1.0) -> Dictionary:
    if _damage_model == null:
        _damage_model = DAMAGE_MODEL_SCRIPT.new()
    return _damage_model.call("register_impact", speed_kmh, alignment)


func repair_vehicle(amount: float = 100.0) -> Dictionary:
    if _damage_model == null:
        _damage_model = DAMAGE_MODEL_SCRIPT.new()
    return _damage_model.call("repair", amount)


func request_roadside_recovery() -> bool:
    if not is_vehicle_disabled() or _recovery_model == null:
        return false
    var now_seconds := float(Time.get_ticks_msec()) / 1000.0
    _recovery_model.call(
        "request_recovery",
        get_vehicle_body_damage(),
        get_vehicle_mechanical_damage(),
        now_seconds,
        recovery_delay_s
    )
    return true


func get_recovery_state() -> String:
    if _recovery_model == null:
        return "idle"
    return str(_recovery_model.get("state"))


func get_recovery_remaining_seconds() -> float:
    if _recovery_model == null:
        return 0.0
    return float(_recovery_model.call("remaining_seconds", float(Time.get_ticks_msec()) / 1000.0))


func get_recovery_quote_eur() -> float:
    if _recovery_model == null:
        return 0.0
    return float(_recovery_model.get("quote_eur"))
