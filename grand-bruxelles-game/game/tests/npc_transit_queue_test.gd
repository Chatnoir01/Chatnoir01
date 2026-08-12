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
	_assert(p0.distance_to(p1) >= 0.65, "queue spacing avoids overlap", failures)
	_assert(queue.can_board(101, 2), "queue head can board when capacity exists", failures)
	_assert(not queue.can_board(202, 2), "second passenger waits for queue head", failures)
	_assert(not queue.can_board(101, 0), "no passenger boards when capacity is zero", failures)
	_assert(queue.leave_queue(101), "queue head can leave", failures)
	_assert(queue.position_index_for(202) == 0, "queue compacts after departure", failures)
	_assert(queue.can_board(202, 1), "next passenger becomes eligible", failures)

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
