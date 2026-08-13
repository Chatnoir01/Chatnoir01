extends SceneTree

func _init() -> void:
	var failures: Array[String] = []
	var agent := NpcAgent.new()
	root.add_child(agent)
	agent.set_spawn_context(NpcBehaviorModel.Role.CIVILIAN, 77, Vector3.ZERO)

	var tags: Dictionary = {}
	for waited_seconds in [10.0, 20.0, 30.0, 40.0]:
		var intent: int = agent.update_transit_context(false, false, waited_seconds)
		_assert(intent == NpcPedestrianContext.PedestrianIntent.WAIT_FOR_TRANSIT, "long wait remains in transit-wait intent", failures)
		tags[agent.get_ambient_animation_tag()] = true
	_assert(tags.size() >= 2, "one traveller should evolve through more than one visible wait pose during a long wait", failures)

	agent.update_transit_context(false, false, 30.0)
	var stable_tag: StringName = agent.get_ambient_animation_tag()
	agent.update_transit_context(false, false, 30.0)
	_assert(agent.get_ambient_animation_tag() == stable_tag, "same elapsed wait must produce the same deterministic pose", failures)

	agent.queue_free()
	if failures.is_empty():
		print("NPC_TRANSIT_WAIT_EVOLUTION_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("NPC_TRANSIT_WAIT_EVOLUTION_FAIL")
		quit(1)

func _assert(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
