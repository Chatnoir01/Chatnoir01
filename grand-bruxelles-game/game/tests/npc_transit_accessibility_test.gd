extends SceneTree

func _init() -> void:
	var failures: Array[String] = []
	var stop := NpcTransitStop.new()
	stop.configure(
		"accessible-stop",
		Vector3.ZERO,
		Vector3(1.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 1.0),
		PackedFloat32Array([0.0, 5.5, 11.0]),
		0.85,
		4,
		PackedInt32Array([1])
	)

	_assert(not stop.is_step_free_door(0), "door 0 is not marked step-free", failures)
	_assert(stop.is_step_free_door(1), "door 1 is marked step-free", failures)
	_assert(not stop.is_step_free_door(2), "door 2 is not marked step-free", failures)

	var assigned: int = stop.join_waiting_passenger(301, 0, true)
	_assert(assigned == 1, "step-free passenger ignores an inaccessible preferred door", failures)
	_assert(stop.assigned_door_for(301) == 1, "step-free passenger remains assigned to the accessible door", failures)

	var ordinary: int = stop.join_waiting_passenger(302, 0, false)
	_assert(ordinary == 0, "ordinary passenger can still use the preferred regular door", failures)

	var no_access := NpcTransitStop.new()
	no_access.configure(
		"legacy-stop",
		Vector3.ZERO,
		Vector3(1.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 1.0),
		PackedFloat32Array([0.0, 5.0]),
		0.85,
		4,
		PackedInt32Array()
	)
	_assert(no_access.join_waiting_passenger(401, -1, true) == -1, "step-free request is rejected when no compatible door is declared", failures)

	if failures.is_empty():
		print("NPC_TRANSIT_ACCESSIBILITY_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("NPC_TRANSIT_ACCESSIBILITY_FAIL")
		quit(1)

func _assert(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
