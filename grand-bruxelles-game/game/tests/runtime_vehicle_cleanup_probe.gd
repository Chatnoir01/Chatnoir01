extends SceneTree

const EXT := preload("res://game/scripts/traffic_manager_rgsdev_vehicle_extension.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("RUNTIME_VEHICLE_CLEANUP_FAIL %s" % message)
    quit(1)

func _run() -> void:
    var world := Node3D.new()
    root.add_child(world)

    var manager := EXT.new()
    manager.auto_load_data = false
    manager.auto_spawn_runtime = false
    world.add_child(manager)

    var prototype := CharacterBody3D.new()
    prototype.name = "PrototypeCar"
    prototype.add_to_group("vehicle")
    world.add_child(prototype)

    var physical := RigidBody3D.new()
    physical.name = "PhysicalCarB"
    physical.add_to_group("vehicle")
    world.add_child(physical)

    await process_frame
    await process_frame

    if world.get_node_or_null("PhysicalCarB") != null:
        _fail("PhysicalCarB still exists")
        return
    if world.get_node_or_null("PrototypeCar") == null:
        _fail("PrototypeCar removed unexpectedly")
        return

    print("RUNTIME_VEHICLE_CLEANUP_OK prototype=true physical=false")
    quit(0)
