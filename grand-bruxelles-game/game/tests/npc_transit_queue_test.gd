extends SceneTree

func _init() -> void:
	var failures: Array[String] = []
	var queue := NpcTransitQueue.new()
	queue.configure(Vector3(10.0, 0.0, 5.0), Vector3(0.0, 0.0, 1.0), 0.8, 4)

	_assert(queue.join_queue(101) == 0, "first passenger gets first queue slot", failures)
	_assert(queue.join_queue(202) == 1, "second passenger gets second queue slot", failures)
	_assert(queue.join_queue(303) == 2, "third passenger gets third queue slot", failures)
	_assert(queue.join_queue(202) == 1, "duplicate join is stable", failures)

	var p0: Vector3 = queue.position_for(101)
	var p1: Vector3 = queue.position_for(202)
	var p2: Vector3 = queue.position_for(303)
	_assert(p0.distance_to(p1) >= 0.65, "queue spacing avoids overlap", failures)
	_assert(is_equal_approx(p0.x, 10.0), "queue head stays centered on boarding axis", failures)
	_assert(absf(p1.x - 10.0) >= 0.05, "waiting passengers stagger laterally instead of forming a rigid line", failures)
	_assert(absf(p1.x - 10.0) <= 0.12, "lateral queue stagger stays physically small", failures)
	_assert(absf(p2.x - 10.0) <= 0.12, "all queue staggering stays bounded", failures)
	_assert(queue.position_for(202).is_equal_approx(p1), "queue stagger is deterministic for a passenger", failures)
	_assert(is_equal_approx(p1.z, 5.8), "lateral stagger does not change longitudinal queue order", failures)
	_assert(is_equal_approx(p2.z, 6.6), "later passengers keep their longitudinal slot", failures)
	_assert(queue.can_board(101, 2), "queue head can board when capacity exists", failures)
	_assert(not queue.can_board(202, 2), "second passenger waits for queue head", failures)
	_assert(not queue.can_board(101, 0), "no passenger boards when capacity is zero", failures)
	_assert(queue.leave_queue(101), "queue head can leave", failures)
	_assert(queue.position_index_for(202) == 0, "queue compacts after departure", failures)
	_assert(queue.can_board(202, 1), "next passenger becomes eligible", failures)
	_assert(is_equal_approx(queue.position_for(202).x, 10.0), "new queue head recenters for boarding", failures)

	queue.join_queue(404)
	queue.join_queue(505)
	_assert(queue.join_queue(606) == -1, "queue respects configured capacity", failures)

	if failures.is_empty():
		print("NPC_TRANSIT_QUEUE_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("NPC_TRANSIT_QUEUE_FAIL")
		quit(1)

func _assert(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
