extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("TRAFFIC_CANONICAL_VEHICLE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var contract := TrafficRuntimeContract.new()
    var vehicle := TrafficVehicleCore.new()
    get_root().add_child(vehicle)
    await process_frame

    var missing: PackedStringArray = contract.validate_vehicle(vehicle)
    if not missing.is_empty():
        _fail("canonical vehicle misses contract methods: %s" % [missing])
        return

    vehicle.configure_archetype("scooter")
    if vehicle.get_traffic_archetype() != "scooter":
        _fail("scooter archetype was not applied")
        return
    if absf(vehicle.speed_factor - 0.88) > 0.001:
        _fail("scooter speed factor drifted")
        return

    var route := PackedVector3Array([Vector3.ZERO, Vector3(0.0, 0.0, -20.0), Vector3(0.0, 0.0, -40.0)])
    var limits := PackedFloat32Array([30.0, 30.0, 30.0])
    vehicle.configure_route_profile(route, limits, "Canonical test road", 123456, 2)
    if vehicle.get_route_point_count() != 3 or vehicle.get_route_edge_count() != 2:
        _fail("route metadata parity failed")
        return
    if vehicle.get_road_name() != "Canonical test road" or vehicle.get_source_osm_id() != 123456:
        _fail("road provenance metadata parity failed")
        return

    # A STOP requires a complete stop, but no source-backed rule in the runtime
    # justifies adding an arbitrary fixed dwell after that stop has been made.
    var stop_controls: Array = [{
        "kind": "stop",
        "osm_id": 9001,
        "route_index": 1,
        "route_position": Vector3.ZERO,
    }]
    vehicle.configure_route_profile(route, limits, "STOP evidence test", 123457, 2, stop_controls)
    vehicle.global_position = Vector3.ZERO
    vehicle.speed_mps = 0.40
    var first_stop_cap: float = float(vehicle.call("_traffic_control_speed_cap", 6.0))
    if not is_zero_approx(first_stop_cap):
        _fail("STOP did not require complete immobilization before being handled")
        return
    var immediate_release_cap: float = float(vehicle.call("_traffic_control_speed_cap", 6.0))
    if immediate_release_cap < 5.99:
        _fail("STOP introduced an unsourced fixed dwell after complete immobilization")
        return

    vehicle.set_crossing_system(RefCounted.new())

    for _impact: int in range(5):
        vehicle.apply_traffic_test_impact(120.0, 1.0)
    if not vehicle.is_traffic_disabled():
        _fail("damage lifecycle did not disable vehicle after repeated severe impacts")
        return
    if vehicle.get_traffic_vehicle_performance_factor() != 0.0:
        _fail("disabled vehicle still exposes non-zero performance")
        return
    if not bool(vehicle.get_meta("traffic_wrecked", false)):
        _fail("disabled canonical vehicle did not publish wreck metadata")
        return

    vehicle.queue_free()
    print("TRAFFIC_CANONICAL_VEHICLE_OK: contract, route metadata, evidence-gated STOP release, archetype and damage lifecycle")
    quit(0)
