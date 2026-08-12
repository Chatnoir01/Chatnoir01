extends "res://game/scripts/traffic_vehicle_core_v3.gd"

signal traffic_disabled(vehicle: Node)

@export var traffic_impact_cooldown_ms: int = 450
@export_range(0.1, 1.0, 0.05) var transmitted_impact_factor: float = 0.78

const DAMAGE_MODEL_SCRIPT := preload("res://game/scripts/vehicle_damage_model.gd")

var _traffic_damage_model: RefCounted = null
var _traffic_next_impact_ms: int = 0
var _traffic_disabled_emitted: bool = false


func _ready() -> void:
    _traffic_damage_model = DAMAGE_MODEL_SCRIPT.new()
    super._ready()


func _physics_process(delta: float) -> void:
    if is_traffic_disabled():
        speed_mps = 0.0
        velocity.x = 0.0
        velocity.z = 0.0
        if not is_on_floor():
            velocity.y -= gravity * delta
        else:
            velocity.y = -0.1
        move_and_slide()
        return

    var impact_speed_kmh := speed_mps * 3.6
    var pre_move_forward := -global_transform.basis.z
    pre_move_forward.y = 0.0
    if pre_move_forward.length_squared() > 0.001:
        pre_move_forward = pre_move_forward.normalized()

    super._physics_process(delta)

    if is_on_wall() and impact_speed_kmh > 0.0:
        _register_traffic_collision(impact_speed_kmh, pre_move_forward)


func _register_traffic_collision(impact_speed_kmh: float, forward_direction: Vector3) -> void:
    if _traffic_damage_model == null or Time.get_ticks_msec() < _traffic_next_impact_ms:
        return

    var alignment := 0.42
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
        if forward_direction.length_squared() > 0.001:
            alignment = maxf(alignment, absf(forward_direction.dot(normal)))

    _traffic_damage_model.call("register_impact", impact_speed_kmh, alignment)
    _traffic_next_impact_ms = Time.get_ticks_msec() + traffic_impact_cooldown_ms
    _apply_damage_performance()
    _emit_disabled_if_needed()
    _transmit_collision_damage(impact_speed_kmh, alignment)


func _transmit_collision_damage(impact_speed_kmh: float, alignment: float) -> void:
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


func apply_external_impact(speed_kmh: float, alignment: float = 1.0) -> Dictionary:
    if _traffic_damage_model == null:
        _traffic_damage_model = DAMAGE_MODEL_SCRIPT.new()
    if Time.get_ticks_msec() < _traffic_next_impact_ms:
        return {"ignored_cooldown": true, "health": get_traffic_vehicle_health()}
    var result: Dictionary = _traffic_damage_model.call("register_impact", speed_kmh, alignment)
    _traffic_next_impact_ms = Time.get_ticks_msec() + traffic_impact_cooldown_ms
    _apply_damage_performance()
    _emit_disabled_if_needed()
    return result


func _apply_damage_performance() -> void:
    if _traffic_damage_model == null:
        return
    var performance := float(_traffic_damage_model.call("get_performance_factor"))
    if performance <= 0.0:
        speed_mps = 0.0
        return
    speed_mps = minf(speed_mps, speed_limit_mps * speed_factor * performance)


func _emit_disabled_if_needed() -> void:
    if not is_traffic_disabled() or _traffic_disabled_emitted:
        return
    _traffic_disabled_emitted = true
    speed_mps = 0.0
    velocity = Vector3.ZERO
    set_meta("traffic_wrecked", true)
    set_meta("traffic_wrecked_at_s", float(Time.get_ticks_msec()) / 1000.0)
    if _intersection_system != null:
        _intersection_system.call("release_vehicle", get_instance_id())
    traffic_disabled.emit(self)


func apply_traffic_test_impact(speed_kmh: float, alignment: float = 1.0) -> Dictionary:
    if _traffic_damage_model == null:
        _traffic_damage_model = DAMAGE_MODEL_SCRIPT.new()
    var result: Dictionary = _traffic_damage_model.call("register_impact", speed_kmh, alignment)
    _apply_damage_performance()
    _emit_disabled_if_needed()
    return result


func get_traffic_vehicle_health() -> float:
    if _traffic_damage_model == null:
        return 100.0
    return float(_traffic_damage_model.call("get_health"))


func get_traffic_vehicle_performance_factor() -> float:
    if _traffic_damage_model == null:
        return 1.0
    return float(_traffic_damage_model.call("get_performance_factor"))


func is_traffic_disabled() -> bool:
    if _traffic_damage_model == null:
        return false
    return bool(_traffic_damage_model.call("is_disabled"))
