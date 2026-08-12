extends SceneTree

const MANAGER_PATH := "res://game/scripts/traffic_manager_core.gd"
const VEHICLE_PATH := "res://game/scripts/traffic_vehicle_core.gd"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("TRAFFIC_CANONICAL_RUNTIME_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    if not ResourceLoader.exists(MANAGER_PATH):
        _fail("canonical manager is missing: %s" % MANAGER_PATH)
        return
    if not ResourceLoader.exists(VEHICLE_PATH):
        _fail("canonical vehicle core is missing: %s" % VEHICLE_PATH)
        return

    var contract_script: Script = load("res://game/scripts/traffic_runtime_contract.gd")
    if contract_script == null:
        _fail("traffic runtime contract did not load")
        return
    var contract: TrafficRuntimeContract = contract_script.new()

    var manager_script: Script = load(MANAGER_PATH)
    var vehicle_script: Script = load(VEHICLE_PATH)
    if manager_script == null or vehicle_script == null:
        _fail("canonical scripts failed to load")
        return

    var manager := Node.new()
    manager.set_script(manager_script)
    var vehicle := CharacterBody3D.new()
    vehicle.set_script(vehicle_script)

    var manager_missing: PackedStringArray = contract.validate_manager(manager)
    var vehicle_missing: PackedStringArray = contract.validate_vehicle(vehicle)
    if not manager_missing.is_empty():
        _fail("canonical manager missing methods: %s" % ", ".join(manager_missing))
        return
    if not vehicle_missing.is_empty():
        _fail("canonical vehicle missing methods: %s" % ", ".join(vehicle_missing))
        return

    var manager_source := FileAccess.get_file_as_string(MANAGER_PATH)
    var vehicle_source := FileAccess.get_file_as_string(VEHICLE_PATH)
    if manager_source.find("_core_v") >= 0 or vehicle_source.find("_core_v") >= 0:
        _fail("canonical runtime source depends on a version-suffixed legacy core")
        return

    root.add_child(manager)
    await process_frame
    for root_name: String in contract.REQUIRED_MANAGER_ROOTS:
        if manager.get_node_or_null(root_name) == null:
            _fail("canonical manager missing runtime root: %s" % root_name)
            return

    manager.call("configure_runtime_snapshot", {
        "route_count": 140,
        "graph_node_count": 588,
        "graph_edge_count": 708,
        "intersection_count": 63,
        "right_priority_count": 53,
        "traffic_control_count": 180,
        "signal_count": 19,
        "crossing_count": 124,
        "unsignalized_crossing_count": 108,
        "parking_candidate_count": 188,
    })
    if int(manager.call("get_route_count")) != 140 or int(manager.call("get_graph_node_count")) != 588:
        _fail("canonical manager did not retain graph snapshot")
        return
    if int(manager.call("get_right_priority_count")) != 53 or int(manager.call("get_signal_count")) != 19:
        _fail("canonical manager did not retain control snapshot")
        return
    if int(manager.call("get_crossing_count")) != 124 or int(manager.call("get_parking_candidate_count")) != 188:
        _fail("canonical manager did not retain crossing/parking snapshot")
        return

    if not bool(manager.call("reserve_parking_candidate", 42, "delivery:test")):
        _fail("canonical parking reservation failed")
        return
    if bool(manager.call("reserve_parking_candidate", 42, "other")):
        _fail("canonical parking reservation allowed conflicting owner")
        return
    if int(manager.call("get_reserved_parking_candidate_count")) != 1:
        _fail("canonical parking reservation count mismatch")
        return
    if not bool(manager.call("release_parking_candidate", 42, "delivery:test")):
        _fail("canonical parking reservation did not release")
        return

    var traffic_root := manager.get_node("TrafficVehicles")
    var moving := Node3D.new()
    traffic_root.add_child(moving)
    var wreck := Node3D.new()
    wreck.set_meta("traffic_wrecked", true)
    wreck.set_meta("traffic_wrecked_at_s", 10.0)
    wreck.set_meta("traffic_wreck_clear_after_s", 5.0)
    traffic_root.add_child(wreck)
    if int(manager.call("get_active_vehicle_count")) != 1 or int(manager.call("get_wreck_count")) != 1:
        _fail("canonical manager moving/wreck classification mismatch")
        return
    if int(manager.call("cleanup_wrecks_at", 14.9)) != 0:
        _fail("canonical manager cleared wreck before deadline")
        return
    if int(manager.call("cleanup_wrecks_at", 15.0)) != 1:
        _fail("canonical manager did not clear wreck at deadline")
        return

    var route := PackedVector3Array([Vector3.ZERO, Vector3(0.0, 0.0, -12.0), Vector3(4.0, 0.0, -20.0)])
    var limits := PackedFloat32Array([30.0, 30.0, 20.0])
    var controls: Array = [{"kind": "crossing", "osm_id": 100}]
    var intersections: Array = [{"id": 7, "priority_to_right": true}]
    vehicle.call("configure_route_profile", route, limits, "Rue de Test", 987654, 2, controls, intersections)
    if int(vehicle.call("get_route_point_count")) != 3 or int(vehicle.call("get_route_edge_count")) != 2:
        _fail("canonical vehicle route metrics mismatch")
        return
    if int(vehicle.call("get_route_control_count")) != 1 or int(vehicle.call("get_route_intersection_count")) != 1:
        _fail("canonical vehicle route metadata mismatch")
        return
    if str(vehicle.call("get_road_name")) != "Rue de Test" or int(vehicle.call("get_source_osm_id")) != 987654:
        _fail("canonical vehicle road provenance mismatch")
        return
    vehicle.call("set_test_speed_kmh", 18.0)
    if absf(float(vehicle.call("get_speed_kmh")) - 18.0) > 0.01:
        _fail("canonical vehicle speed telemetry mismatch")
        return
    var crossing_system := RefCounted.new()
    vehicle.call("set_crossing_system", crossing_system)

    vehicle.free()
    manager.queue_free()
    print("TRAFFIC_CANONICAL_RUNTIME_OK: flattened manager/vehicle pass roots, snapshot, reservation, wreck lifecycle and route telemetry")
    quit(0)
