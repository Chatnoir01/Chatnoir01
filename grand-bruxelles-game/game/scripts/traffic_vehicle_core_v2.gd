extends "res://game/scripts/traffic_vehicle_core.gd"

var _crossing_system: RefCounted = null


func set_crossing_system(crossing_system: RefCounted) -> void:
    _crossing_system = crossing_system


func _traffic_control_speed_cap(base_speed: float) -> float:
    if route_controls.is_empty():
        return base_speed

    var cap := base_speed
    var now_seconds := float(Time.get_ticks_msec()) / 1000.0
    if now_seconds < _stop_hold_until_s:
        return 0.0

    for control_variant: Variant in route_controls:
        if typeof(control_variant) != TYPE_DICTIONARY:
            continue
        var control: Dictionary = control_variant
        var control_route_index := int(control.get("route_index", -1))
        if control_route_index < route_index - 1 or control_route_index > route_index + 3:
            continue

        var control_position: Vector3 = control.get("route_position", Vector3.ZERO)
        var distance := global_position.distance_to(control_position)
        if distance > 32.0:
            continue

        var kind := str(control.get("kind", ""))
        var control_id := int(control.get("osm_id", 0))

        if kind == "traffic_signals" and _control_system != null:
            var approach: Vector3 = control.get("approach_direction", Vector3.ZERO)
            var state := str(_control_system.call("signal_state_for", control, approach))
            if state == "red":
                cap = minf(cap, _safe_approach_speed(distance, 2.6))
            elif state == "amber":
                var stopping_distance := speed_mps * speed_mps / maxf(0.1, 2.0 * braking_mps2) + 1.8
                if distance >= stopping_distance:
                    cap = minf(cap, _safe_approach_speed(distance, 2.6))

        elif kind == "give_way":
            if distance <= 18.0:
                cap = minf(cap, 3.0)
            if distance <= 6.0:
                cap = minf(cap, 1.5)

        elif kind == "crossing":
            var occupied := false
            if _crossing_system != null and control_id > 0:
                occupied = bool(_crossing_system.call("crossing_requires_stop", control_id))
            if occupied:
                cap = minf(cap, _safe_approach_speed(distance, 2.8))
                if distance <= 3.0:
                    cap = 0.0

        elif kind == "stop" and not _handled_controls.has(control_id):
            cap = minf(cap, _safe_approach_speed(distance, 2.2))
            if distance <= 2.8 and speed_mps <= 0.45:
                _handled_controls[control_id] = true
                _stop_hold_until_s = now_seconds + 0.8
                cap = 0.0

    return cap
