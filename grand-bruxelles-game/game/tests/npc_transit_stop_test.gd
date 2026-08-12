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

	_assert(stop.door_count() == 2, "stop exposes both vehicle doors", failures)
	_assert(stop.join_waiting_passenger(101) == 0, "first passenger selects door zero", failures)
	_assert(stop.join_waiting_passenger(202) == 1, "second passenger balances to door one", failures)
	_assert(stop.join_waiting_passenger(303) == 0, "third passenger returns to the shortest deterministic queue", failures)
	_assert(stop.join_waiting_passenger(404) == 1, "fourth passenger keeps queues balanced", failures)

	var q0_target: Vector3 = stop.queue_target_for(101)
	var q0_second: Vector3 = stop.queue_target_for(303)
	_assert(q0_target.distance_to(q0_second) >= 0.65, "same-door waiting positions keep personal space", failures)
	_assert(stop.queue_size_for_door(0) == 2 and stop.queue_size_for_door(1) == 2, "door queues stay balanced", failures)

	stop.vehicle_arrived(PackedInt32Array([1, 2]))
	var second_door_attempt: Dictionary = stop.request_boarding(202)
	_assert(bool(second_door_attempt.get("allowed", false)), "head of second door queue can board", failures)
	_assert(int(second_door_attempt.get("door_index", -1)) == 1, "boarding preserves assigned door", failures)
	_assert(stop.remaining_capacity_for_door(1) == 1, "boarding consumes only that door capacity", failures)

	var blocked_non_head: Dictionary = stop.request_boarding(303)
	_assert(not bool(blocked_non_head.get("allowed", false)), "non-head passenger cannot jump the first door queue", failures)

	var first_door_attempt: Dictionary = stop.request_boarding(101)
	_assert(bool(first_door_attempt.get("allowed", false)), "first door head boards while capacity remains", failures)
	_assert(stop.remaining_capacity_for_door(0) == 0, "first door capacity reaches zero", failures)
	var no_capacity: Dictionary = stop.request_boarding(303)
	_assert(not bool(no_capacity.get("allowed", false)), "next first-door passenger waits when that door is full", failures)

	var exit_a: Vector3 = stop.disembark_position_for(1, 0)
	var exit_b: Vector3 = stop.disembark_position_for(1, 1)
	_assert(exit_a.distance_to(exit_b) >= 0.65, "disembarking passengers receive separated landing positions", failures)
	_assert(exit_a.distance_to(stop.queue_target_for(404)) >= 0.65, "disembark lane does not overlap the waiting queue", failures)

	stop.vehicle_departed()
	var after_departure: Dictionary = stop.request_boarding(404)
	_assert(not bool(after_departure.get("allowed", false)), "boarding closes when vehicle departs", failures)

	if failures.is_empty():
		print("NPC_TRANSIT_STOP_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("NPC_TRANSIT_STOP_FAIL")
		quit(1)

func _assert(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
