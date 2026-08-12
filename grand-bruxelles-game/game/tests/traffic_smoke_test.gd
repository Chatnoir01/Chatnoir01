extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("TRAFFIC_SMOKE_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var manager_script: Script = load("res://game/scripts/traffic_manager.gd")
    if manager_script == null:
        _fail("traffic manager script did not load")
        return

    var manager := Node3D.new()
    manager.name = "TrafficManagerTest"
    manager.set_script(manager_script)
    manager.set("max_vehicles", 4)
    manager.set("density_enabled", false)
    manager.set("max_crossing_pedestrians", 3)
    manager.set("max_parked_vehicles", 4)
    manager.set("max_delivery_vehicles", 2)
    manager.set("spawn_radius_m", 2000.0)
    manager.set("crossing_spawn_radius_m", 2000.0)
    manager.set("parking_spawn_radius_m", 2000.0)
    manager.set("delivery_spawn_radius_m", 2000.0)
    manager.set("despawn_radius_m", 3000.0)
    manager.set("traffic_seed", 42)
    root.add_child(manager)

    await process_frame
    await physics_frame
    await physics_frame

    for method_name: String in [
        "get_route_count", "get_graph_node_count", "get_graph_edge_count",
        "get_intersection_count", "get_right_priority_count",
        "get_traffic_control_count", "get_signal_count", "get_crossing_count",
        "get_unsignalized_crossing_count", "get_active_crossing_pedestrian_count",
        "get_parking_candidate_count", "get_parked_vehicle_count",
        "get_delivery_vehicle_count", "get_reserved_parking_candidate_count",
        "get_active_vehicle_count",
    ]:
        if not manager.has_method(method_name):
            _fail("traffic manager public API missing: %s" % method_name)
            return

    var route_count := int(manager.call("get_route_count"))
    var graph_nodes := int(manager.call("get_graph_node_count"))
    var graph_edges := int(manager.call("get_graph_edge_count"))
    var intersection_count := int(manager.call("get_intersection_count"))
    var right_priority_count := int(manager.call("get_right_priority_count"))
    var control_count := int(manager.call("get_traffic_control_count"))
    var signal_count := int(manager.call("get_signal_count"))
    var crossing_count := int(manager.call("get_crossing_count"))
    var unsignalized_crossing_count := int(manager.call("get_unsignalized_crossing_count"))
    var active_count := int(manager.call("get_active_vehicle_count"))
    var active_pedestrians := int(manager.call("get_active_crossing_pedestrian_count"))
    var parking_candidates := int(manager.call("get_parking_candidate_count"))
    var parked_count := int(manager.call("get_parked_vehicle_count"))
    var delivery_count := int(manager.call("get_delivery_vehicle_count"))
    var reserved_count := int(manager.call("get_reserved_parking_candidate_count"))

    if route_count < 100 or graph_nodes < 20 or graph_edges <= route_count:
        _fail("current OSM road graph is incomplete")
        return
    if intersection_count < 20 or right_priority_count <= 0 or right_priority_count > intersection_count:
        _fail("current intersection arbitration counts are invalid")
        return
    if control_count < 100 or signal_count < 10:
        _fail("current OSM traffic-control pack is incomplete")
        return
    if crossing_count < 50 or unsignalized_crossing_count <= 0 or unsignalized_crossing_count > crossing_count:
        _fail("current crossing mapping counts are invalid")
        return
    if active_count != 4 or active_pedestrians != 3:
        _fail("moving traffic or crossing pedestrian counts mismatch")
        return
    if parking_candidates <= 0 or parked_count != 4:
        _fail("parking simulation counts mismatch")
        return
    if delivery_count != 2 or reserved_count != delivery_count:
        _fail("delivery/reserved curb counts mismatch: %d/%d" % [delivery_count, reserved_count])
        return

    var traffic_root := manager.get_node_or_null("TrafficVehicles")
    var pedestrian_root := manager.get_node_or_null("CrossingPedestrians")
    var parking_root := manager.get_node_or_null("ParkedVehicles")
    var delivery_root := manager.get_node_or_null("DeliveryVehicles")
    if traffic_root == null or pedestrian_root == null or parking_root == null or delivery_root == null:
        _fail("one or more traffic runtime roots are missing")
        return

    var parked_ids := {}
    for parked: Node in parking_root.get_children():
        if not bool(parked.get_meta("simulated_occupancy", false)):
            _fail("parked vehicle is not explicitly labelled simulated occupancy")
            return
        parked_ids[int(parked.get_meta("parking_candidate_id", -1))] = true

    for delivery: Node in delivery_root.get_children():
        if not bool(delivery.get_meta("simulated_delivery", false)):
            _fail("delivery vehicle is not explicitly labelled simulated")
            return
        var candidate_id := int(delivery.get_meta("parking_candidate_id", -1))
        if parked_ids.has(candidate_id):
            _fail("delivery and parked car overlap on the same curb candidate")
            return

    var first_vehicle: Node = null
    for child: Node in traffic_root.get_children():
        if not child.is_queued_for_deletion():
            first_vehicle = child
            break
    if first_vehicle == null:
        _fail("no traffic vehicle available for inspection")
        return

    for method_name: String in [
        "get_speed_kmh", "get_speed_limit_kmh", "get_road_name", "get_source_osm_id",
        "get_route_point_count", "get_route_edge_count", "get_route_control_count",
        "get_route_intersection_count", "set_crossing_system",
    ]:
        if not first_vehicle.has_method(method_name):
            _fail("traffic vehicle API missing: %s" % method_name)
            return

    var speed_limit := float(first_vehicle.call("get_speed_limit_kmh"))
    if speed_limit < 5.0 or speed_limit > 90.0:
        _fail("invalid traffic speed limit: %.2f" % speed_limit)
        return
    if int(first_vehicle.call("get_route_point_count")) < 3 or int(first_vehicle.call("get_route_edge_count")) < 2:
        _fail("spawned traffic route is too short")
        return
    if int(first_vehicle.call("get_source_osm_id")) <= 0:
        _fail("spawned vehicle lost OSM source id")
        return

    print(
        "TRAFFIC_SMOKE_OK: %d ways, %d nodes, %d edges, %d intersections (%d right-priority), %d controls, %d signals, %d crossings (%d unsignalized), %d moving, %d pedestrians, %d/%d parked/candidates, %d deliveries" %
        [route_count, graph_nodes, graph_edges, intersection_count, right_priority_count,
        control_count, signal_count, crossing_count, unsignalized_crossing_count,
        active_count, active_pedestrians, parked_count, parking_candidates, delivery_count]
    )
    manager.queue_free()
    await process_frame
    quit(0)
