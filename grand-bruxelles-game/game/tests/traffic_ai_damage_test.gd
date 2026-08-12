extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("TRAFFIC_AI_DAMAGE_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var manager_script: Script = load("res://game/scripts/traffic_manager.gd")
    if manager_script == null:
        _fail("traffic manager script did not load")
        return

    var manager := Node3D.new()
    manager.name = "TrafficAIDamageTest"
    manager.set_script(manager_script)
    manager.set("max_vehicles", 0)
    manager.set("density_enabled", false)
    manager.set("max_crossing_pedestrians", 0)
    manager.set("max_parked_vehicles", 0)
    manager.set("max_delivery_vehicles", 0)
    manager.set("wreck_clear_delay_s", 18.0)
    root.add_child(manager)
    await process_frame

    for method_name: String in ["get_wreck_count", "cleanup_wrecks_at", "_create_vehicle_node"]:
        if not manager.has_method(method_name):
            _fail("wreck manager API missing: %s" % method_name)
            return

    var traffic_root := manager.get_node_or_null("TrafficVehicles")
    if traffic_root == null:
        _fail("TrafficVehicles root missing")
        return

    var vehicle: CharacterBody3D = manager.call("_create_vehicle_node") as CharacterBody3D
    if vehicle == null:
        _fail("AI vehicle factory returned null")
        return
    traffic_root.add_child(vehicle)
    await process_frame

    for method_name: String in [
        "apply_traffic_test_impact",
        "get_traffic_vehicle_health",
        "get_traffic_vehicle_performance_factor",
        "is_traffic_disabled",
    ]:
        if not vehicle.has_method(method_name):
            _fail("AI damage API missing: %s" % method_name)
            return

    var light: Dictionary = vehicle.call("apply_traffic_test_impact", 8.0, 1.0)
    if float(light.get("last_impact_damage", -1.0)) != 0.0:
        _fail("sub-threshold AI impact caused damage")
        return

    var moderate: Dictionary = vehicle.call("apply_traffic_test_impact", 45.0, 0.85)
    if float(moderate.get("health", 100.0)) >= 100.0:
        _fail("moderate AI collision did not reduce health")
        return
    if float(vehicle.call("get_traffic_vehicle_performance_factor")) >= 1.0:
        _fail("AI mechanical damage did not reduce performance")
        return
    if bool(vehicle.call("is_traffic_disabled")):
        _fail("single moderate AI collision immobilized vehicle too aggressively")
        return

    for _index: int in range(8):
        vehicle.call("apply_traffic_test_impact", 70.0, 1.0)
        if bool(vehicle.call("is_traffic_disabled")):
            break

    if not bool(vehicle.call("is_traffic_disabled")):
        _fail("repeated severe AI impacts never immobilized vehicle")
        return
    if float(vehicle.call("get_traffic_vehicle_performance_factor")) != 0.0:
        _fail("disabled AI vehicle still exposes drive performance")
        return
    if not bool(vehicle.get_meta("traffic_wrecked", false)):
        _fail("disabled AI vehicle was not marked as a road wreck")
        return
    if int(manager.call("get_wreck_count")) != 1:
        _fail("manager did not register exactly one traffic wreck")
        return
    if vehicle.velocity.length() > 0.01 or float(vehicle.get("speed_mps")) > 0.01:
        _fail("wrecked AI vehicle did not stop")
        return

    var wrecked_at := float(vehicle.get_meta("traffic_wrecked_at_s", 0.0))
    var clear_delay := float(vehicle.get_meta("traffic_wreck_clear_after_s", 0.0))
    if clear_delay < 4.0:
        _fail("wreck clearance delay is unrealistically short")
        return
    if int(manager.call("cleanup_wrecks_at", wrecked_at + clear_delay - 0.1)) != 0:
        _fail("wreck was cleared before its tow delay")
        return
    if int(manager.call("get_wreck_count")) != 1:
        _fail("wreck disappeared before clearance deadline")
        return

    if int(manager.call("cleanup_wrecks_at", wrecked_at + clear_delay)) != 1:
        _fail("wreck was not cleared at tow deadline")
        return
    if int(manager.call("get_wreck_count")) != 0:
        _fail("cleared wreck still counted as active")
        return

    await process_frame
    if traffic_root.get_child_count() != 0:
        _fail("wreck node remained in traffic tree after clearance")
        return

    manager.queue_free()
    await process_frame
    print("TRAFFIC_AI_DAMAGE_OK: threshold, degradation, wreck obstruction, tow delay and clearance passed")
    quit(0)
