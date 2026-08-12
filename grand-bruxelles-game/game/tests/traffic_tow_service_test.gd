extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("TRAFFIC_TOW_SERVICE_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var manager_script: Script = load("res://game/scripts/traffic_manager_core_v9.gd")
    if manager_script == null:
        _fail("tow-aware traffic manager core did not load")
        return

    var manager := Node3D.new()
    manager.name = "TowServiceTest"
    manager.set_script(manager_script)
    manager.set("max_vehicles", 0)
    manager.set("density_enabled", false)
    manager.set("max_crossing_pedestrians", 0)
    manager.set("max_parked_vehicles", 0)
    manager.set("max_delivery_vehicles", 0)
    manager.set("wreck_clear_delay_s", 18.0)
    manager.set("tow_arrival_delay_s", 7.0)
    manager.set("tow_service_duration_s", 5.0)
    root.add_child(manager)
    await process_frame

    for method_name: String in [
        "_create_vehicle_node",
        "get_wreck_count",
        "get_tow_service_count",
        "get_visible_tow_service_count",
        "process_tow_services_at",
    ]:
        if not manager.has_method(method_name):
            _fail("tow service API missing: %s" % method_name)
            return

    var traffic_root := manager.get_node_or_null("TrafficVehicles")
    var tow_root := manager.get_node_or_null("TowServices")
    if traffic_root == null or tow_root == null:
        _fail("traffic or tow runtime root missing")
        return

    var vehicle: CharacterBody3D = manager.call("_create_vehicle_node") as CharacterBody3D
    if vehicle == null:
        _fail("AI vehicle factory returned null")
        return
    traffic_root.add_child(vehicle)
    await process_frame

    for _index: int in range(10):
        vehicle.call("apply_traffic_test_impact", 75.0, 1.0)
        if bool(vehicle.call("is_traffic_disabled")):
            break

    if not bool(vehicle.call("is_traffic_disabled")):
        _fail("severe impacts did not create a wreck")
        return
    if int(manager.call("get_wreck_count")) != 1:
        _fail("wreck registration count mismatch")
        return
    if int(manager.call("get_tow_service_count")) != 1:
        _fail("wreck did not receive exactly one tow assignment")
        return
    if int(manager.call("get_visible_tow_service_count")) != 0:
        _fail("tow truck is visible before its arrival time")
        return

    var wrecked_at := float(vehicle.get_meta("traffic_wrecked_at_s", 0.0))
    var clear_delay := float(vehicle.get_meta("traffic_wreck_clear_after_s", 0.0))
    if clear_delay < 12.0:
        _fail("tow lifecycle shortened wreck obstruction too aggressively")
        return

    manager.call("process_tow_services_at", wrecked_at + 6.9)
    if int(manager.call("get_visible_tow_service_count")) != 0:
        _fail("tow truck arrived before configured delay")
        return

    manager.call("process_tow_services_at", wrecked_at + 7.0)
    if int(manager.call("get_visible_tow_service_count")) != 1:
        _fail("tow truck did not become visible at arrival")
        return

    var tow: Node = tow_root.get_child(0)
    if tow == null or not bool(tow.get_meta("simulated_tow_service", false)):
        _fail("tow node is not labelled as simulated service")
        return
    var collision := tow.get_node_or_null("CollisionShape3D") as CollisionShape3D
    if collision == null or collision.shape == null or collision.disabled:
        _fail("arrived tow truck has no active collision")
        return

    var completed_early := int(manager.call("process_tow_services_at", wrecked_at + clear_delay - 0.1))
    if completed_early != 0 or int(manager.call("get_wreck_count")) != 1:
        _fail("tow service cleared the wreck before its deadline")
        return

    var completed := int(manager.call("process_tow_services_at", wrecked_at + clear_delay))
    if completed != 1:
        _fail("tow service did not complete at clearance deadline")
        return
    if int(manager.call("get_tow_service_count")) != 0:
        _fail("completed tow assignment remained active")
        return
    if int(manager.call("get_wreck_count")) != 0:
        _fail("wreck still counted after tow completion")
        return

    await process_frame
    if traffic_root.get_child_count() != 0 or tow_root.get_child_count() != 0:
        _fail("wreck or tow truck remained in scene after service completion")
        return

    manager.queue_free()
    await process_frame
    print("TRAFFIC_TOW_SERVICE_OK: assignment, delayed arrival, visible collision, service hold and joint clearance passed")
    quit(0)
