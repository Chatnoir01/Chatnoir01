extends SceneTree

func _init() -> void:
	var failures: Array[String] = []
	var stop := NpcTransitStop.new()
	stop.configure("door-arrival", Vector3(20.0, 0.0, 10.0), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), PackedFloat32Array([0.0]), 0.85, 1)
	var agent := NpcAgent.new()
	agent.set_spawn_context(NpcBehaviorModel.Role.CIVILIAN, 101, Vector3.ZERO)
	_assert(agent.join_transit_stop(stop, 101) == 0, "agent joins transit stop", failures)
	stop.vehicle_arrived(PackedInt32Array([1]))
	var clearance := agent.request_transit_stop_boarding()
	_assert(bool(clearance.get("allowed", false)), "queue head receives boarding clearance", failures)
	_assert(agent.transit_state == NpcAgent.TransitState.BOARDING, "cleared agent enters boarding state", failures)
	var door_position: Variant = clearance.get("door_position", Vector3.ZERO)
	_assert(door_position is Vector3, "clearance exposes physical door position", failures)
	_assert(not agent.confirm_boarded(), "agent cannot become onboard before reaching the door", failures)
	_assert(agent.transit_state == NpcAgent.TransitState.BOARDING, "agent remains boarding while approaching door", failures)
	if door_position is Vector3:
		agent.position = door_position as Vector3
	_assert(agent.confirm_boarded(), "agent becomes onboard after reaching door", failures)
	agent.free()
	if failures.is_empty():
		print("NPC_AGENT_TRANSIT_DOOR_ARRIVAL_OK")
		quit(0)
	for failure in failures:
		push_error(failure)
	print("NPC_AGENT_TRANSIT_DOOR_ARRIVAL_FAIL")
	quit(1)

func _assert(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
