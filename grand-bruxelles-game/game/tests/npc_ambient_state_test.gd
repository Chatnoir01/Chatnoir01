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
	var initial_wait_tag: StringName = first.animation_tag()
	first.advance(false, false)
	var next_wait_tag: StringName = first.animation_tag()
	_assert(next_wait_tag != initial_wait_tag, "long transit waits must advance to a new deterministic visible pose instead of freezing forever", failures)
	first.set_transit_context(true, true)
	_assert(first.current_state == NpcAmbientState.State.BOARDING, "boarding must force BOARDING", failures)
	first.set_transit_context(false, false)
	_assert(first.current_state == NpcAmbientState.State.WALK, "leaving transit context must resume WALK", failures)

	var duration_a: float = first.state_duration_seconds(3)
	var duration_b: float = second.state_duration_seconds(3)
	_assert(duration_a >= 1.0 and duration_a <= 12.0, "ambient durations must remain human-scale", failures)
	_assert(duration_a != duration_b, "different NPC seeds should desynchronize durations", failures)

	var wait_first := NpcAmbientState.new()
	var wait_second := NpcAmbientState.new()
	wait_first.configure(101)
	wait_second.configure(202)
	wait_first.set_transit_context(true, false)
	wait_second.set_transit_context(true, false)
	var wait_interval_first: float = wait_first.transit_wait_pose_interval_seconds()
	var wait_interval_second: float = wait_second.transit_wait_pose_interval_seconds()
	_assert(wait_interval_first >= 4.0 and wait_interval_first <= 12.0, "transit wait pose timing must remain human-scale", failures)
	_assert(wait_interval_second >= 4.0 and wait_interval_second <= 12.0, "second transit wait pose timing must remain human-scale", failures)
	_assert(not is_equal_approx(wait_interval_first, wait_interval_second), "different travelers must not share one synchronized wait-pose timer", failures)
	var shorter_interval: float = minf(wait_interval_first, wait_interval_second) + 0.01
	var first_changed: bool = wait_first.advance_transit_wait_pose(shorter_interval)
	var second_changed: bool = wait_second.advance_transit_wait_pose(shorter_interval)
	_assert(first_changed != second_changed, "only the traveler whose own wait timer elapsed should change pose", failures)
	_assert(wait_first.advance_transit_wait_pose(0.0) == false, "zero elapsed time must never advance a wait pose", failures)

	var seen: Dictionary = {}
	for i in range(12):
		var state: int = first.advance(false, false, i)
		seen[state] = true
	_assert(seen.has(NpcAmbientState.State.IDLE), "ambient sequence should include IDLE", failures)
	_assert(not seen.has(NpcAmbientState.State.SOCIAL_PAUSE), "solo ambient sequence must not mime a social interaction", failures)
	_assert(seen.size() >= 3, "ambient sequence should have meaningful variation", failures)

	var social_seen := false
	for i in range(12):
		if first.advance(false, false, i, true) == NpcAmbientState.State.SOCIAL_PAUSE:
			social_seen = true
			break
	_assert(social_seen, "social pause remains available when an interaction partner exists", failures)
	var dense_social_seen := false
	for i in range(12):
		if first.advance(false, true, i, true) == NpcAmbientState.State.SOCIAL_PAUSE:
			dense_social_seen = true
			break
	_assert(not dense_social_seen, "dense flow still suppresses stationary social clusters", failures)

	var wait_tags: Dictionary = {}
	for cycle_index in range(12):
		var tag: StringName = first.transit_wait_animation_tag(1, false, cycle_index)
		wait_tags[tag] = true
	_assert(wait_tags.size() >= 3, "transit waiting should not loop one pose forever", failures)
	var deterministic_a: StringName = first.transit_wait_animation_tag(0, false, 4)
	var deterministic_b: StringName = first.transit_wait_animation_tag(0, false, 4)
	_assert(deterministic_a == deterministic_b, "same NPC wait pose selection must be deterministic", failures)
	var rainy_tags: Dictionary = {}
	for cycle_index in range(12):
		var rainy_tag: StringName = first.transit_wait_animation_tag(2, true, cycle_index)
		rainy_tags[rainy_tag] = true
	_assert(not rainy_tags.has(&"wait_check_phone"), "rain context should avoid prolonged exposed phone-check pose", failures)

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
