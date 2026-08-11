extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("POLICE_GAMEPLAY_SMOKE_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene failed to load")
        return

    var main := packed.instantiate()
    root.add_child(main)
    await process_frame
    await process_frame
    await process_frame

    var wanted := main.get_node_or_null("WantedSystem")
    var dispatch := main.get_node_or_null("PoliceDispatch")
    var player := main.get_node_or_null("Player") as Node3D
    var patrol := main.get_node_or_null("PolicePatrol") as Node3D
    var traffic := main.get_node_or_null("PrototypeCar") as Node3D

    if wanted == null or dispatch == null or player == null or patrol == null or traffic == null:
        _fail("main police gameplay nodes are incomplete")
        return

    if not wanted.has_method("report_offence") or not wanted.has_method("arrest_player"):
        _fail("wanted system API missing")
        return
    if not dispatch.has_method("get_deployed_count"):
        _fail("dispatch API missing")
        return
    if not player.has_method("get_gameplay_position") or not player.has_method("is_arrested"):
        _fail("player police API missing")
        return

    wanted.call("report_offence", 35.0, "smoke_test")
    await process_frame
    await process_frame
    if int(wanted.call("get_wanted_level")) < 2:
        _fail("offence did not create expected wanted level")
        return
    if int(dispatch.call("get_deployed_count")) < 2:
        _fail("dispatch did not deploy enough officers")
        return

    var officers := get_nodes_in_group("police_officer")
    if officers.size() < 2:
        _fail("police officer instances were not deployed")
        return

    var visuals := patrol.get_node_or_null("EmergencyVisuals")
    if visuals == null or not bool(visuals.call("are_emergency_lights_active")):
        _fail("dispatch did not activate police emergency lights")
        return

    if not traffic.has_method("get_emergency_yield_factor"):
        _fail("traffic emergency-yield API missing")
        return
    if float(traffic.call("get_emergency_yield_factor")) >= 1.0:
        _fail("nearby traffic did not detect active emergency vehicle")
        return

    wanted.call("clear_wanted")
    await process_frame
    await process_frame
    if int(dispatch.call("get_deployed_count")) != 0:
        _fail("dispatch did not stand down after wanted cleared")
        return
    if bool(visuals.call("are_emergency_lights_active")):
        _fail("police emergency lights stayed active after stand-down")
        return

    player.global_position = patrol.global_position
    player.call("try_enter_vehicle")
    await process_frame
    if not bool(patrol.call("has_driver")):
        _fail("player could not enter police patrol vehicle")
        return
    if int(wanted.call("get_wanted_level")) < 2:
        _fail("police vehicle theft did not create a wanted level")
        return
    if player.call("get_gameplay_position") != patrol.global_position:
        _fail("pursuit target does not follow driven vehicle")
        return

    patrol.call("exit_driver")
    await process_frame
    wanted.call("report_offence", 30.0, "arrest_test")
    wanted.call("arrest_player", player)
    if not bool(player.call("is_arrested")):
        _fail("arrest did not immobilize player")
        return
    if int(wanted.call("get_wanted_level")) != 0:
        _fail("arrest did not clear wanted state")
        return

    wanted.call("release_arrest")
    if bool(player.call("is_arrested")):
        _fail("release did not restore player control")
        return

    print("POLICE_GAMEPLAY_SMOKE_OK: wanted, dispatch, pursuit target, arrest and emergency yield passed")
    main.queue_free()
    await process_frame
    quit(0)
