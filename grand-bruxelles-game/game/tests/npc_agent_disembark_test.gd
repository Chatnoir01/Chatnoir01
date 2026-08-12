extends SceneTree

func _init() -> void:
	var failures: Array[String] = []
	var stop := NpcTransitStop.new()
	stop.configure(
		"demo-stop",
		Vector3(100.0, 0.0, 50.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 1.0),
		PackedFloat32Array([0.0, 7.0]),
		0.85,
		4
	)

	var agent := NpcAgent.new()
	agent.set_spawn_context(NpcBehaviorModel.Role.CIVILIAN, 71, Vector3(0.0, 0.0, 0.0))
	agent.transit_state = NpcAgent.TransitState.ONBOARD

	var expected_exit: Vector3 = stop.disembark_position_for(1, 2)
	var started: bool = agent.begin_disembark_from_stop(stop, 1, 2)
	_assert(started, "onboard passenger can begin a stop-managed disembark", failures)
	_assert(agent.transit_state == NpcAgent.TransitState.DISEMBARKING, "agent enters disembarking state", failures)
	_assert(agent.get_world_position().distance_to(expected_exit) <= 0.001, "agent uses the stop-provided separated landing position", failures)
	_assert(agent.movement_held, "agent stays held while the exit transition is being completed", failures)

	var duplicate_start: bool = agent.begin_disembark_from_stop(stop, 1, 3)
	_assert(not duplicate_start, "a passenger cannot start a second disembark transition", failures)
	_assert(agent.complete_disembark(), "disembark transition completes cleanly", failures)
	_assert(agent.transit_state == NpcAgent.TransitState.NONE, "completed passenger returns to normal pedestrian state", failures)
	_assert(not agent.movement_held, "completed passenger is released to pedestrian movement", failures)

	var invalid_agent := NpcAgent.new()
	invalid_agent.set_spawn_context(NpcBehaviorModel.Role.CIVILIAN, 72, Vector3.ZERO)
	_assert(not invalid_agent.begin_disembark_from_stop(stop, 0, 0), "non-onboard passenger cannot disembark", failures)
	invalid_agent.transit_state = NpcAgent.TransitState.ONBOARD
	_assert(not invalid_agent.begin_disembark_from_stop(null, 0, 0), "missing stop is rejected", failures)

	if failures.is_empty():
		print("NPC_AGENT_DISEMBARK_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("NPC_AGENT_DISEMBARK_FAIL")
		quit(1)

func _assert(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
