extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("TRAFFIC_DENSITY_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var script: Script = load("res://game/scripts/traffic_density_model.gd")
    if script == null:
        _fail("density model script did not load")
        return

    var model: RefCounted = script.new()
    var night := float(model.call("time_factor", 2.0))
    var morning_peak := float(model.call("time_factor", 8.0))
    var evening_peak := float(model.call("time_factor", 17.0))
    if not (night < morning_peak and morning_peak <= evening_peak):
        _fail("time profile ordering is invalid: %.2f / %.2f / %.2f" % [night, morning_peak, evening_peak])
        return

    var arterial_roads: Array[Dictionary] = [
        {"class": "primary", "lanes": 4, "points": [[-20.0, 0.0], [20.0, 0.0]]},
        {"class": "secondary", "lanes": 2, "points": [[0.0, -20.0], [0.0, 20.0]]},
    ]
    var local_roads: Array[Dictionary] = [
        {"class": "living_street", "lanes": 1, "points": [[-20.0, 0.0], [20.0, 0.0]]},
        {"class": "residential", "lanes": 1, "points": [[0.0, -20.0], [0.0, 20.0]]},
    ]
    var arterial_factor := float(model.call("local_capacity_factor", arterial_roads, Vector3.ZERO))
    var local_factor := float(model.call("local_capacity_factor", local_roads, Vector3.ZERO))
    if arterial_factor <= local_factor:
        _fail("arterial road capacity should exceed local-street capacity")
        return

    var peak_target := int(model.call("target_vehicle_count", 12, 17.0, arterial_roads, Vector3.ZERO))
    var night_target := int(model.call("target_vehicle_count", 12, 2.0, arterial_roads, Vector3.ZERO))
    if peak_target <= night_target:
        _fail("peak target must exceed night target: %d <= %d" % [peak_target, night_target])
        return
    if peak_target > 12 or night_target < 1:
        _fail("density target escaped configured bounds")
        return

    var anchors: Array = [
        {"id": "midi", "x": -100.0, "z": 0.0},
        {"id": "bourse", "x": 100.0, "z": 0.0},
    ]
    if str(model.call("nearest_sector", anchors, Vector3(-90.0, 0.0, 0.0))) != "midi":
        _fail("nearest corridor sector classification failed")
        return

    print("TRAFFIC_DENSITY_OK: time profile, OSM road-capacity factor and sector classification passed")
    quit(0)
