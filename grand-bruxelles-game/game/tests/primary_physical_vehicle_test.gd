extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("PRIMARY_PHYSICAL_VEHICLE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    for _frame: int in range(8):
        await process_frame
    await physics_frame

    var mission := main.get_node_or_null("MissionDriveToCenter")
    var player := main.get_node_or_null("Player") as CharacterBody3D
    var primary := main.get_node_or_null("PrototypeCar") as CharacterBody3D
    var legacy := main.get_node_or_null("PhysicalCarB")
    if mission == null or player == null or primary == null:
        _fail("production mission/player/primary vehicle nodes missing")
        return
    if legacy != null:
        _fail("legacy PhysicalCarB still active")
        return
    if str(mission.call("primary_vehicle_node_name")) != "PrototypeCar":
        _fail("mission primary vehicle identity drifted")
        return
    if mission.get("car") != primary:
        _fail("mission is not bound to PrototypeCar")
        return
    for method_name: String in ["enter_driver", "exit_driver", "has_driver", "assign_external_driver", "set_external_drive_input", "get_visual_steering_angle"]:
        if not primary.has_method(method_name):
            _fail("unified production controller contract missing: %s" % method_name)
            return

    var label := main.get_node_or_null("MissionLabel") as Label
    if label == null or label.text.find("VOITURE DE DÉPART") < 0:
        _fail("mission UI does not direct player to unified starter car")
        return

    primary.call("enter_driver", player)
    await physics_frame
    await process_frame
    if int(mission.call("get_stage")) != 1:
        _fail("entering unified starter car did not start Mission 01")
        return
    if not bool(primary.call("has_driver")):
        _fail("starter car did not retain player driver")
        return

    primary.call("exit_driver")
    primary.velocity = Vector3(7.0, 0.0, -3.0)
    primary.set("speed", 8.0)
    mission.call("restart_mission")
    await physics_frame
    var horizontal_speed := Vector2(primary.velocity.x, primary.velocity.z).length()
    if horizontal_speed > 0.05 or absf(float(primary.get("speed"))) > 0.05:
        _fail("mission restart retained starter vehicle motion: horizontal=%.3f speed=%.3f" % [horizontal_speed, float(primary.get("speed"))])
        return

    var visual := primary.get_node_or_null("RgsdevVisual")
    if visual == null or not visual.has_method("get_visual_contract"):
        _fail("starter Rgsdev visual missing")
        return
    var contract: Dictionary = visual.call("get_visual_contract")
    var visual_dot := float(contract.get("visual_forward_dot_body_forward", -1.0))
    if visual_dot < 0.985:
        _fail("starter visual forward drifted: %.4f" % visual_dot)
        return

    print("PRIMARY_PHYSICAL_VEHICLE_OK: mission=PrototypeCar unified=true legacy_B=false visual_dot=%.4f reset_horizontal=%.3f" % [visual_dot, horizontal_speed])
    main.queue_free()
    quit(0)
