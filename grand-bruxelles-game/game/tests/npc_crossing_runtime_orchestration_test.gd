extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("NPC_CROSSING_RUNTIME_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var manager := TrafficManagerNpcCrossingExtension.new()
    manager.auto_load_data = false
    manager.auto_spawn_runtime = false
    manager.official_density_enabled = false
    get_root().add_child(manager)
    await process_frame

    var roads: Array = [{
        "osm_id": 1001,
        "drivable": true,
        "highway": "residential",
        "width": 6.0,
        "maxspeed_kmh": 30.0,
        "points": [[-15.0, 0.0], [15.0, 0.0]],
    }]
    var controls: Array = [{
        "osm_id": 901,
        "kind": "crossing",
        "point": [0.0, 0.0],
        "crossing_signals": false,
        "crossing": "uncontrolled",
    }]
    manager.configure_test_data(roads, controls)
    var crossing_system: RefCounted = manager.get_npc_crossing_system()
    if crossing_system == null:
        _fail("manager did not expose canonical crossing system")
        return
    var crossing: Dictionary = crossing_system.call("get_crossing", 901)
    if crossing.is_empty():
        _fail("synthetic crossing was not built")
        return

    var traffic_root := manager.get_node_or_null("TrafficVehicles") as Node3D
    if traffic_root == null:
        _fail("canonical TrafficVehicles root is missing")
        return
    var vehicle := TrafficVehicleCore.new()
    vehicle.name = "ApproachingVehicle"
    traffic_root.add_child(vehicle)
    vehicle.set_physics_process(false)
    vehicle.global_position = Vector3(-5.0, 0.68, 0.0)
    vehicle.velocity = Vector3(5.0, 0.0, 0.0)

    if manager.is_crossing_gap_safe(901, Vector3.ZERO):
        _fail("closing vehicle inside stopping envelope was treated as a safe gap")
        return

    var director := NpcPopulationDirector.new()
    get_root().add_child(director)
    var agent := NpcAgent.new()
    get_root().add_child(agent)
    agent.set_spawn_context(NpcBehaviorModel.Role.CIVILIAN, 77, Vector3(0.0, 0.68, -6.0))
    var original_target := Vector3(0.0, 0.68, 6.0)
    agent.set_destination(original_target)
    agent.set_physics_process(false)
    if not director.register_agent(agent):
        _fail("real NpcAgent could not register with population director")
        return
    if not director.configure_traffic_crossing_runtime(manager):
        _fail("population director rejected crossing-capable traffic manager")
        return

    director.update_crossings_at(0.0)
    if not director.has_crossing_assignment(agent):
        _fail("civilian was not assigned to the crossing on its route")
        return

    var curb: Vector3 = crossing.get("start", Vector3.ZERO)
    var far_side: Vector3 = crossing.get("finish", Vector3.ZERO)
    if agent.get_world_position().distance_to(curb) > agent.get_world_position().distance_to(far_side):
        var swap := curb
        curb = far_side
        far_side = swap
    agent.global_position = curb
    director.update_crossings_at(0.10)
    var state: Dictionary = crossing_system.call("get_crossing_state", 901)
    if int(state.get("waiting", 0)) != 1 or not agent.movement_held:
        _fail("civilian did not enter curb-wait state")
        return

    var first_recheck: float = agent.pedestrian_context.curb_recheck_interval_seconds(0)
    var first_check_at: float = maxf(0.10 + 0.8, 0.10 + first_recheck)
    director.update_crossings_at(first_check_at)
    state = crossing_system.call("get_crossing_state", 901)
    if int(state.get("waiting", 0)) != 1 or int(state.get("crossing", 0)) != 0:
        _fail("civilian entered roadway while an approaching vehicle was inside stopping envelope")
        return

    vehicle.velocity = Vector3.ZERO
    if not manager.is_crossing_gap_safe(901, agent.get_world_position()):
        _fail("a yielded stationary vehicle outside minimum clearance still blocked forever")
        return

    var second_recheck: float = agent.pedestrian_context.curb_recheck_interval_seconds(1)
    director.update_crossings_at(first_check_at + second_recheck - 0.02)
    state = crossing_system.call("get_crossing_state", 901)
    if int(state.get("waiting", 0)) != 1 or int(state.get("crossing", 0)) != 0:
        _fail("civilian rechecked yielded traffic before its personal cadence elapsed")
        return

    var crossing_start_at: float = first_check_at + second_recheck + 0.02
    director.update_crossings_at(crossing_start_at)
    state = crossing_system.call("get_crossing_state", 901)
    if int(state.get("waiting", 0)) != 0 or int(state.get("crossing", 0)) != 1:
        _fail("civilian did not begin crossing at the next personal recheck after traffic yielded")
        return
    if agent.movement_held:
        _fail("civilian movement hold was not released for safe crossing")
        return
    if agent.behavior.target_position.distance_to(far_side) > 0.01:
        _fail("civilian destination was not redirected to far curb")
        return

    agent.global_position = far_side
    director.update_crossings_at(crossing_start_at + 0.10)
    state = crossing_system.call("get_crossing_state", 901)
    if int(state.get("waiting", 0)) != 0 or int(state.get("crossing", 0)) != 0:
        _fail("crossing occupancy was not cleared after exit")
        return
    if director.has_crossing_assignment(agent):
        _fail("crossing assignment leaked after reaching far curb")
        return
    if agent.behavior.target_position.distance_to(original_target) > 0.01:
        _fail("original pedestrian destination was not restored")
        return

    print("NPC_CROSSING_RUNTIME_OK: unsafe traffic blocks; personal curb cadence staggers rechecks; yielded traffic releases; destination restored")
    agent.queue_free()
    director.queue_free()
    manager.queue_free()
    quit(0)
