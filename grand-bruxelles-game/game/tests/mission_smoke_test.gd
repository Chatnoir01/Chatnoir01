extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("MISSION_SMOKE_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var packed: PackedScene = load("res://game/main.tscn")
    if packed == null:
        _fail("main scene did not load")
        return

    var scene: Node = packed.instantiate()
    root.add_child(scene)
    await process_frame
    await physics_frame

    var player: CharacterBody3D = scene.get_node_or_null("Player") as CharacterBody3D
    var car: CharacterBody3D = scene.get_node_or_null("PrototypeCar") as CharacterBody3D
    var mission: Node = scene.get_node_or_null("MissionDriveToCenter")
    var label: Label = scene.get_node_or_null("MissionLabel") as Label

    if player == null or car == null or mission == null or label == null:
        _fail("mission dependencies missing")
        return
    if int(mission.call("get_stage")) != 0:
        _fail("mission should start at stage 0")
        return

    car.call("enter_driver", player)
    await physics_frame
    if int(mission.call("get_stage")) != 1:
        _fail("entering the car should start route stage 1")
        return

    var checkpoints: Array[Vector3] = [
        Vector3(-272.04, 0.58, -217.07),
        Vector3(81.54, 0.58, -664.58),
        Vector3(319.01, 0.58, -535.20),
    ]

    for index: int in range(checkpoints.size()):
        car.global_position = checkpoints[index]
        car.velocity = Vector3.ZERO
        await physics_frame
        await physics_frame
        var expected_stage: int = index + 2
        if int(mission.call("get_stage")) != expected_stage:
            _fail("checkpoint %d did not advance to stage %d" % [index, expected_stage])
            return

    if int(mission.call("get_stage")) != int(mission.call("get_stage_count")):
        _fail("mission did not reach completed stage")
        return
    if not label.text.contains("MISSION TERMINÉE"):
        _fail("mission completion HUD text missing")
        return

    print("MISSION_SMOKE_OK: Midi -> Anneessens -> Bourse -> Grand-Place passed")
    scene.queue_free()
    await process_frame
    quit(0)
