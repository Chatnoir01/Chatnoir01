extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("TRAFFIC_DELIVERY_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var manager_script: Script = load("res://game/scripts/traffic_manager.gd")
    if manager_script == null:
        _fail("traffic manager script did not load")
        return

    var manager := Node3D.new()
    manager.name = "DeliveryTest"
    manager.set_script(manager_script)
    manager.set("max_vehicles", 0)
    manager.set("density_enabled", false)
    manager.set("max_crossing_pedestrians", 0)
    manager.set("max_parked_vehicles", 0)
    manager.set("max_delivery_vehicles", 2)
    manager.set("parking_spawn_radius_m", 2000.0)
    manager.set("delivery_spawn_radius_m", 2000.0)
    manager.set("traffic_seed", 77)
    root.add_child(manager)
    await process_frame

    for method_name: String in [
        "get_delivery_vehicle_count",
        "get_reserved_parking_candidate_count",
        "expire_deliveries_at",
    ]:
        if not manager.has_method(method_name):
            _fail("delivery API missing: %s" % method_name)
            return

    var count := int(manager.call("get_delivery_vehicle_count"))
    if count != 2:
        _fail("expected 2 temporary delivery vans, got %d" % count)
        return
    if int(manager.call("get_reserved_parking_candidate_count")) != count:
        _fail("delivery curb slots were not reserved one-to-one")
        return

    var delivery_root := manager.get_node_or_null("DeliveryVehicles")
    if delivery_root == null:
        _fail("DeliveryVehicles root missing")
        return

    var seen_candidates := {}
    for child: Node in delivery_root.get_children():
        if not bool(child.get_meta("simulated_delivery", false)):
            _fail("delivery van is not explicitly marked simulated")
            return
        var candidate_id := int(child.get_meta("parking_candidate_id", -1))
        if candidate_id < 0 or seen_candidates.has(candidate_id):
            _fail("delivery vans share or lost curb candidate ids")
            return
        seen_candidates[candidate_id] = true
        var collision := child.get_node_or_null("CollisionShape3D") as CollisionShape3D
        if collision == null or collision.shape == null:
            _fail("delivery van missing collision shape")
            return

    var expired := int(manager.call("expire_deliveries_at", 1000000000.0))
    if expired != count:
        _fail("forced delivery expiry count mismatch: %d/%d" % [expired, count])
        return
    if int(manager.call("get_delivery_vehicle_count")) != 0:
        _fail("expired deliveries remained active")
        return
    if int(manager.call("get_reserved_parking_candidate_count")) != 0:
        _fail("expired deliveries did not release curb reservations")
        return

    manager.queue_free()
    await process_frame
    print("TRAFFIC_DELIVERY_OK: temporary vans reserve unique safe curb slots and release them on expiry")
    quit(0)
