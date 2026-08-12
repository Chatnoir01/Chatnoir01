extends "res://game/scripts/traffic_manager_core_v7.gd"

@export var wreck_clear_delay_s: float = 18.0
@export var wreck_cleanup_interval_s: float = 1.0
@export var max_wrecks_before_fast_clear: int = 3

var _wreck_cleanup_elapsed: float = 0.0


func _process(delta: float) -> void:
    super._process(delta)
    _wreck_cleanup_elapsed += delta
    if _wreck_cleanup_elapsed < wreck_cleanup_interval_s:
        return
    _wreck_cleanup_elapsed = 0.0
    cleanup_wrecks_at(float(Time.get_ticks_msec()) / 1000.0)


func _create_vehicle_node() -> CharacterBody3D:
    var vehicle := super._create_vehicle_node()
    if vehicle.has_signal("traffic_disabled"):
        vehicle.connect("traffic_disabled", Callable(self, "_on_traffic_vehicle_disabled"))
    return vehicle


func _on_traffic_vehicle_disabled(vehicle: Node) -> void:
    if not is_instance_valid(vehicle):
        return
    vehicle.add_to_group("traffic_wreck")
    vehicle.set_meta("traffic_wrecked", true)
    if not vehicle.has_meta("traffic_wrecked_at_s"):
        vehicle.set_meta("traffic_wrecked_at_s", float(Time.get_ticks_msec()) / 1000.0)
    vehicle.set_meta("traffic_wreck_clear_after_s", _effective_wreck_delay())


func _effective_wreck_delay() -> float:
    if get_wreck_count() >= max_wrecks_before_fast_clear:
        return maxf(4.0, wreck_clear_delay_s * 0.45)
    return maxf(1.0, wreck_clear_delay_s)


func cleanup_wrecks_at(now_seconds: float) -> int:
    if _traffic_root == null:
        return 0
    var cleared := 0
    for child: Node in _traffic_root.get_children():
        if child.is_queued_for_deletion() or not bool(child.get_meta("traffic_wrecked", false)):
            continue
        var wrecked_at := float(child.get_meta("traffic_wrecked_at_s", now_seconds))
        var delay := float(child.get_meta("traffic_wreck_clear_after_s", wreck_clear_delay_s))
        if now_seconds < wrecked_at + maxf(0.0, delay):
            continue
        child.queue_free()
        cleared += 1
    if cleared > 0:
        call_deferred("_replenish_traffic")
    return cleared


func get_wreck_count() -> int:
    if _traffic_root == null:
        return 0
    var count := 0
    for child: Node in _traffic_root.get_children():
        if not child.is_queued_for_deletion() and bool(child.get_meta("traffic_wrecked", false)):
            count += 1
    return count
