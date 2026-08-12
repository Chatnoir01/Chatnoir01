extends SceneTree

func _init() -> void:
	var failures: Array[String] = []
	var first := NpcAmbientState.new()
	var second := NpcAmbientState.new()
	first.configure(101)
	second.configure(202)

	_assert(first.current_state == NpcAmbientState.State.WALK, "initial state must be WALK", failures)
	_assert(first.advance(false, false, 0) != NpcAmbientState.State.BOARDING, "non-transit ambient state must not board", failures)
	first.set_transit_context(true, false)
	_assert(first.current_state == NpcAmbientState.State.WAIT_TRANSIT, "waiting transit must force WAIT_TRANSIT", failures)
	first.set_transit_context(true, true)
	_assert(first.current_state == NpcAmbientState.State.BOARDING, "boarding must force BOARDING", failures)
	first.set_transit_context(false, false)
	_assert(first.current_state == NpcAmbientState.State.WALK, "leaving transit context must resume WALK", failures)

	var duration_a: float = first.state_duration_seconds(3)
	var duration_b: float = second.state_duration_seconds(3)
	_assert(duration_a >= 1.0 and duration_a <= 12.0, "ambient durations must remain human-scale", failures)
	_assert(duration_a != duration_b, "different NPC seeds should desynchronize durations", failures)

	var seen: Dictionary = {}
	for i in range(12):
		var state: int = first.advance(false, false, i)
		seen[state] = true
	_assert(seen.has(NpcAmbientState.State.IDLE), "ambient sequence should include IDLE", failures)
	_assert(seen.size() >= 3, "ambient sequence should have meaningful variation", failures)

	if failures.is_empty():
		print("NPC_AMBIENT_STATE_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("NPC_AMBIENT_STATE_FAIL")
		quit(1)

func _assert(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
