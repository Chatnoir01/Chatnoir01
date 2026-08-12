extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("TRAFFIC_CANONICAL_TOW_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var manager_script: Script = load("res://game/scripts/traffic_manager_core.gd")
    if manager_script == null:
        _fail("canonical manager did not load")
        return

    var manager := Node.new()
    manager.set_script(manager_script)
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
            _fail("canonical tow API missing: %s" % method_name)
            return

    manager.set("wreck_clear_delay_s", 18.0)
    manager.set("tow_arrival_delay_s", 7.0)
    manager.set("tow_service_duration_s", 5.0)

    var traffic_root := manager.get_node_or_null("TrafficVehicles")
    var tow_root := manager.get_node_or_null("TowServices")
    if traffic_root == null or tow_root == null:
        _fail("traffic or tow root missing")
        return

    var vehicle: CharacterBody3D = manager.call("_create_vehicle_node") as CharacterBody3D
    if vehicle == null:
        _fail("canonical AI vehicle factory returned null")
        return
    traffic_root.add_child(vehicle)
    await process_frame

    for _index: int in range(10):
        vehicle.call("apply_traffic_test_impact", 75.0, 1.0)
        if bool(vehicle.call("is_traffic_disabled")):
            break
    if not bool(vehicle.call("is_traffic_disabled")):
        _fail("severe impacts did not create canonical wreck")
        return

    if int(manager.call("get_wreck_count")) != 1:
        _fail("wreck count mismatch")
        return
    if int(manager.call("get_tow_service_count")) != 1:
        _fail("wreck did not receive exactly one tow assignment")
        return
    if int(manager.call("get_visible_tow_service_count")) != 0:
        _fail("tow service visible before configured arrival")
        return

    var wrecked_at := float(vehicle.get_meta("traffic_wrecked_at_s", 0.0))
    var clear_delay := float(vehicle.get_meta("traffic_wreck_clear_after_s", 0.0))
    if clear_delay < 12.0:
        _fail("tow lifecycle shortened road obstruction too aggressively")
        return

    manager.call("process_tow_services_at", wrecked_at + 6.9)
    if int(manager.call("get_visible_tow_service_count")) != 0:
        _fail("tow service arrived early")
        return

    manager.call("process_tow_services_at", wrecked_at + 7.0)
    if int(manager.call("get_visible_tow_service_count")) != 1:
        _fail("tow service did not appear at arrival")
        return

    var tow: Node = tow_root.get_child(0)
    if tow == null or not bool(tow.get_meta("simulated_tow_service", false)):
        _fail("tow node lacks simulated-service provenance")
        return
    var collision := tow.get_node_or_null("CollisionShape3D") as CollisionShape3D
    if collision == null or collision.shape == null or collision.disabled:
        _fail("arrived tow service lacks active collision")
        return

    if int(manager.call("process_tow_services_at", wrecked_at + clear_delay - 0.1)) != 0:
        _fail("tow completed before clearance deadline")
        return
    if int(manager.call("get_wreck_count")) != 1:
        _fail("wreck disappeared before tow completion")
        return

    if int(manager.call("process_tow_services_at", wrecked_at + clear_delay)) != 1:
        _fail("tow did not complete at clearance deadline")
        return
    if int(manager.call("get_tow_service_count")) != 0 or int(manager.call("get_wreck_count")) != 0:
        _fail("tow or wreck remained counted after completion")
        return

    await process_frame
    if traffic_root.get_child_count() != 0 or tow_root.get_child_count() != 0:
        _fail("tow or wreck remained in runtime roots after completion")
        return

    manager.queue_free()
    print("TRAFFIC_CANONICAL_TOW_OK: one assignment, delayed visible collision and joint clearance passed")
    quit(0)
