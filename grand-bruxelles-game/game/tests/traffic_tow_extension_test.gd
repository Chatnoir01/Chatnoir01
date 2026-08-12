extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("TRAFFIC_TOW_EXTENSION_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var manager := TrafficManagerTowExtension.new()
    manager.auto_load_data = false
    manager.auto_spawn_runtime = false
    manager.tow_arrival_delay_s = 7.0
    manager.tow_service_duration_s = 5.0
    manager.wreck_clear_delay_s = 18.0
    get_root().add_child(manager)
    await process_frame

    var contract := TrafficRuntimeContract.new()
    var missing: PackedStringArray = contract.validate_manager(manager, true)
    if not missing.is_empty():
        _fail("tow manager contract incomplete: %s" % [missing])
        return
    if manager.get_node_or_null("TowServices") == null:
        _fail("tow service root was not created")
        return

    var wreck := TrafficVehicleCore.new()
    wreck.name = "SyntheticWreck"
    wreck.position = Vector3(10.0, 0.0, 20.0)
    var traffic_root := manager.get_node("TrafficVehicles")
    traffic_root.add_child(wreck)
    await process_frame
    wreck.set_meta("traffic_wrecked", true)
    wreck.set_meta("traffic_wrecked_at_s", 100.0)
    manager.call("_on_traffic_vehicle_disabled", wreck)

    if manager.get_tow_service_count() != 1:
        _fail("disabled vehicle did not receive exactly one tow assignment")
        return
    if manager.get_visible_tow_service_count() != 0:
        _fail("tow truck became visible before configured arrival")
        return
    if manager.process_tow_services_at(106.9) != 0 or manager.get_visible_tow_service_count() != 0:
        _fail("tow arrived too early")
        return
    if manager.process_tow_services_at(107.0) != 0 or manager.get_visible_tow_service_count() != 1:
        _fail("tow did not arrive at deterministic arrival time")
        return
    if manager.cleanup_wrecks_at(117.9) != 0:
        _fail("base wreck cleanup bypassed active tow service")
        return
    if manager.process_tow_services_at(118.0) != 1:
        _fail("tow service did not complete at protected wreck-clear time")
        return
    await process_frame
    if manager.get_tow_service_count() != 0 or manager.get_visible_tow_service_count() != 0:
        _fail("completed tow assignment was not cleared")
        return
    if is_instance_valid(wreck) and not wreck.is_queued_for_deletion():
        _fail("wreck remained active after tow completion")
        return

    manager.queue_free()
    print("TRAFFIC_TOW_EXTENSION_OK: optional v9 parity arrival, visibility, protected cleanup and completion")
    quit(0)
