extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("VEHICLE_SMOKE_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var packed: PackedScene = load("res://game/main.tscn")
    if packed == null:
        _fail("main scene did not load")
        return

    var scene: Node = packed.instantiate()
    root.add_child(scene)
    await process_frame

    var player: CharacterBody3D = scene.get_node_or_null("Player") as CharacterBody3D
    var car: CharacterBody3D = scene.get_node_or_null("PrototypeCar") as CharacterBody3D
    if player == null:
        _fail("Player node missing")
        return
    if car == null:
        _fail("PrototypeCar node missing")
        return

    for method_name: String in [
        "enter_driver",
        "exit_driver",
        "get_speed_kmh",
        "get_max_forward_speed_kmh",
        "get_vehicle_health",
        "get_vehicle_body_damage",
        "get_vehicle_mechanical_damage",
        "get_vehicle_performance_factor",
        "is_vehicle_disabled",
        "apply_test_impact",
        "repair_vehicle",
    ]:
        if not car.has_method(method_name):
            _fail("vehicle API missing: %s" % method_name)
            return

    if bool(car.call("has_driver")):
        _fail("car unexpectedly starts occupied")
        return
    if absf(float(car.call("get_speed_kmh"))) > 0.01:
        _fail("parked car should start at 0 km/h")
        return
    if absf(float(car.call("get_vehicle_health")) - 100.0) > 0.01:
        _fail("prototype car should start undamaged")
        return

    car.call("enter_driver", player)
    await process_frame
    if not bool(car.call("has_driver")):
        _fail("driver was not attached")
        return
    if player.visible:
        _fail("player should be hidden while driving")
        return
    if player.is_physics_processing():
        _fail("player physics should be disabled while driving")
        return
    if float(car.call("get_max_forward_speed_kmh")) <= 30.0:
        _fail("vehicle maximum speed telemetry is invalid")
        return

    car.call("exit_driver")
    await process_frame
    if bool(car.call("has_driver")):
        _fail("driver was not detached")
        return
    if not player.visible:
        _fail("player should be visible after leaving vehicle")
        return
    if not player.is_physics_processing():
        _fail("player physics should be restored after leaving vehicle")
        return
    if absf(float(car.call("get_speed_kmh"))) > 0.01:
        _fail("car should reset to 0 km/h after exit")
        return

    var impact: Dictionary = car.call("apply_test_impact", 50.0, 1.0)
    if float(impact.get("health", 100.0)) >= 100.0:
        _fail("damage model is not connected to playable vehicle")
        return
    if float(car.call("get_vehicle_performance_factor")) >= 1.0:
        _fail("playable vehicle performance did not degrade after impact")
        return

    car.call("repair_vehicle", 100.0)
    if absf(float(car.call("get_vehicle_health")) - 100.0) > 0.01:
        _fail("playable vehicle repair did not restore health")
        return
    if bool(car.call("is_vehicle_disabled")):
        _fail("repaired vehicle remained disabled")
        return

    print("VEHICLE_SMOKE_OK: enter/exit, speed telemetry, damage and repair passed")
    scene.queue_free()
    await process_frame
    quit(0)
