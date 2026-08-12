extends SceneTree

class FakeGapProvider:
    extends RefCounted
    var safe: bool = false
    var checks: int = 0
    func is_crossing_gap_safe(_crossing_id: int, _agent_position: Vector3) -> bool:
        checks += 1
        return safe

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("TRAFFIC_NPC_CROSSING_BRIDGE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var crossing_script: Script = load("res://game/scripts/traffic_crossing_system.gd")
    var bridge_script: Script = load("res://game/scripts/traffic_npc_crossing_bridge.gd")
    var npc_script: Script = load("res://game/tests/fixtures/fake_npc_crossing_agent.gd")
    if crossing_script == null or bridge_script == null or npc_script == null:
        _fail("crossing system, bridge or fixture did not load")
        return

    var system: RefCounted = crossing_script.new()
    var roads: Array[Dictionary] = [{"osm_id": 1, "width": 6.0, "points": [[-20.0, 0.0], [20.0, 0.0]]}]
    var controls: Array = [{"osm_id": 100, "kind": "crossing", "point": [0.0, 0.0], "crossing_signals": false}]
    system.call("rebuild", roads, controls)
    var crossing: Dictionary = system.call("get_crossing", 100)
    if crossing.is_empty():
        _fail("crossing descriptor missing")
        return

    var bridge: RefCounted = bridge_script.new()
    bridge.set("minimum_wait_seconds", 0.5)
    var gap_provider := FakeGapProvider.new()

    var same_side := Node3D.new()
    same_side.set_script(npc_script)
    root.add_child(same_side)
    same_side.global_position = Vector3(0.0, 0.68, -4.0)
    same_side.call("set_destination", Vector3(8.0, 0.68, -5.0))
    bridge.call("update_agents", [same_side], system, gap_provider, 0.0)
    if bool(bridge.call("has_assignment", same_side)):
        _fail("same-side destination was incorrectly redirected")
        return

    var npc := Node3D.new()
    npc.set_script(npc_script)
    root.add_child(npc)
    npc.global_position = Vector3(0.0, 0.68, -4.0)
    var original_target := Vector3(2.0, 0.68, 9.0)
    npc.call("set_destination", original_target)

    bridge.call("update_agents", [npc], system, gap_provider, 0.0)
    if not bool(bridge.call("has_assignment", npc)):
        _fail("cross-road destination did not receive crossing assignment")
        return

    var start: Vector3 = crossing.get("start", Vector3.ZERO)
    var finish: Vector3 = crossing.get("finish", Vector3.ZERO)
    var curb := start if npc.global_position.distance_to(start) <= npc.global_position.distance_to(finish) else finish
    var far_side := finish if curb == start else start
    var assigned_target: Vector3 = npc.get("behavior").get("target_position")
    if assigned_target.distance_to(curb) > 0.01:
        _fail("NPC was not routed to nearest curb")
        return

    npc.global_position = curb
    bridge.call("update_agents", [npc], system, gap_provider, 0.1)
    var waiting_state: Dictionary = system.call("get_crossing_state", 100)
    if int(waiting_state.get("waiting", 0)) != 1 or not bool(npc.get("movement_held")):
        _fail("NPC did not enter held curb-wait state")
        return

    bridge.call("update_agents", [npc], system, gap_provider, 0.4)
    if gap_provider.checks != 0:
        _fail("traffic gap was polled before the curb recheck cadence elapsed")
        return

    bridge.call("update_agents", [npc], system, gap_provider, 0.8)
    if gap_provider.checks != 1:
        _fail("traffic gap was not polled when the fallback cadence elapsed")
        return
    if int((system.call("get_crossing_state", 100) as Dictionary).get("crossing", 0)) != 0:
        _fail("NPC crossed while traffic gap provider reported unsafe")
        return

    gap_provider.safe = true
    bridge.call("update_agents", [npc], system, gap_provider, 1.0)
    if gap_provider.checks != 1:
        _fail("traffic gap was repolled every frame instead of respecting cadence")
        return
    bridge.call("update_agents", [npc], system, gap_provider, 1.3)
    var active_state: Dictionary = system.call("get_crossing_state", 100)
    if gap_provider.checks != 2:
        _fail("traffic gap was not repolled at the next cadence boundary")
        return
    if int(active_state.get("waiting", 0)) != 0 or int(active_state.get("crossing", 0)) != 1:
        _fail("NPC did not transition from curb wait to crossing after safe gap")
        return
    if bool(npc.get("movement_held")):
        _fail("NPC pedestrian hold remained active while crossing")
        return
    var crossing_target: Vector3 = npc.get("behavior").get("target_position")
    if crossing_target.distance_to(far_side) > 0.01:
        _fail("NPC was not routed to opposite curb")
        return

    npc.global_position = far_side
    bridge.call("update_agents", [npc], system, gap_provider, 1.5)
    if bool(bridge.call("has_assignment", npc)):
        _fail("NPC crossing assignment remained after exit")
        return
    if bool(system.call("crossing_requires_stop", 100)):
        _fail("traffic stop state remained after NPC cleared crossing")
        return
    var restored_target: Vector3 = npc.get("behavior").get("target_position")
    if restored_target.distance_to(original_target) > 0.01:
        _fail("NPC original destination was not restored")
        return

    print("TRAFFIC_NPC_CROSSING_BRIDGE_OK: curb gap checks are cadence-gated; unsafe traffic blocks; safe gap releases; destination restored")
    quit(0)
