extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("TRAFFIC_CANONICAL_MANAGER_FAIL: %s" % message)
    quit(1)

func _road(points: Array, osm_id: int, road_class: String = "residential", oneway: Variant = 0, width: float = 6.0, lanes: int = 2) -> Dictionary:
    return {
        "points": points,
        "osm_id": osm_id,
        "class": road_class,
        "drivable": true,
        "oneway": oneway,
        "width": width,
        "lanes": lanes,
        "name": "Canonical %d" % osm_id,
        "maxspeed_kmh": 30.0,
        "parking_evidence": {
            "runtime_approved": true,
            "source": "synthetic_test_fixture",
        },
    }

func _run() -> void:
    var manager := TrafficManagerCore.new()
    manager.auto_load_data = false
    manager.auto_spawn_runtime = false
    manager.max_vehicles = 12
    manager.max_parked_vehicles = 0
    manager.max_delivery_vehicles = 1
    manager.max_crossing_pedestrians = 1
    manager.delivery_spawn_radius_m = 100000.0
    manager.crossing_spawn_radius_m = 100000.0
    manager.min_route_length_m = 10.0
    manager.route_target_length_m = 55.0
    manager.route_max_length_m = 180.0
    manager.max_route_edges = 10
    get_root().add_child(manager)
    await process_frame

    var roads: Array = [
        _road([[-60.0, 0.0], [0.0, 0.0], [60.0, 0.0]], 3001),
        _road([[0.0, -60.0], [0.0, 0.0], [0.0, 60.0]], 3002),
        _road([[60.0, 0.0], [100.0, 0.0], [140.0, 0.0]], 3003, "secondary", 0, 7.0, 2),
        _road([[0.0, 80.0], [80.0, 80.0]], 3004, "service", 0, 6.0, 2),
    ]
    var controls: Array = [
        {"kind": "traffic_signals", "osm_id": 4001, "point": [0.0, 0.0]},
        {"kind": "crossing", "osm_id": 4002, "point": [40.0, 80.0], "crossing_signals": false},
    ]
    manager.configure_test_data(roads, controls, [{"id": "test", "x": 0.0, "z": 0.0}])

    var contract := TrafficRuntimeContract.new()
    var missing: PackedStringArray = contract.validate_manager(manager)
    if not missing.is_empty():
        _fail("manager contract incomplete: %s" % [missing])
        return
    if manager.has_method("process_tow_services_at"):
        _fail("v9 tow extension leaked into canonical v8 parity core")
        return

    for root_name: String in contract.REQUIRED_MANAGER_ROOTS:
        if manager.get_node_or_null(root_name) == null:
            _fail("missing runtime root %s" % root_name)
            return

    if manager.get_route_count() != 4:
        _fail("test roads were not accepted")
        return
    if manager.get_graph_node_count() < 8 or manager.get_graph_edge_count() < 12:
        _fail("canonical road graph did not rebuild")
        return
    if manager.get_intersection_count() < 1 or manager.get_traffic_control_count() != 2:
        _fail("intersection/control systems did not rebuild")
        return
    if manager.get_crossing_count() != 1 or manager.get_unsignalized_crossing_count() != 1:
        _fail("crossing system parity failed")
        return
    if manager.get_parking_candidate_count() <= 0:
        _fail("source-approved parking candidates were not derived")
        return

    manager.set_simulation_hour(3.0)
    var night_target: int = manager.get_density_target_vehicle_count()
    manager.set_simulation_hour(17.0)
    var evening_target: int = manager.get_density_target_vehicle_count()
    if evening_target != night_target:
        _fail("unsourced time-of-day shaping changed canonical manager density target")
        return

    manager.auto_spawn_runtime = true
    manager.max_vehicles = 1
    if not bool(manager.call("_spawn_one_vehicle")):
        _fail("canonical manager could not spawn a routed canonical vehicle")
        return
    await process_frame
    if manager.get_active_vehicle_count() != 1:
        _fail("spawned traffic vehicle was not tracked")
        return
    var traffic_root := manager.get_node("TrafficVehicles")
    var vehicle := traffic_root.get_child(0) as TrafficVehicleCore
    if vehicle == null:
        _fail("spawned vehicle is not the canonical TrafficVehicleCore")
        return
    if vehicle.get_route_point_count() < 3 or vehicle.get_source_osm_id() <= 0:
        _fail("canonical manager did not preserve route/provenance metadata")
        return

    manager.call("_replenish_crossing_pedestrians")
    if manager.get_active_crossing_pedestrian_count() != 1:
        _fail("canonical crossing pedestrian was not spawned")
        return

    manager.call("_replenish_deliveries")
    if manager.get_delivery_vehicle_count() != 1 or manager.get_reserved_parking_candidate_count() != 1:
        _fail("delivery did not reserve a source-approved parking candidate")
        return
    manager.expire_deliveries_at(1.0e12)
    if manager.get_delivery_vehicle_count() != 0 or manager.get_reserved_parking_candidate_count() != 0:
        _fail("delivery expiry did not release curb reservation")
        return

    for _impact: int in range(5):
        vehicle.apply_traffic_test_impact(120.0, 1.0)
    if manager.get_wreck_count() != 1:
        _fail("disabled vehicle was not promoted to managed wreck")
        return
    vehicle.set_meta("traffic_wrecked_at_s", 0.0)
    vehicle.set_meta("traffic_wreck_clear_after_s", 0.0)
    if manager.cleanup_wrecks_at(100.0) != 1:
        _fail("wreck cleanup did not clear expired wreck")
        return
    if manager.get_wreck_count() != 0:
        _fail("cleared wreck still counted")
        return

    manager.queue_free()
    print("TRAFFIC_CANONICAL_MANAGER_OK: v8 parity contract, roots, spawn, neutral unsourced temporal density, crossing, source-gated delivery and wreck lifecycle")
    quit(0)
