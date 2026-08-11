extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("TRAFFIC_MIX_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var manager_script: Script = load("res://game/scripts/traffic_manager.gd")
    if manager_script == null:
        _fail("traffic manager script did not load")
        return

    var manager := Node3D.new()
    manager.name = "TrafficMixTest"
    manager.set_script(manager_script)
    manager.set("max_vehicles", 0)
    manager.set("density_enabled", false)
    manager.set("max_crossing_pedestrians", 0)
    manager.set("traffic_seed", 2026)
    manager.set("scooter_share", 0.25)
    manager.set("motorcycle_share", 0.20)
    root.add_child(manager)
    await process_frame

    if not manager.has_method("get_active_archetype_counts"):
        _fail("mixed traffic API missing")
        return

    var counts := {"car": 0, "scooter": 0, "motorcycle": 0}
    for _index: int in range(80):
        var vehicle: CharacterBody3D = manager.call("_create_vehicle_node")
        if vehicle == null:
            _fail("vehicle factory returned null")
            return
        if not vehicle.has_method("get_traffic_archetype"):
            _fail("vehicle archetype API missing")
            return
        var archetype := str(vehicle.call("get_traffic_archetype"))
        if archetype not in ["car", "scooter", "motorcycle"]:
            _fail("unknown archetype: %s" % archetype)
            return
        counts[archetype] = int(counts.get(archetype, 0)) + 1

        var collision := vehicle.get_node_or_null("CollisionShape3D") as CollisionShape3D
        if collision == null or collision.shape == null:
            _fail("%s missing collision shape" % archetype)
            return
        vehicle.free()

    if int(counts["car"]) <= 0 or int(counts["scooter"]) <= 0 or int(counts["motorcycle"]) <= 0:
        _fail("fixed-seed mix did not produce all archetypes: %s" % str(counts))
        return

    var vehicle_script: Script = load("res://game/scripts/traffic_vehicle.gd")
    var car := CharacterBody3D.new()
    car.set_script(vehicle_script)
    car.call("configure_archetype", "car")
    var scooter := CharacterBody3D.new()
    scooter.set_script(vehicle_script)
    scooter.call("configure_archetype", "scooter")
    var motorcycle := CharacterBody3D.new()
    motorcycle.set_script(vehicle_script)
    motorcycle.call("configure_archetype", "motorcycle")

    if float(scooter.get("steering_response")) <= float(car.get("steering_response")):
        _fail("scooter should steer more responsively than car")
        return
    if float(motorcycle.get("acceleration_mps2")) <= float(car.get("acceleration_mps2")):
        _fail("motorcycle should accelerate faster than car")
        return
    if float(scooter.get("speed_factor")) >= float(motorcycle.get("speed_factor")):
        _fail("scooter cruise profile should remain below motorcycle")
        return

    car.free()
    scooter.free()
    motorcycle.free()
    manager.queue_free()
    await process_frame

    print("TRAFFIC_MIX_OK: cars=%d scooters=%d motorcycles=%d with distinct handling profiles" % [counts["car"], counts["scooter"], counts["motorcycle"]])
    quit(0)
