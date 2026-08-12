extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("VEHICLE_SERVICE_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var service_script: Script = load("res://game/scripts/vehicle_service_system.gd")
    var fake_vehicle_script: Script = load("res://game/tests/fake_service_vehicle.gd")
    if service_script == null or fake_vehicle_script == null:
        _fail("service system or vehicle fixture did not load")
        return

    var holder := Node3D.new()
    holder.name = "Holder"
    root.add_child(holder)

    var car := Node3D.new()
    car.name = "FakeCar"
    car.set_script(fake_vehicle_script)
    holder.add_child(car)

    var system := Node.new()
    system.name = "VehicleServiceSystem"
    system.set_script(service_script)
    system.set("car_path", NodePath("../FakeCar"))
    holder.add_child(system)
    await process_frame

    if int(system.call("get_service_count")) != 2:
        _fail("current committed service pack should contain exactly two OSM services")
        return
    if int(system.call("get_active_service_count")) != 1:
        _fail("only Expres Pneu should fall inside current runtime bounds")
        return
    if int(system.call("get_active_garage_count")) != 0:
        _fail("H.R.Z Services is outside current playable bounds and must not be interactable")
        return

    var current_nearest: Dictionary = system.call("nearest_active_service", Vector3(-730.348, 0.68, -273.968))
    if str(current_nearest.get("name", "")) != "Expres Pneu":
        _fail("current active OSM service mismatch")
        return
    if str(current_nearest.get("kind", "")) != "tyres":
        _fail("Expres Pneu must remain a tyre service, not a full garage")
        return

    var synthetic := {
        "services": [
            {"osm_id": 1, "kind": "garage", "name": "Garage Fixture", "point": [0.0, 0.0]},
            {"osm_id": 2, "kind": "tyres", "name": "Tyre Fixture", "point": [60.0, 0.0]},
        ]
    }
    system.call("configure_data", synthetic, [-100.0, -100.0, 100.0, 100.0])
    car.global_position = Vector3.ZERO

    if int(system.call("get_active_garage_count")) != 1:
        _fail("synthetic active garage was not accepted")
        return
    var quote := float(system.call("estimate_full_repair_quote", 40.0, 60.0))
    if quote <= 35.0:
        _fail("garage repair quote did not scale with damage")
        return
    if not bool(system.call("request_full_repair", 10.0)):
        _fail("damaged stopped vehicle could not start garage repair")
        return
    if str(system.call("get_service_state")) != "requested":
        _fail("garage service did not enter requested state")
        return
    if bool(system.call("process_service_at", 13.4)):
        _fail("garage repair completed before configured delay")
        return
    if not bool(system.call("process_service_at", 13.5)):
        _fail("garage repair did not complete after configured delay")
        return
    if float(car.call("get_vehicle_health")) != 100.0 or int(car.get("repair_calls")) != 1:
        _fail("garage repair did not fully restore vehicle")
        return

    system.call("reset_service_state")
    car.set("health", 47.0)
    car.set("speed_kmh", 5.0)
    if bool(system.call("request_full_repair", 20.0)):
        _fail("moving vehicle was accepted for garage repair")
        return

    holder.queue_free()
    await process_frame
    print("VEHICLE_SERVICE_OK: real OSM bounds filtering, service type integrity, quote, delay and full repair passed")
    quit(0)
