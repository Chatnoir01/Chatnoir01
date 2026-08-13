extends SceneTree

func _init() -> void:
	var failures: Array[String] = []
	var stop := NpcTransitStop.new()
	stop.configure(
		"agent-stop",
		Vector3(20.0, 0.0, 10.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 1.0),
		PackedFloat32Array([0.0]),
		0.85,
		4
	)

	var first := NpcAgent.new()
	var second := NpcAgent.new()
	first.set_spawn_context(NpcBehaviorModel.Role.CIVILIAN, 101, Vector3.ZERO)
	second.set_spawn_context(NpcBehaviorModel.Role.CIVILIAN, 203, Vector3(1.0, 0.0, 0.0))

	_assert(first.join_transit_stop(stop, 101) == 0, "first agent joins the stop", failures)
	_assert(second.join_transit_stop(stop, 202) == 0, "second agent joins the same door queue", failures)
	_assert(first.transit_state == NpcAgent.TransitState.WAITING, "first agent enters waiting transit state", failures)
	_assert(second.transit_state == NpcAgent.TransitState.WAITING, "second agent enters waiting transit state", failures)

	var first_wait_tag := first.get_ambient_animation_tag()
	var second_wait_tag := second.get_ambient_animation_tag()
	_assert(first_wait_tag != &"wait_transit", "waiting agents must expose a concrete wait animation instead of one generic synchronized tag", failures)
	_assert(second_wait_tag != &"wait_transit", "every waiting queue slot must expose a concrete wait animation", failures)
	_assert(first_wait_tag != second_wait_tag, "different waiting agents/queue slots should deterministically vary their visible wait behavior", failures)
	_assert(first.get_ambient_animation_tag() == first_wait_tag, "wait animation choice must remain deterministic for the same agent and queue slot", failures)

	var first_target: Vector3 = first.refresh_transit_stop_target()
	var second_target_before: Vector3 = second.refresh_transit_stop_target()
	_assert(first_target.distance_to(second_target_before) >= 0.65, "agents target distinct queue slots", failures)
	_assert(not first.movement_held, "agent walks toward a distant queue slot instead of freezing immediately", failures)

	stop.vehicle_arrived(PackedInt32Array([1]))
	var second_early: Dictionary = second.request_transit_stop_boarding()
	_assert(not bool(second_early.get("allowed", false)), "second agent cannot skip the queue head", failures)
	var first_board: Dictionary = first.request_transit_stop_boarding()
	_assert(bool(first_board.get("allowed", false)), "queue head receives boarding clearance", failures)
	_assert(first.transit_state == NpcAgent.TransitState.BOARDING, "cleared agent enters boarding state", failures)
	_assert(first.confirm_boarded(), "cleared agent can confirm vehicle entry", failures)
	_assert(first.transit_state == NpcAgent.TransitState.ONBOARD, "confirmed agent becomes onboard", failures)

	var second_target_after: Vector3 = second.refresh_transit_stop_target()
	_assert(second_target_after.distance_to(first_target) < 0.01, "remaining queue compacts to the freed front slot", failures)
	var second_full: Dictionary = second.request_transit_stop_boarding()
	_assert(not bool(second_full.get("allowed", false)), "remaining agent waits when vehicle capacity is exhausted", failures)
	_assert(String(second_full.get("reason", "")) == "door_full", "capacity denial exposes a stable reason", failures)

	stop.vehicle_departed()
	_assert(second.leave_transit_queue(), "agent can leave stop queue cleanly after vehicle departure", failures)
	_assert(stop.queue_size_for_door(0) == 0, "stop reservation is released with the agent", failures)

	first.free()
	second.free()

	if failures.is_empty():
		print("NPC_AGENT_TRANSIT_STOP_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("NPC_AGENT_TRANSIT_STOP_FAIL")
		quit(1)

func _assert(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
