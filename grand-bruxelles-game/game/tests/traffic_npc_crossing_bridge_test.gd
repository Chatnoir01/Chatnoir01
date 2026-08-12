extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("TRAFFIC_NPC_CROSSING_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var crossing_script: Script = load("res://game/scripts/traffic_crossing_system.gd")
    var bridge_script: Script = load("res://game/scripts/traffic_npc_crossing_bridge.gd")
    var npc_script: Script = load("res://game/tests/fixtures/fake_npc_crossing_agent.gd")
    if crossing_script == null or bridge_script == null or npc_script == null:
        _fail("required script did not load")
        return

    var system: RefCounted = crossing_script.new()
    var roads: Array[Dictionary] = [
        {
            "osm_id": 1,
            "width": 6.0,
            "points": [[-20.0, 0.0], [20.0, 0.0]],
        },
    ]
    var controls: Array = [
        {"osm_id": 100, "kind": "crossing", "point": [0.0, 0.0], "crossing_signals": false},
    ]
    system.call("rebuild", roads, controls)

    var crossing: Dictionary = system.call("get_crossing", 100)
    if crossing.is_empty():
        _fail("crossing descriptor missing")
        return

    var bridge: RefCounted = bridge_script.new()
    bridge.set("minimum_wait_seconds", 0.5)

    var same_side := Node3D.new()
    same_side.set_script(npc_script)
    root.add_child(same_side)
    same_side.global_position = Vector3(0.0, 0.68, -4.0)
    same_side.call("set_destination", Vector3(8.0, 0.68, -5.0))

    bridge.call("update_agents", [same_side], system, null, 0.0)
    if bool(bridge.call("has_assignment", same_side)):
        _fail("same-side destination was incorrectly redirected to crossing")
        return

    var npc := Node3D.new()
    npc.set_script(npc_script)
    root.add_child(npc)
    npc.global_position = Vector3(0.0, 0.68, -4.0)
    var original_target := Vector3(2.0, 0.68, 9.0)
    npc.call("set_destination", original_target)

    bridge.call("update_agents", [npc], system, null, 0.0)
    if not bool(bridge.call("has_assignment", npc)):
        _fail("cross-road destination did not receive crossing assignment")
        return

    var assigned_target: Vector3 = npc.get("behavior").get("target_position")
    var start: Vector3 = crossing.get("start", Vector3.ZERO)
    var finish: Vector3 = crossing.get("finish", Vector3.ZERO)
    var curb := start if npc.global_position.distance_to(start) <= npc.global_position.distance_to(finish) else finish
    var far_side := finish if curb == start else start
    if assigned_target.distance_to(curb) > 0.01:
        _fail("agent was not routed to nearest curb")
        return

    npc.global_position = curb
    bridge.call("update_agents", [npc], system, null, 0.1)
    var waiting_state: Dictionary = system.call("get_crossing_state", 100)
    if int(waiting_state.get("waiting", 0)) != 1:
        _fail("agent did not register as waiting at curb")
        return
    if not bool(npc.get("movement_held")):
        _fail("agent was not held while waiting")
        return

    bridge.call("update_agents", [npc], system, null, 0.4)
    var early_state: Dictionary = system.call("get_crossing_state", 100)
    if int(early_state.get("crossing", 0)) != 0:
        _fail("agent began crossing before minimum wait")
        return

    bridge.call("update_agents", [npc], system, null, 0.8)
    var crossing_state: Dictionary = system.call("get_crossing_state", 100)
    if int(crossing_state.get("waiting", 0)) != 0 or int(crossing_state.get("crossing", 0)) != 1:
        _fail("waiting agent did not transition to active crossing")
        return
    if bool(npc.get("movement_held")):
        _fail("pedestrian hold was not released for crossing")
        return
    var crossing_target: Vector3 = npc.get("behavior").get("target_position")
    if crossing_target.distance_to(far_side) > 0.01:
        _fail("agent was not routed across to opposite curb")
        return

    npc.global_position = far_side
    bridge.call("update_agents", [npc], system, null, 1.2)
    if bool(bridge.call("has_assignment", npc)):
        _fail("assignment was not cleared after crossing")
        return
    if bool(system.call("crossing_requires_stop", 100)):
        _fail("traffic did not resume after real NPC cleared crossing")
        return
    var restored_target: Vector3 = npc.get("behavior").get("target_position")
    if restored_target.distance_to(original_target) > 0.01:
        _fail("original NPC destination was not restored")
        return

    var stats: Dictionary = bridge.call("get_stats")
    if int(stats.get("assigned", -1)) != 0:
        _fail("bridge retained stale assignment")
        return

    print("TRAFFIC_NPC_CROSSING_OK: same-side ignored, curb wait, safe crossing and destination restore passed")
    quit(0)
