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
    manager.set("spawn_radius_m", 2000.0)
    manager.set("crossing_spawn_radius_m", 2000.0)
    manager.set("despawn_radius_m", 3000.0)
    manager.set("traffic_seed", 42)
    root.add_child(manager)

    await process_frame
    await physics_frame
    await physics_frame

    for method_name: String in [
        "get_route_count",
        "get_graph_node_count",
        "get_graph_edge_count",
        "get_intersection_count",
        "get_right_priority_count",
        "get_traffic_control_count",
        "get_signal_count",
        "get_crossing_count",
        "get_unsignalized_crossing_count",
        "get_active_crossing_pedestrian_count",
        "get_active_vehicle_count",
    ]:
        if not manager.has_method(method_name):
            _fail("traffic manager public API missing: %s" % method_name)
            return

    var route_count := int(manager.call("get_route_count"))
    if route_count < 100:
        _fail("too few eligible current OSM traffic routes: %d" % route_count)
        return

    var graph_nodes := int(manager.call("get_graph_node_count"))
    var graph_edges := int(manager.call("get_graph_edge_count"))
    var intersection_count := int(manager.call("get_intersection_count"))
    var right_priority_count := int(manager.call("get_right_priority_count"))
    if graph_nodes < 20:
        _fail("OSM road graph has too few nodes: %d" % graph_nodes)
        return
    if graph_edges <= route_count:
        _fail("road graph was not split into directed segments: %d edges / %d ways" % [graph_edges, route_count])
        return
    if intersection_count < 20:
        _fail("too few current OSM intersections detected: %d" % intersection_count)
        return
    if right_priority_count <= 0 or right_priority_count > intersection_count:
        _fail("invalid right-priority intersection count: %d/%d" % [right_priority_count, intersection_count])
        return

    var control_count := int(manager.call("get_traffic_control_count"))
    var signal_count := int(manager.call("get_signal_count"))
    var crossing_count := int(manager.call("get_crossing_count"))
    var unsignalized_crossing_count := int(manager.call("get_unsignalized_crossing_count"))
    if control_count < 100:
        _fail("current traffic-control pack did not load: %d controls" % control_count)
        return
    if signal_count < 10:
        _fail("too few current OSM traffic signals loaded: %d" % signal_count)
        return
    if crossing_count < 50:
        _fail("too few OSM crossings mapped to roads: %d" % crossing_count)
        return
    if unsignalized_crossing_count <= 0 or unsignalized_crossing_count > crossing_count:
        _fail("invalid unsignalized crossing count: %d/%d" % [unsignalized_crossing_count, crossing_count])
        return

    var active_count := int(manager.call("get_active_vehicle_count"))
    var active_pedestrians := int(manager.call("get_active_crossing_pedestrian_count"))
    if active_count != 4:
        _fail("expected 4 spawned traffic vehicles, got %d" % active_count)
        return
    if active_pedestrians != 3:
        _fail("expected 3 crossing pedestrians, got %d" % active_pedestrians)
        return

    var traffic_root := manager.get_node_or_null("TrafficVehicles")
    var pedestrian_root := manager.get_node_or_null("CrossingPedestrians")
    if traffic_root == null:
        _fail("TrafficVehicles root missing")
        return
    if pedestrian_root == null:
        _fail("CrossingPedestrians root missing")
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
        "get_speed_kmh",
        "get_speed_limit_kmh",
        "get_road_name",
        "get_source_osm_id",
        "get_route_point_count",
        "get_route_edge_count",
        "get_route_control_count",
        "get_route_intersection_count",
        "set_crossing_system",
    ]:
        if not first_vehicle.has_method(method_name):
            _fail("traffic vehicle API missing: %s" % method_name)
            return

    var speed_limit := float(first_vehicle.call("get_speed_limit_kmh"))
    if speed_limit < 5.0 or speed_limit > 90.0:
        _fail("invalid traffic speed limit: %.2f" % speed_limit)
        return
    if int(first_vehicle.call("get_route_point_count")) < 3:
        _fail("spawned vehicle route is too short")
        return
    if int(first_vehicle.call("get_route_edge_count")) < 2:
        _fail("spawned vehicle is still limited to one OSM segment")
        return
    if int(first_vehicle.call("get_source_osm_id")) <= 0:
        _fail("spawned vehicle lost OSM source id")
        return

    print(
        "TRAFFIC_SMOKE_OK: %d ways, %d nodes, %d edges, %d intersections (%d right-priority), %d controls, %d signals, %d crossings (%d unsignalized), %d vehicles, %d crossing pedestrians" %
        [
            route_count,
            graph_nodes,
            graph_edges,
            intersection_count,
            right_priority_count,
            control_count,
            signal_count,
            crossing_count,
            unsignalized_crossing_count,
            active_count,
            active_pedestrians,
        ]
    )
    manager.queue_free()
    await process_frame
    quit(0)
