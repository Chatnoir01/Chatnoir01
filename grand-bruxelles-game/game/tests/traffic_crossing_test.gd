extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("TRAFFIC_CROSSING_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var script: Script = load("res://game/scripts/traffic_crossing_system.gd")
    if script == null:
        _fail("crossing system script did not load")
        return

    var system: RefCounted = script.new()
    var roads: Array[Dictionary] = [
        {
            "osm_id": 1,
            "width": 6.0,
            "points": [[-20.0, 0.0], [20.0, 0.0]],
        },
    ]
    var controls: Array = [
        {"osm_id": 100, "kind": "crossing", "point": [0.0, 0.0], "crossing_signals": false},
        {"osm_id": 101, "kind": "crossing", "point": [10.0, 0.0], "crossing_signals": true},
    ]
    system.call("rebuild", roads, controls)

    if int(system.call("get_crossing_count")) != 2:
        _fail("expected two mapped crossings")
        return
    if int(system.call("get_unsignalized_crossing_count")) != 1:
        _fail("signalized crossing classification is wrong")
        return

    var crossing: Dictionary = system.call("get_crossing", 100)
    if crossing.is_empty():
        _fail("unsignalized crossing descriptor missing")
        return
    var road_direction: Vector3 = crossing.get("road_direction", Vector3.ZERO)
    var crossing_direction: Vector3 = crossing.get("crossing_direction", Vector3.ZERO)
    if absf(road_direction.dot(crossing_direction)) > 0.01:
        _fail("crossing path is not perpendicular to the road")
        return

    if bool(system.call("crossing_requires_stop", 100)):
        _fail("empty crossing should not stop traffic")
        return
    if not bool(system.call("register_waiting", 100, 501)):
        _fail("waiting pedestrian could not register")
        return
    if not bool(system.call("crossing_requires_stop", 100)):
        _fail("waiting pedestrian must stop traffic")
        return

    var waiting_state: Dictionary = system.call("get_crossing_state", 100)
    if int(waiting_state.get("waiting", 0)) != 1 or int(waiting_state.get("crossing", 0)) != 0:
        _fail("waiting state mismatch")
        return

    if not bool(system.call("begin_crossing", 100, 501)):
        _fail("pedestrian could not enter crossing")
        return
    var active_state: Dictionary = system.call("get_crossing_state", 100)
    if int(active_state.get("waiting", 0)) != 0 or int(active_state.get("crossing", 0)) != 1:
        _fail("active crossing state mismatch")
        return

    system.call("clear_pedestrian", 100, 501)
    if bool(system.call("crossing_requires_stop", 100)):
        _fail("traffic did not resume after pedestrian cleared")
        return

    var nearby: Array = system.call("get_crossings_near", Vector3.ZERO, 50.0, true)
    if nearby.size() != 1 or int((nearby[0] as Dictionary).get("id", 0)) != 100:
        _fail("unsignalized crossing filter mismatch")
        return

    print("TRAFFIC_CROSSING_OK: empty/free, waiting/stop, crossing/stop, clear/resume passed")
    quit(0)
