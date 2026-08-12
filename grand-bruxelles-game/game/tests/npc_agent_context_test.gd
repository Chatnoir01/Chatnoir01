extends SceneTree

func _init() -> void:
	var agent := NpcAgent.new()
	root.add_child(agent)
	agent.set_spawn_context(NpcBehaviorModel.Role.CIVILIAN, 77, Vector3.ZERO)

	var initial_appearance: Dictionary = agent.get_appearance_profile()
	_assert(initial_appearance["clothing_base"] != &"police_uniform", "civilian appearance stays civilian")
	_assert(initial_appearance["stature_scale"] >= 0.92 and initial_appearance["stature_scale"] <= 1.08, "stature variation is bounded")
	_assert(agent.get_appearance_profile() == initial_appearance, "appearance is deterministic for a stable spawn context")

	agent.set_weather_context(NpcAppearanceProfile.WeatherContext.RAIN)
	var rain_appearance: Dictionary = agent.get_appearance_profile()
	_assert(rain_appearance["outer_layer"] in [&"rain_jacket", &"hooded_coat", &"light_coat", &"waterproof_shell"], "rain selects weather-appropriate civilian outerwear")
	_assert(rain_appearance["stature_scale"] == initial_appearance["stature_scale"], "weather does not change body proportions")

	agent.set_spawn_context(NpcBehaviorModel.Role.POLICE, 77, Vector3.ZERO)
	var police_appearance: Dictionary = agent.get_appearance_profile()
	_assert(police_appearance["clothing_base"] == &"police_uniform", "police role selects uniform base")
	_assert(police_appearance["outer_layer"] == &"police_rain_layer", "police appearance preserves active weather context")

	agent.set_spawn_context(NpcBehaviorModel.Role.CIVILIAN, 77, Vector3.ZERO)
	var red_intent: int = agent.update_crossing_context(NpcPedestrianContext.CrossingSignal.RED, true, 20.0)
	_assert(red_intent == NpcPedestrianContext.PedestrianIntent.WAIT_AT_CURB, "red crossing intent")
	_assert(agent.movement_held, "red crossing holds movement")

	var green_intent: int = agent.update_crossing_context(NpcPedestrianContext.CrossingSignal.GREEN, false, 0.0)
	_assert(green_intent == NpcPedestrianContext.PedestrianIntent.CROSS, "green crossing intent")
	_assert(not agent.movement_held, "green crossing releases movement")

	var wait_intent: int = agent.update_transit_context(false, false, 10.0)
	_assert(wait_intent == NpcPedestrianContext.PedestrianIntent.WAIT_FOR_TRANSIT, "wait transit intent")
	_assert(agent.movement_held, "transit wait holds movement")

	var board_intent: int = agent.update_transit_context(true, true, 10.0)
	_assert(board_intent == NpcPedestrianContext.PedestrianIntent.BOARD_TRANSIT, "board transit intent")
	_assert(agent.movement_held, "boarding remains externally held")

	agent.clear_pedestrian_hold()
	_assert(agent.pedestrian_intent == NpcPedestrianContext.PedestrianIntent.CONTINUE, "clear intent")
	_assert(not agent.movement_held, "clear hold")

	print("NPC_AGENT_CONTEXT_OK")
	agent.queue_free()
	quit(0)

func _assert(condition: bool, label: String) -> void:
	if condition:
		return
	push_error("NPC_AGENT_CONTEXT_FAIL: %s" % label)
	quit(1)
