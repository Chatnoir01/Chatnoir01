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
    manager.set("spawn_radius_m", 2000.0)
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
        "get_active_vehicle_count",
    ]:
        if not manager.has_method(method_name):
            _fail("traffic manager public API missing: %s" % method_name)
            return

    var route_count := int(manager.call("get_route_count"))
    if route_count < 10:
        _fail("too few eligible OSM traffic routes: %d" % route_count)
        return

    var graph_nodes := int(manager.call("get_graph_node_count"))
    var graph_edges := int(manager.call("get_graph_edge_count"))
    if graph_nodes < 20:
        _fail("OSM road graph has too few nodes: %d" % graph_nodes)
        return
    if graph_edges <= route_count:
        _fail("road graph was not split into directed segments: %d edges / %d ways" % [graph_edges, route_count])
        return

    var active_count := int(manager.call("get_active_vehicle_count"))
    if active_count != 4:
        _fail("expected 4 spawned traffic vehicles, got %d" % active_count)
        return

    var traffic_root := manager.get_node_or_null("TrafficVehicles")
    if traffic_root == null:
        _fail("TrafficVehicles root missing")
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
        "TRAFFIC_SMOKE_OK: %d OSM ways, %d graph nodes, %d directed edges, %d active vehicles" %
        [route_count, graph_nodes, graph_edges, active_count]
    )
    manager.queue_free()
    await process_frame
    quit(0)
