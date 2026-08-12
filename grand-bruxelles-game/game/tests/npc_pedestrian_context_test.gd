extends SceneTree

func _init() -> void:
	var context := NpcPedestrianContext.new()
	context.configure(42, 1.35)

	_assert(context.preferred_speed >= 0.75 and context.preferred_speed <= 1.75, "speed bounds")
	_assert(context.crossing_intent(NpcPedestrianContext.CrossingSignal.GREEN, false, 0.0) == NpcPedestrianContext.PedestrianIntent.CROSS, "green crossing")
	_assert(context.crossing_intent(NpcPedestrianContext.CrossingSignal.RED, true, 99.0) == NpcPedestrianContext.PedestrianIntent.WAIT_AT_CURB, "red signal wait")
	_assert(context.crossing_intent(NpcPedestrianContext.CrossingSignal.NONE, true, 0.0) == NpcPedestrianContext.PedestrianIntent.CROSS, "unsignalized safe gap")
	_assert(context.transit_boarding_dwell_seconds >= 1.5 and context.transit_boarding_dwell_seconds <= 4.5, "boarding dwell stays physically plausible")
	_assert(context.transit_intent(true, true, 0.0) == NpcPedestrianContext.PedestrianIntent.WAIT_FOR_TRANSIT, "fresh arrival cannot board instantly")
	_assert(context.transit_intent(true, true, context.transit_boarding_dwell_seconds - 0.01) == NpcPedestrianContext.PedestrianIntent.WAIT_FOR_TRANSIT, "boarding waits through individual dwell")
	_assert(context.transit_intent(true, true, context.transit_boarding_dwell_seconds) == NpcPedestrianContext.PedestrianIntent.BOARD_TRANSIT, "board available transit after dwell")
	_assert(context.transit_intent(false, false, 15.0) == NpcPedestrianContext.PedestrianIntent.WAIT_FOR_TRANSIT, "wait for transit")
	_assert(context.transit_intent(false, false, context.transit_patience_seconds + 1.0) == NpcPedestrianContext.PedestrianIntent.CONTINUE, "leave after excessive wait")

	var other := NpcPedestrianContext.new()
	other.configure(43, 1.35)
	_assert(context.transit_boarding_dwell_seconds != other.transit_boarding_dwell_seconds, "boarding dwell varies deterministically between pedestrians")
	_assert(context.idle_duration_seconds(0) != other.idle_duration_seconds(0), "seeded idle variation")
	_assert(context.idle_phase_offset_seconds(30.0) >= 0.0 and context.idle_phase_offset_seconds(30.0) < 30.0, "idle phase stays inside cycle")
	_assert(context.idle_phase_offset_seconds(30.0) != other.idle_phase_offset_seconds(30.0), "agents do not share one idle phase")
	_assert(context.idle_phase_offset_seconds(0.0) == 0.0, "zero idle cycle stays stable")
	_assert(context.idle_variant_index(0, 4) >= 0 and context.idle_variant_index(0, 4) < 4, "idle variant stays in bounds")
	_assert(context.idle_variant_index(2, 4) != context.idle_variant_index(3, 4), "idle sequence can vary animation choice")
	_assert(context.idle_variant_index(0, 0) == -1, "empty idle variant set is safe")
	_assert(context.lateral_personal_space_meters(0.0) > context.lateral_personal_space_meters(1.0), "crowd spacing contracts")

	print("NPC_PEDESTRIAN_CONTEXT_OK")
	quit(0)

func _assert(condition: bool, label: String) -> void:
	if condition:
		return
	push_error("NPC_PEDESTRIAN_CONTEXT_FAIL: %s" % label)
	quit(1)
