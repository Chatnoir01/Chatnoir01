extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const PRODUCTION_VEHICLE_NODE := "PrototypeCar"
const REMOVED_PHYSICAL_PROTOTYPE := "PhysicalCarB"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("PRODUCTION_MISSION_VEHICLE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var main: Node = MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main

    # Production traffic cleanup is deferred. Wait through both process and
    # physics frames so the contract is evaluated after PhysicalCarB is gone.
    for _frame: int in range(12):
        await process_frame
        await physics_frame

    var mission := main.get_node_or_null("MissionDriveToCenter")
    var player := main.get_node_or_null("Player") as CharacterBody3D
    var primary := main.get_node_or_null(PRODUCTION_VEHICLE_NODE) as CharacterBody3D
    var removed := main.get_node_or_null(REMOVED_PHYSICAL_PROTOTYPE)
    if mission == null or player == null or primary == null:
        _fail("production mission/player/PrototypeCar missing")
        return
    if removed != null:
        _fail("obsolete PhysicalCarB survived production cleanup")
        return
    for required_method: String in ["has_driver", "enter_driver", "exit_driver"]:
        if not primary.has_method(required_method):
            _fail("production vehicle contract missing method: %s" % required_method)
            return
    if str(mission.call("primary_vehicle_node_name")) != PRODUCTION_VEHICLE_NODE:
        _fail("mission primary vehicle identity drifted")
        return
    if not mission.has_method("primary_vehicle_is_valid") or not bool(mission.call("primary_vehicle_is_valid")):
        _fail("mission cannot prove a valid production vehicle binding")
        return
    if mission.get("car") != primary:
        _fail("mission cached vehicle is not PrototypeCar")
        return

    var label := main.get_node_or_null("MissionLabel") as Label
    if label == null or label.text.to_lower().find("voiture") < 0:
        _fail("mission UI no longer directs the player to the production car")
        return

    primary.call("enter_driver", player)
    await physics_frame
    await process_frame
    if int(mission.call("get_stage")) != 1:
        _fail("entering production vehicle did not start Mission 01")
        return
    if not bool(primary.call("has_driver")):
        _fail("production vehicle lost driver immediately after mission start")
        return

    primary.call("exit_driver")
    primary.velocity = Vector3(7.0, 2.0, -3.0)
    if "speed" in primary:
        primary.set("speed", 11.0)
    mission.call("restart_mission")
    await physics_frame
    await process_frame

    var horizontal_speed := Vector2(primary.velocity.x, primary.velocity.z).length()
    var controller_speed := float(primary.get("speed")) if "speed" in primary else 0.0
    if horizontal_speed > 0.05 or absf(controller_speed) > 0.05:
        _fail("mission restart retained production vehicle motion: horizontal=%.3f controller=%.3f" % [horizontal_speed, controller_speed])
        return
    if int(mission.call("get_stage")) != 0:
        _fail("mission restart did not return to stage zero")
        return
    if not bool(mission.call("primary_vehicle_is_valid")):
        _fail("mission primary vehicle invalid after restart")
        return

    print("PRODUCTION_MISSION_VEHICLE_OK primary=PrototypeCar physical_prototype_removed=true mission_started=true reset_horizontal=%.3f reset_controller=%.3f" % [horizontal_speed, controller_speed])
    main.queue_free()
    quit(0)
