extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("TRAFFIC_CONTROL_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    if not _test_signals_and_route_controls():
        return
    if not _test_priority_to_right():
        return
    print("TRAFFIC_CONTROL_OK: signals, route controls and priority-to-right arbitration passed")
    quit(0)


func _test_signals_and_route_controls() -> bool:
    var control_script: Script = load("res://game/scripts/traffic_control_system.gd")
    if control_script == null:
        _fail("traffic control system script did not load")
        return false

    var system: RefCounted = control_script.new()
    var controls: Array = [
        {"osm_id": 1, "kind": "traffic_signals", "point": [10.0, 0.0]},
        {"osm_id": 2, "kind": "traffic_signals", "point": [10.0, 2.0]},
        {"osm_id": 3, "kind": "stop", "point": [20.0, 0.0]},
        {"osm_id": 4, "kind": "crossing", "point": [30.0, 0.0]},
    ]
    system.call("rebuild", controls)

    if int(system.call("get_control_count")) != 4:
        _fail("control count mismatch")
        return false
    if int(system.call("get_signal_count")) != 2:
        _fail("signal count mismatch")
        return false
    if int(system.call("get_signal_cluster_count")) != 1:
        _fail("nearby signal heads should form one intersection cluster")
        return false

    var route := PackedVector3Array([
        Vector3(0.0, 0.68, 0.0),
        Vector3(10.0, 0.68, 0.0),
        Vector3(20.0, 0.68, 0.0),
        Vector3(30.0, 0.68, 0.0),
        Vector3(40.0, 0.68, 0.0),
    ])
    var mapped: Array = system.call("controls_for_route", route)
    if mapped.size() != 4:
        _fail("expected 4 mapped route controls, got %d" % mapped.size())
        return false

    var stop_found := false
    var signal_control: Dictionary = {}
    for control: Dictionary in mapped:
        if str(control.get("kind", "")) == "stop":
            stop_found = int(control.get("route_index", -1)) == 2
        if str(control.get("kind", "")) == "traffic_signals" and signal_control.is_empty():
            signal_control = control
    if not stop_found:
        _fail("STOP control did not map to the expected route waypoint")
        return false
    if signal_control.is_empty():
        _fail("signal control missing from route mapping")
        return false

    var east_west := Vector3(1.0, 0.0, 0.0)
    var north_south := Vector3(0.0, 0.0, 1.0)
    var ew_state := str(system.call("signal_state_for", signal_control, east_west, 10.0))
    var ns_state := str(system.call("signal_state_for", signal_control, north_south, 10.0))
    if ew_state != "green" or ns_state != "red":
        _fail("first signal phase is unsafe: EW=%s NS=%s" % [ew_state, ns_state])
        return false

    ew_state = str(system.call("signal_state_for", signal_control, east_west, 40.0))
    ns_state = str(system.call("signal_state_for", signal_control, north_south, 40.0))
    if ew_state != "red" or ns_state != "green":
        _fail("second signal phase is unsafe: EW=%s NS=%s" % [ew_state, ns_state])
        return false
    return true


func _test_priority_to_right() -> bool:
    var intersection_script: Script = load("res://game/scripts/traffic_intersection_system.gd")
    if intersection_script == null:
        _fail("traffic intersection system script did not load")
        return false

    var system: RefCounted = intersection_script.new()
    var roads: Array[Dictionary] = [
        {
            "osm_id": 101,
            "points": [[-10.0, 0.0], [0.0, 0.0], [10.0, 0.0]],
        },
        {
            "osm_id": 102,
            "points": [[0.0, 10.0], [0.0, 0.0], [0.0, -10.0]],
        },
    ]
    system.call("rebuild", roads, [])
    if int(system.call("get_intersection_count")) != 1:
        _fail("synthetic four-way intersection was not detected")
        return false
    if int(system.call("get_right_priority_count")) != 1:
        _fail("unsigned synthetic intersection should use priority-to-right")
        return false

    var south_to_north := Vector3(0.0, 0.0, -1.0)
    var east_to_west := Vector3(-1.0, 0.0, 0.0)

    var a_initial := bool(system.call("request_passage", 0, 1001, south_to_north, 8.0, 10.0))
    if not a_initial:
        _fail("first isolated approach should initially be allowed")
        return false

    var b_allowed := bool(system.call("request_passage", 0, 1002, east_to_west, 7.0, 10.1))
    if not b_allowed:
        _fail("vehicle arriving from the right should be allowed")
        return false

    var a_after_right := bool(system.call("request_passage", 0, 1001, south_to_north, 7.0, 10.2))
    if a_after_right:
        _fail("vehicle failed to yield to traffic approaching from its right")
        return false

    var b_reserved := bool(system.call("request_passage", 0, 1002, east_to_west, 3.0, 10.25))
    if not b_reserved:
        _fail("priority vehicle could not reserve the intersection")
        return false

    var a_during_reservation := bool(system.call("request_passage", 0, 1001, south_to_north, 2.8, 10.3))
    if a_during_reservation:
        _fail("second vehicle entered while intersection was reserved")
        return false

    system.call("release_vehicle", 1002)
    var a_after_release := bool(system.call("request_passage", 0, 1001, south_to_north, 2.8, 10.4))
    if not a_after_release:
        _fail("yielding vehicle did not proceed after priority vehicle cleared")
        return false

    var signaled: RefCounted = intersection_script.new()
    signaled.call("rebuild", roads, [{"osm_id": 9, "kind": "traffic_signals", "point": [0.0, 0.0]}])
    if int(signaled.call("get_right_priority_count")) != 0:
        _fail("signal-controlled intersection must not also use priority-to-right")
        return false
    return true
