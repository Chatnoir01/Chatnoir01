extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("TRAFFIC_CONTROL_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var control_script: Script = load("res://game/scripts/traffic_control_system.gd")
    if control_script == null:
        _fail("traffic control system script did not load")
        return

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
        return
    if int(system.call("get_signal_count")) != 2:
        _fail("signal count mismatch")
        return
    if int(system.call("get_signal_cluster_count")) != 1:
        _fail("nearby signal heads should form one intersection cluster")
        return

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
        return

    var stop_found := false
    var signal_control: Dictionary = {}
    for control: Dictionary in mapped:
        if str(control.get("kind", "")) == "stop":
            stop_found = int(control.get("route_index", -1)) == 2
        if str(control.get("kind", "")) == "traffic_signals" and signal_control.is_empty():
            signal_control = control
    if not stop_found:
        _fail("STOP control did not map to the expected route waypoint")
        return
    if signal_control.is_empty():
        _fail("signal control missing from route mapping")
        return

    var east_west := Vector3(1.0, 0.0, 0.0)
    var north_south := Vector3(0.0, 0.0, 1.0)
    var ew_state := str(system.call("signal_state_for", signal_control, east_west, 10.0))
    var ns_state := str(system.call("signal_state_for", signal_control, north_south, 10.0))
    if ew_state != "green" or ns_state != "red":
        _fail("first signal phase is unsafe: EW=%s NS=%s" % [ew_state, ns_state])
        return

    ew_state = str(system.call("signal_state_for", signal_control, east_west, 40.0))
    ns_state = str(system.call("signal_state_for", signal_control, north_south, 40.0))
    if ew_state != "red" or ns_state != "green":
        _fail("second signal phase is unsafe: EW=%s NS=%s" % [ew_state, ns_state])
        return

    print("TRAFFIC_CONTROL_OK: clustering, mapping and safe alternating phases passed")
    quit(0)
