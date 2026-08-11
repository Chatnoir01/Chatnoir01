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
    if not car.has_method("enter_driver") or not car.has_method("exit_driver"):
        _fail("vehicle API missing")
        return
    if bool(car.call("has_driver")):
        _fail("car unexpectedly starts occupied")
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

    print("VEHICLE_SMOKE_OK: enter/exit flow passed")
    scene.queue_free()
    await process_frame
    quit(0)
