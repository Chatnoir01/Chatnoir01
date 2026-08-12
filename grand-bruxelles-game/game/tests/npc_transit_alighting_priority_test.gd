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

	_assert(stop.join_waiting_passenger(101, 0) == 0, "passenger 101 joins door 0", failures)
	_assert(stop.join_waiting_passenger(202, 1) == 1, "passenger 202 joins door 1", failures)

	stop.vehicle_arrived(PackedInt32Array([2, 2]), PackedInt32Array([2, 0]))
	var blocked: Dictionary = stop.request_boarding(101)
	_assert(not bool(blocked.get("allowed", false)), "boarding is held while passengers still need to alight at that door", failures)
	_assert(String(blocked.get("reason", "")) == "allow_disembark_first", "boarding exposes the alighting-priority reason", failures)

	var other_door: Dictionary = stop.request_boarding(202)
	_assert(bool(other_door.get("allowed", false)), "a separate door without alighting passengers can board independently", failures)

	_assert(stop.pending_alighting_for_door(0) == 2, "door 0 tracks two pending alighting passengers", failures)
	_assert(stop.register_disembarked(0), "first alighting passenger is registered", failures)
	_assert(stop.pending_alighting_for_door(0) == 1, "one alighting passenger remains", failures)
	_assert(not bool(stop.request_boarding(101).get("allowed", false)), "boarding remains blocked until the final alighting passenger clears", failures)
	_assert(stop.register_disembarked(0), "second alighting passenger is registered", failures)
	_assert(stop.pending_alighting_for_door(0) == 0, "alighting queue clears", failures)

	var allowed: Dictionary = stop.request_boarding(101)
	_assert(bool(allowed.get("allowed", false)), "boarding opens once alighting is complete", failures)
	_assert(stop.remaining_capacity_for_door(0) == 1, "boarding consumes only one place after alighting", failures)

	stop.vehicle_departed()
	_assert(stop.pending_alighting_for_door(0) == 0, "departure clears alighting state", failures)
	_assert(not stop.register_disembarked(0), "departed stop rejects stale alighting events", failures)

	if failures.is_empty():
		print("NPC_TRANSIT_ALIGHTING_PRIORITY_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("NPC_TRANSIT_ALIGHTING_PRIORITY_FAIL")
		quit(1)

func _assert(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
