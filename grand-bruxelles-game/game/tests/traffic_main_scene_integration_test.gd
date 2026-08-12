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

    var manager := main.get_node_or_null("TrafficManager") as TrafficManagerOfficialDensityExtension
    if manager == null:
        _fail("main scene is not wired to TrafficManagerOfficialDensityExtension")
        return

    var contract := TrafficRuntimeContract.new()
    var missing: PackedStringArray = contract.validate_manager(manager, true)
    if not missing.is_empty():
        _fail("wired traffic manager does not satisfy canonical+tow contract: %s" % [missing])
        return

    if not manager.is_official_density_loaded():
        _fail("wired manager did not load the committed Brussels Mobility density snapshot")
        return
    if manager.get_official_density_sensor_count() < 5:
        _fail("wired manager exposes fewer than five source-backed density sensors")
        return
    if manager.get_official_density_capture_timestamp().is_empty():
        _fail("official density capture timestamp provenance is missing")
        return

    var nearest_any_distance := manager.get_official_density_nearest_any_distance_m()
    var nearest_any_id := manager.get_official_density_nearest_any_sensor_id()
    if not is_finite(nearest_any_distance) or nearest_any_id.is_empty():
        _fail("nearest official fresh density sensor diagnostic is unavailable")
        return
    if not manager.is_official_density_available_here():
        _fail(
            "Bruxelles-Midi player anchor is outside official density calibration coverage: nearest fresh sensor %s at %.1fm, configured radius %.1fm" %
            [nearest_any_id, nearest_any_distance, manager.official_density_radius_m]
        )
        return
    if manager.get_official_density_sample_count() <= 0:
        _fail("official density calibration has no local source samples at Bruxelles-Midi")
        return
    if manager.get_official_density_nearest_distance_m() > manager.official_density_radius_m:
        _fail("nearest official density source lies outside the configured coverage radius")
        return
    var official_factor := manager.get_official_density_factor()
    if official_factor < 0.58 or official_factor > 1.48:
        _fail("official density factor escaped its conservative calibration bounds")
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

    print(
        "TRAFFIC_MAIN_SCENE_OK: %d routes, %d graph edges, %d vehicles, official factor %.3f from %d local sensors (nearest %.1fm, nearest-any %s %.1fm)" %
        [
            manager.get_route_count(),
            manager.get_graph_edge_count(),
            manager.get_active_vehicle_count(),
            official_factor,
            manager.get_official_density_sample_count(),
            manager.get_official_density_nearest_distance_m(),
            nearest_any_id,
            nearest_any_distance,
        ]
    )
    main.queue_free()
    quit(0)
