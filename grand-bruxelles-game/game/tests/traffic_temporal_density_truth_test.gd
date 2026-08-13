extends SceneTree

const DENSITY_SCRIPT := preload("res://game/scripts/traffic_density_model.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("TRAFFIC_TEMPORAL_DENSITY_TRUTH_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var density: RefCounted = DENSITY_SCRIPT.new()
    var probe_hours: Array[float] = [0.0, 4.5, 6.0, 8.0, 12.0, 17.0, 20.0, 23.5]
    for hour: float in probe_hours:
        var factor := float(density.call("time_factor", hour))
        if absf(factor - 1.0) > 0.0001:
            _fail("unsourced hour %.2f changes traffic volume with factor %.3f" % [hour, factor])
            return

    print("TRAFFIC_TEMPORAL_DENSITY_TRUTH_OK: no time-of-day volume curve without authoritative temporal evidence")
    quit(0)
