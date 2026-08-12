extends SceneTree

func _init() -> void:
	var context := NpcPedestrianContext.new()
	context.configure(42, 1.35)

	_assert(context.preferred_speed >= 0.75 and context.preferred_speed <= 1.75, "speed bounds")
	_assert(context.crossing_intent(NpcPedestrianContext.CrossingSignal.GREEN, false, 0.0) == NpcPedestrianContext.PedestrianIntent.CROSS, "green crossing")
	_assert(context.crossing_intent(NpcPedestrianContext.CrossingSignal.RED, true, 99.0) == NpcPedestrianContext.PedestrianIntent.WAIT_AT_CURB, "red signal wait")
	_assert(context.crossing_intent(NpcPedestrianContext.CrossingSignal.NONE, true, 0.0) == NpcPedestrianContext.PedestrianIntent.CROSS, "unsignalized safe gap")
	_assert(context.transit_intent(true, true, 15.0) == NpcPedestrianContext.PedestrianIntent.BOARD_TRANSIT, "board available transit")
	_assert(context.transit_intent(false, false, 15.0) == NpcPedestrianContext.PedestrianIntent.WAIT_FOR_TRANSIT, "wait for transit")
	_assert(context.transit_intent(false, false, context.transit_patience_seconds + 1.0) == NpcPedestrianContext.PedestrianIntent.CONTINUE, "leave after excessive wait")

	var other := NpcPedestrianContext.new()
	other.configure(43, 1.35)
	_assert(context.idle_duration_seconds(0) != other.idle_duration_seconds(0), "seeded idle variation")
	_assert(context.lateral_personal_space_meters(0.0) > context.lateral_personal_space_meters(1.0), "crowd spacing contracts")

	print("NPC_PEDESTRIAN_CONTEXT_OK")
	quit(0)

func _assert(condition: bool, label: String) -> void:
	if condition:
		return
	push_error("NPC_PEDESTRIAN_CONTEXT_FAIL: %s" % label)
	quit(1)
