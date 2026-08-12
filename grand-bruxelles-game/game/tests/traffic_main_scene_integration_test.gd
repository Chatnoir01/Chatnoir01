extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("TRAFFIC_MAIN_SCENE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var scene_resource: PackedScene = load("res://game/main.tscn") as PackedScene
    if scene_resource == null:
        _fail("main scene did not load")
        return
    var main: Node = scene_resource.instantiate()
    get_root().add_child(main)
    for _frame: int in range(8):
        await process_frame

    var manager := main.get_node_or_null("TrafficManager") as TrafficManagerTowExtension
    if manager == null:
        _fail("main scene is not wired to TrafficManagerTowExtension")
        return

    var contract := TrafficRuntimeContract.new()
    var missing: PackedStringArray = contract.validate_manager(manager, true)
    if not missing.is_empty():
        _fail("wired traffic manager does not satisfy canonical+tow contract: %s" % [missing])
        return

    if manager.get_route_count() <= 0:
        _fail("wired manager did not load fallback OSM routes")
        return
    if manager.get_graph_node_count() <= 0 or manager.get_graph_edge_count() <= 0:
        _fail("wired manager did not build a usable road graph")
        return
    if manager.get_active_vehicle_count() <= 0:
        _fail("wired manager did not spawn any canonical traffic vehicle")
        return

    var counts: Dictionary = manager.get_active_archetype_counts()
    var archetype_total := int(counts.get("car", 0)) + int(counts.get("scooter", 0)) + int(counts.get("motorcycle", 0))
    if archetype_total != manager.get_active_vehicle_count():
        _fail("spawned traffic contains a non-canonical vehicle archetype")
        return

    var traffic_root := manager.get_node_or_null("TrafficVehicles")
    if traffic_root == null or traffic_root.get_child_count() <= 0:
        _fail("TrafficVehicles root is empty after scene startup")
        return
    var first_vehicle := traffic_root.get_child(0) as TrafficVehicleCore
    if first_vehicle == null:
        _fail("main scene spawned a vehicle outside the canonical TrafficVehicleCore")
        return
    if first_vehicle.get_route_point_count() < 2 or first_vehicle.get_source_osm_id() <= 0:
        _fail("spawned vehicle lacks route/source provenance")
        return

    print("TRAFFIC_MAIN_SCENE_OK: %d routes, %d graph edges, %d active canonical vehicles" % [manager.get_route_count(), manager.get_graph_edge_count(), manager.get_active_vehicle_count()])
    main.queue_free()
    quit(0)
