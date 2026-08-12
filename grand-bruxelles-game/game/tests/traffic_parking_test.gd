extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("TRAFFIC_PARKING_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var script: Script = load("res://game/scripts/traffic_parking_model.gd")
    if script == null:
        _fail("parking model script did not load")
        return

    var model: RefCounted = script.new()
    var roads: Array[Dictionary] = [
        {
            "osm_id": 1,
            "class": "residential",
            "width": 6.0,
            "name": "Rue test",
            "points": [[0.0, 0.0], [100.0, 0.0]],
        },
        {
            "osm_id": 2,
            "class": "primary",
            "width": 10.0,
            "points": [[0.0, 20.0], [100.0, 20.0]],
        },
    ]
    var controls: Array = [
        {"osm_id": 100, "kind": "crossing", "point": [50.0, 0.0]},
    ]

    var candidates: Array = model.call("build_candidates", roads, controls)
    if candidates.size() < 2:
        _fail("residential road produced too few curb candidates")
        return

    for candidate: Dictionary in candidates:
        if int(candidate.get("osm_id", 0)) != 1:
            _fail("primary road unexpectedly produced simulated curb parking")
            return
        if not bool(candidate.get("simulated_occupancy", false)):
            _fail("parking occupancy is not explicitly marked simulated")
            return
        var road_point: Vector3 = candidate.get("road_point", Vector3.ZERO)
        var parked_position: Vector3 = candidate.get("position", Vector3.ZERO)
        if road_point.distance_to(Vector3(50.0, 0.68, 0.0)) < 12.0:
            _fail("parking candidate blocks pedestrian crossing clearance")
            return
        if parked_position.distance_to(road_point) < 4.0:
            _fail("parked vehicle center is too close to road centerline")
            return
        if road_point.x < 7.9 or road_point.x > 92.1:
            _fail("parking candidate violated segment-end clearance")
            return

    var nearby: Array = model.call("candidates_near", candidates, Vector3(10.0, 0.68, 0.0), 20.0)
    if nearby.is_empty():
        _fail("nearby parking candidate lookup failed")
        return

    print("TRAFFIC_PARKING_OK: class filter, curb offset, crossing clearance and endpoint clearance passed; candidates=%d" % candidates.size())
    quit(0)
