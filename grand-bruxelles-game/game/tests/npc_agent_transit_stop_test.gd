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
	var third := NpcAgent.new()
	first.set_spawn_context(NpcBehaviorModel.Role.CIVILIAN, 101, Vector3.ZERO)
	second.set_spawn_context(NpcBehaviorModel.Role.CIVILIAN, 203, Vector3(1.0, 0.0, 0.0))
	third.set_spawn_context(NpcBehaviorModel.Role.CIVILIAN, 307, Vector3(2.0, 0.0, 0.0))

	_assert(first.join_transit_stop(stop, 101) == 0, "first agent joins the stop", failures)
	_assert(second.join_transit_stop(stop, 202) == 0, "second agent joins the same door queue", failures)
	_assert(third.join_transit_stop(stop, 303) == 0, "third agent joins the same door queue", failures)
	_assert(first.transit_state == NpcAgent.TransitState.WAITING, "first agent enters waiting transit state", failures)
	_assert(second.transit_state == NpcAgent.TransitState.WAITING, "second agent enters waiting transit state", failures)
	_assert(third.transit_state == NpcAgent.TransitState.WAITING, "third agent enters waiting transit state", failures)

	var first_wait_tag := first.get_ambient_animation_tag()
	var second_wait_tag := second.get_ambient_animation_tag()
	_assert(first_wait_tag != &"wait_transit", "waiting agents must expose a concrete wait animation instead of one generic synchronized tag", failures)
	_assert(second_wait_tag != &"wait_transit", "every waiting queue slot must expose a concrete wait animation", failures)
	_assert(first_wait_tag != second_wait_tag, "different waiting agents/queue slots should deterministically vary their visible wait behavior", failures)
	_assert(first.get_ambient_animation_tag() == first_wait_tag, "wait animation choice must remain deterministic for the same agent and queue slot", failures)

	var first_target: Vector3 = first.refresh_transit_stop_target()
	var second_target_before: Vector3 = second.refresh_transit_stop_target()
	var third_target_before: Vector3 = third.refresh_transit_stop_target()
	_assert(first_target.distance_to(second_target_before) >= 0.65, "agents target distinct queue slots", failures)
	_assert(second_target_before.distance_to(third_target_before) >= 0.65, "later agents keep distinct queue slots", failures)
	_assert(not first.movement_held, "agent walks toward a distant queue slot instead of freezing immediately", failures)

	var second_delay: float = second.transit_queue_compaction_delay_seconds()
	var third_delay: float = third.transit_queue_compaction_delay_seconds()
	_assert(second_delay >= 0.15 and second_delay <= 0.60, "queue compaction delay stays short and human-scale", failures)
	_assert(third_delay >= 0.15 and third_delay <= 0.60, "every waiting traveler gets a bounded compaction delay", failures)
	_assert(not is_equal_approx(second_delay, third_delay), "different travelers stagger queue compaction timing deterministically", failures)

	stop.vehicle_arrived(PackedInt32Array([2]))
	var second_early: Dictionary = second.request_transit_stop_boarding()
	_assert(not bool(second_early.get("allowed", false)), "second agent cannot skip the queue head", failures)
	var first_board: Dictionary = first.request_transit_stop_boarding()
	_assert(bool(first_board.get("allowed", false)), "queue head receives boarding clearance", failures)
	_assert(first.transit_state == NpcAgent.TransitState.BOARDING, "cleared agent enters boarding state", failures)
	_assert(first.confirm_boarded(), "cleared agent can confirm vehicle entry", failures)
	_assert(first.transit_state == NpcAgent.TransitState.ONBOARD, "confirmed agent becomes onboard", failures)

	_assert(stop.queue_for_door(0).position_index_for(202) == 0, "queue order compacts immediately after the head boards", failures)
	var second_during_compaction: Dictionary = second.request_transit_stop_boarding()
	_assert(not bool(second_during_compaction.get("allowed", false)), "new queue head cannot board while still visually occupying its old slot", failures)
	_assert(String(second_during_compaction.get("reason", "")) == "queue_compacting", "visual compaction denial exposes a stable reason", failures)
	_assert(second.transit_state == NpcAgent.TransitState.WAITING, "compacting traveler stays in waiting state", failures)

	var second_immediate: Vector3 = second.refresh_transit_stop_target(0.0)
	var third_immediate: Vector3 = third.refresh_transit_stop_target(0.0)
	_assert(second_immediate.is_equal_approx(second_target_before), "next traveler does not snap to the freed slot on the same frame", failures)
	_assert(third_immediate.is_equal_approx(third_target_before), "later travelers also keep their old slot on the compaction frame", failures)

	var shorter_delay: float = minf(second_delay, third_delay)
	second.refresh_transit_stop_target(maxf(0.0, shorter_delay - 0.01))
	third.refresh_transit_stop_target(maxf(0.0, shorter_delay - 0.01))
	_assert(second.refresh_transit_stop_target(0.0).is_equal_approx(second_target_before), "second traveler waits through its compaction reaction delay", failures)
	_assert(third.refresh_transit_stop_target(0.0).is_equal_approx(third_target_before), "third traveler waits through its compaction reaction delay", failures)

	if second_delay < third_delay:
		var second_target_after: Vector3 = second.refresh_transit_stop_target(0.02)
		_assert(second_target_after.distance_to(first_target) < 0.01, "shorter-delay traveler advances first into the freed head slot", failures)
		_assert(third.refresh_transit_stop_target(0.0).is_equal_approx(third_target_before), "longer-delay traveler remains in place while the first compaction starts", failures)
		var third_target_after: Vector3 = third.refresh_transit_stop_target(maxf(0.0, third_delay - shorter_delay + 0.02))
		_assert(third_target_after.z <= third_target_before.z - 0.70, "later traveler advances only after its own delay", failures)
	else:
		var third_target_after: Vector3 = third.refresh_transit_stop_target(0.02)
		_assert(third_target_after.z <= third_target_before.z - 0.70, "shorter-delay traveler advances first toward its new slot", failures)
		_assert(second.refresh_transit_stop_target(0.0).is_equal_approx(second_target_before), "longer-delay traveler remains in place while the first compaction starts", failures)
		var second_target_after: Vector3 = second.refresh_transit_stop_target(maxf(0.0, second_delay - shorter_delay + 0.02))
		_assert(second_target_after.distance_to(first_target) < 0.01, "remaining traveler advances after its own delay", failures)

	_assert(stop.queue_for_door(0).position_index_for(202) == 0, "second traveler remains logical queue head after visual compaction", failures)
	_assert(stop.queue_for_door(0).position_index_for(303) == 1, "later passenger keeps queue order during visual compaction", failures)
	var second_board: Dictionary = second.request_transit_stop_boarding()
	_assert(bool(second_board.get("allowed", false)), "new queue head can board once its visual compaction is complete", failures)
	_assert(second.confirm_boarded(), "second cleared agent can confirm vehicle entry", failures)
	_assert(stop.queue_for_door(0).position_index_for(303) == 0, "third traveler becomes queue head after second boards", failures)

	var third_during_compaction: Dictionary = third.request_transit_stop_boarding()
	_assert(not bool(third_during_compaction.get("allowed", false)), "successive queue head also waits for its own visual compaction", failures)
	_assert(String(third_during_compaction.get("reason", "")) == "queue_compacting", "successive compaction uses the same stable denial reason", failures)
	third.refresh_transit_stop_target(third_delay + 0.01)
	var third_full: Dictionary = third.request_transit_stop_boarding()
	_assert(not bool(third_full.get("allowed", false)), "remaining agent waits when vehicle capacity is exhausted", failures)
	_assert(String(third_full.get("reason", "")) == "door_full", "capacity denial is exposed after visual queue movement is complete", failures)

	stop.vehicle_departed()
	_assert(third.leave_transit_queue(), "third agent can leave stop queue cleanly after vehicle departure", failures)
	_assert(stop.queue_size_for_door(0) == 0, "stop reservation is released with the remaining agent", failures)

	first.free()
	second.free()
	third.free()

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
