extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("POLICE_PURSUIT_SMOKE_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var packed: PackedScene = load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene failed to load")
        return

    var main: Node = packed.instantiate()
    root.add_child(main)
    for _index: int in range(5):
        await process_frame

    var wanted: Node = main.get_node_or_null("WantedSystem")
    var dispatch: Node = main.get_node_or_null("PoliceDispatch")
    var router: Node = main.get_node_or_null("PoliceRoadRouter")
    if wanted == null or dispatch == null or router == null:
        _fail("pursuit systems missing from main scene")
        return

    if not router.has_method("get_segment_count") or int(router.call("get_segment_count")) < 100:
        _fail("road router did not load enough drivable Brussels segments")
        return
    if not dispatch.has_method("get_deployed_vehicle_count") or not dispatch.has_method("get_blockade_count"):
        _fail("dispatch pursuit API missing")
        return

    wanted.call("set_heat", 35.0)
    await process_frame
    await process_frame
    if int(wanted.call("get_wanted_level")) != 2:
        _fail("heat 35 did not resolve to wanted level 2")
        return
    if int(dispatch.call("get_deployed_vehicle_count")) != 1:
        _fail("level 2 did not deploy exactly one pursuit vehicle")
        return

    var pursuit_units: Array[Node] = get_nodes_in_group("police_pursuit_unit")
    if pursuit_units.size() != 1:
        _fail("pursuit unit group count mismatch at level 2")
        return
    var pursuit: Node3D = pursuit_units[0] as Node3D
    if pursuit == null or not pursuit.has_method("is_ai_controlled") or not bool(pursuit.call("is_ai_controlled")):
        _fail("spawned pursuit vehicle is not AI controlled")
        return
    var visuals: Node = pursuit.get_node_or_null("EmergencyVisuals")
    if visuals == null or not bool(visuals.call("are_emergency_lights_active")):
        _fail("pursuit vehicle emergency lights are not active")
        return

    var start_position: Vector3 = pursuit.global_position
    for _index: int in range(28):
        await physics_frame
    var moved_distance: float = pursuit.global_position.distance_to(start_position)
    if moved_distance < 0.15:
        _fail("AI pursuit vehicle did not move")
        return
    var route_point: Vector3 = pursuit.call("get_ai_route_point") as Vector3
    if route_point == Vector3.ZERO:
        _fail("AI pursuit vehicle never acquired a road route point")
        return

    wanted.call("set_heat", 80.0)
    await process_frame
    await process_frame
    if int(wanted.call("get_wanted_level")) != 4:
        _fail("heat 80 did not resolve to wanted level 4")
        return
    if int(dispatch.call("get_deployed_vehicle_count")) != 2:
        _fail("level 4 did not deploy patrol plus unmarked unit")
        return
    if int(dispatch.call("get_blockade_count")) != 1:
        _fail("level 4 did not deploy one roadblock")
        return

    wanted.call("set_heat", 105.0)
    await process_frame
    await process_frame
    if int(wanted.call("get_wanted_level")) != 5:
        _fail("heat 105 did not resolve to wanted level 5")
        return
    if int(dispatch.call("get_deployed_vehicle_count")) != 3:
        _fail("level 5 did not deploy three pursuit vehicles")
        return
    if int(dispatch.call("get_blockade_count")) != 2:
        _fail("level 5 did not deploy two roadblocks")
        return

    var bab_found: bool = false
    for unit: Node in get_nodes_in_group("police_pursuit_unit"):
        if unit.is_in_group("police_bab"):
            bab_found = true
            break
    if not bab_found:
        _fail("level 5 pursuit did not include BAB reinforcement")
        return

    wanted.call("clear_wanted")
    await process_frame
    await process_frame
    if int(dispatch.call("get_deployed_vehicle_count")) != 0:
        _fail("pursuit vehicles did not stand down")
        return
    if int(dispatch.call("get_blockade_count")) != 0:
        _fail("roadblocks did not stand down")
        return

    print("POLICE_PURSUIT_SMOKE_OK: road routing, AI vehicles, roadblocks and BAB escalation passed")
    main.queue_free()
    await process_frame
    quit(0)
