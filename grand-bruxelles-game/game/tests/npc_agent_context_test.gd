extends SceneTree

func _init() -> void:
	var agent := NpcAgent.new()
	root.add_child(agent)
	agent.set_spawn_context(NpcBehaviorModel.Role.CIVILIAN, 77, Vector3.ZERO)

	var expected_civilian_speed: float = _expected_civilian_speed(77)
	_assert(is_equal_approx(agent.behavior.preferred_speed, expected_civilian_speed), "civilian runtime uses deterministic contextual walking pace")
	_assert(is_equal_approx(agent.pedestrian_context.preferred_speed, expected_civilian_speed), "pedestrian context and runtime share one walking pace")
	var second_agent := NpcAgent.new()
	root.add_child(second_agent)
	second_agent.set_spawn_context(NpcBehaviorModel.Role.CIVILIAN, 78, Vector3.ZERO)
	_assert(absf(second_agent.behavior.preferred_speed - agent.behavior.preferred_speed) > 0.01, "nearby civilians do not receive synchronized walking speeds")

	var initial_appearance: Dictionary = agent.get_appearance_profile()
	_assert(initial_appearance["clothing_base"] != &"police_uniform", "civilian appearance stays civilian")
	_assert(initial_appearance["stature_scale"] >= 0.92 and initial_appearance["stature_scale"] <= 1.08, "stature variation is bounded")
	_assert(agent.get_appearance_profile() == initial_appearance, "appearance is deterministic for a stable spawn context")
	_assert(agent.get_ambient_animation_tag() == &"walk", "ambient state begins in walk")
	var ambient_state: int = agent.advance_ambient_state(false, 1)
	_assert(ambient_state != NpcAmbientState.State.BOARDING, "ambient state cannot board outside transit")

	agent.set_weather_context(NpcAppearanceProfile.WeatherContext.RAIN)
	var rain_appearance: Dictionary = agent.get_appearance_profile()
	_assert(rain_appearance["outer_layer"] in [&"rain_jacket", &"hooded_coat", &"light_coat", &"waterproof_shell"], "rain selects weather-appropriate civilian outerwear")
	_assert(rain_appearance["stature_scale"] == initial_appearance["stature_scale"], "weather does not change body proportions")

	agent.set_spawn_context(NpcBehaviorModel.Role.POLICE, 77, Vector3.ZERO)
	var police_appearance: Dictionary = agent.get_appearance_profile()
	_assert(police_appearance["clothing_base"] == &"police_uniform", "police role selects uniform base")
	_assert(police_appearance["outer_layer"] == &"police_rain_layer", "police appearance preserves active weather context")
	_assert(is_equal_approx(agent.pedestrian_context.preferred_speed, agent.behavior.preferred_speed), "police context preserves patrol speed ownership")

	agent.set_spawn_context(NpcBehaviorModel.Role.CIVILIAN, 77, Vector3.ZERO)
	var red_intent: int = agent.update_crossing_context(NpcPedestrianContext.CrossingSignal.RED, true, 20.0)
	_assert(red_intent == NpcPedestrianContext.PedestrianIntent.WAIT_AT_CURB, "red crossing intent")
	_assert(agent.movement_held, "red crossing holds movement")

	var green_intent: int = agent.update_crossing_context(NpcPedestrianContext.CrossingSignal.GREEN, false, 0.0)
	_assert(green_intent == NpcPedestrianContext.PedestrianIntent.CROSS, "green crossing intent")
	_assert(not agent.movement_held, "green crossing releases movement")

	var queue := NpcTransitQueue.new()
	queue.configure(Vector3(2.0, 0.0, 3.0), Vector3(0.0, 0.0, 1.0), 0.8, 3)
	var blocker := NpcAgent.new()
	root.add_child(blocker)
	blocker.set_spawn_context(NpcBehaviorModel.Role.CIVILIAN, 88, Vector3.ZERO)
	_assert(blocker.join_transit_queue(queue, 8800) == 0, "first passenger joins queue head")
	_assert(agent.join_transit_queue(queue, 7700) == 1, "second passenger joins second slot")
	_assert(agent.get_transit_queue_target() == queue.position_for(7700), "agent exposes assigned queue slot target")
	_assert(not agent.can_board_from_queue(2), "non-head passenger cannot board")
	_assert(blocker.can_board_from_queue(2), "queue head can board")
	_assert(blocker.leave_transit_queue(), "queue head leaves after boarding")
	_assert(agent.can_board_from_queue(1), "next passenger becomes boardable after compaction")

	var wait_intent: int = agent.update_transit_context(false, false, 10.0)
	_assert(wait_intent == NpcPedestrianContext.PedestrianIntent.WAIT_FOR_TRANSIT, "wait transit intent")
	_assert(agent.transit_state == NpcAgent.TransitState.WAITING, "waiting state is tracked")
	_assert(agent.movement_held, "transit wait holds movement")
	_assert(agent.get_ambient_animation_tag() == &"wait_transit", "waiting state exposes transit animation")

	var board_intent: int = agent.update_transit_context(true, true, 10.0)
	_assert(board_intent == NpcPedestrianContext.PedestrianIntent.BOARD_TRANSIT, "board transit intent")
	_assert(agent.transit_state == NpcAgent.TransitState.BOARDING, "boarding state is tracked")
	_assert(agent.movement_held, "boarding remains externally held")
	_assert(agent.get_ambient_animation_tag() == &"boarding", "boarding state exposes boarding animation")
	_assert(agent.confirm_boarded(), "boarding can be confirmed")
	_assert(agent.transit_state == NpcAgent.TransitState.ONBOARD, "onboard state is tracked")
	_assert(agent.movement_held, "onboard state keeps movement held")
	_assert(not agent.confirm_boarded(), "duplicate boarding confirmation is rejected")

	var exit_position := Vector3(4.0, 0.0, -3.0)
	_assert(agent.begin_disembark(exit_position), "onboard passenger can begin disembarking")
	_assert(agent.transit_state == NpcAgent.TransitState.DISEMBARKING, "disembarking state is tracked")
	_assert(agent.get_world_position() == exit_position, "disembarking uses external vehicle exit position")
	_assert(agent.movement_held, "disembarking remains held until external completion")
	_assert(agent.complete_disembark(), "disembarking can complete")
	_assert(agent.transit_state == NpcAgent.TransitState.NONE, "transit state clears after disembarking")
	_assert(agent.pedestrian_intent == NpcPedestrianContext.PedestrianIntent.CONTINUE, "pedestrian intent clears after disembarking")
	_assert(not agent.movement_held, "movement releases after disembarking")
	_assert(agent.get_ambient_animation_tag() == &"walk", "ambient state resumes walk after disembarking")
	_assert(not agent.complete_disembark(), "duplicate disembark completion is rejected")

	agent.clear_pedestrian_hold()
	_assert(agent.pedestrian_intent == NpcPedestrianContext.PedestrianIntent.CONTINUE, "clear intent")
	_assert(not agent.movement_held, "clear hold")

	print("NPC_AGENT_CONTEXT_OK")
	blocker.queue_free()
	second_agent.queue_free()
	agent.queue_free()
	quit(0)

func _expected_civilian_speed(seed_value: int) -> float:
	var normalized: float = float(abs(seed_value * 37) % 1000) / 1000.0
	var base_speed: float = lerpf(1.0, 1.55, normalized)
	var pace_mix: int = absi(seed_value * 1103515245 + 11 * 12345)
	var pace_factor: float = lerpf(0.88, 1.12, float(pace_mix % 10000) / 10000.0)
	return clampf(base_speed * pace_factor, 0.75, 1.75)

func _assert(condition: bool, label: String) -> void:
	if condition:
		return
	push_error("NPC_AGENT_CONTEXT_FAIL: %s" % label)
	quit(1)
