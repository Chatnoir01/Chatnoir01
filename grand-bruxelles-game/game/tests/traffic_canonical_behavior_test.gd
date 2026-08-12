extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("TRAFFIC_CANONICAL_BEHAVIOR_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var manager_script: Script = load("res://game/scripts/traffic_manager_core.gd")
    if manager_script == null:
        _fail("manager script missing")
        return
    var manager: Node3D = manager_script.new()
    get_root().add_child(manager)
    await process_frame

    for root_name in ["TrafficVehicles", "CrossingPedestrians", "ParkedVehicles", "DeliveryVehicles", "TowServices"]:
        if manager.get_node_or_null(root_name) == null:
            _fail("missing runtime root %s" % root_name)
            return

    if not bool(manager.call("initialize_runtime")):
        _fail("real OSM runtime initialization failed")
        return
    if int(manager.call("get_route_count")) != 140:
        _fail("expected 140 real drivable OSM routes")
        return
    if int(manager.call("get_graph_node_count")) <= 0 or int(manager.call("get_graph_edge_count")) <= 0:
        _fail("OSM graph is empty")
        return
    if int(manager.call("get_intersection_count")) <= 0:
        _fail("OSM intersections were not reconstructed")
        return

    var candidates: Array = manager.call("get_candidate_edge_ids", Vector3(-668.5, 0.0, 627.84), 520.0)
    if candidates.is_empty():
        _fail("no route edge found near Midi anchor")
        return
    var route: Dictionary = manager.call("build_random_route", int(candidates[0]), 20260812, 120.0, 420.0, 18)
    var points: PackedVector3Array = route.get("points", PackedVector3Array())
    if points.size() < 3 or int(route.get("edge_count", 0)) < 2:
        _fail("canonical graph did not produce a multi-edge route")
        return

    manager.call("configure_topology", 140, manager.call("get_graph_node_count"), manager.call("get_graph_edge_count"), manager.call("get_intersection_count"), 53, manager.call("get_traffic_control_count"), manager.call("get_signal_count"), manager.call("get_crossing_count"), manager.call("get_unsignalized_crossing_count"), 188)
    if int(manager.call("get_parking_candidate_count")) != 188:
        _fail("parking candidate count mismatch")
        return

    if not bool(manager.call("reserve_parking_candidate", 7, "delivery:test")):
        _fail("first parking reservation rejected")
        return
    if bool(manager.call("reserve_parking_candidate", 7, "other")):
        _fail("duplicate parking reservation accepted")
        return
    manager.call("release_parking_candidate", 7, "delivery:test")
    if int(manager.call("get_reserved_parking_candidate_count")) != 0:
        _fail("reservation did not release")
        return

    var traffic_root: Node3D = manager.get_node("TrafficVehicles") as Node3D
    var wreck := CharacterBody3D.new()
    wreck.name = "CanonicalWreck"
    traffic_root.add_child(wreck)
    if not bool(manager.call("register_wreck", wreck, 100.0)):
        _fail("wreck registration failed")
        return
    if int(manager.call("get_wreck_count")) != 1 or int(manager.call("get_active_vehicle_count")) != 0:
        _fail("wreck lifecycle count mismatch")
        return
    if int(manager.call("cleanup_wrecks_at", 100.5)) != 0:
        _fail("wreck cleared before delay")
        return
    if int(manager.call("cleanup_wrecks_at", 200.0)) != 1:
        _fail("wreck did not clear after delay")
        return
    await process_frame
    if int(manager.call("get_wreck_count")) != 0:
        _fail("wreck remained after queued deletion")
        return

    manager.queue_free()
    print("TRAFFIC_CANONICAL_BEHAVIOR_OK: real OSM graph, multi-edge route, roots, parking and wreck lifecycle passed")
    quit(0)
