extends SceneTree

func _init() -> void:
	var runtime := NpcRuntimeIntegration.new()
	root.add_child(runtime)

	var agent := NpcAgent.new()
	root.add_child(agent)
	agent.set_spawn_context(NpcBehaviorModel.Role.CIVILIAN, 77, Vector3.ZERO)
	agent.set_destination(Vector3(0.0, 0.0, -20.0))

	_assert(agent.get_ambient_animation_tag() == &"walk", "civilian starts in walk")
	var walk_duration := agent.ambient_state.state_duration_seconds(0)
	var state_after_walk := runtime.update_ambient_cadence_for_agent(agent, walk_duration + 0.01, false)
	_assert(state_after_walk != NpcAmbientState.State.WALK, "free-walking civilian autonomously enters a micro-behavior")
	_assert(agent.ambient_state.movement_scale() == 0.0, "micro-behavior pauses locomotion instead of sliding")
	_assert(agent.movement_held, "runtime owns the stationary ambient hold")

	var repeat := NpcAgent.new()
	root.add_child(repeat)
	repeat.set_spawn_context(NpcBehaviorModel.Role.CIVILIAN, 77, Vector3.ZERO)
	repeat.set_destination(Vector3(0.0, 0.0, -20.0))
	var repeat_state := runtime.update_ambient_cadence_for_agent(repeat, walk_duration + 0.01, false)
	_assert(repeat_state == state_after_walk, "same seed and elapsed time produce deterministic ambient cadence")

	var neighbor := NpcAgent.new()
	root.add_child(neighbor)
	neighbor.set_spawn_context(NpcBehaviorModel.Role.CIVILIAN, 78, Vector3.ZERO)
	neighbor.set_destination(Vector3(0.0, 0.0, -20.0))
	var neighbor_duration := neighbor.ambient_state.state_duration_seconds(0)
	var neighbor_state := runtime.update_ambient_cadence_for_agent(neighbor, neighbor_duration + 0.01, false)
	_assert(neighbor_state != state_after_walk, "adjacent seeds avoid synchronized ambient behavior")

	runtime.update_ambient_cadence_for_agent(agent, agent.ambient_state.state_duration_seconds(agent.ambient_state.sequence_index) + 0.01, false)
	_assert(not agent.movement_held or agent.ambient_state.movement_scale() == 0.0, "ambient hold follows the current state rather than sticking")

	agent.update_crossing_context(NpcPedestrianContext.CrossingSignal.RED, true, 5.0)
	var held_state := agent.ambient_state.current_state
	var held_sequence := agent.ambient_state.sequence_index
	runtime.update_ambient_cadence_for_agent(agent, 60.0, false)
	_assert(agent.ambient_state.current_state == held_state, "crossing ownership freezes ambient state changes")
	_assert(agent.ambient_state.sequence_index == held_sequence, "crossing ownership freezes ambient cadence sequence")
	_assert(agent.movement_held, "ambient cleanup never releases a crossing-owned hold")

	print("NPC_AMBIENT_RUNTIME_CADENCE_OK")
	neighbor.queue_free()
	repeat.queue_free()
	agent.queue_free()
	runtime.queue_free()
	quit(0)

func _assert(condition: bool, label: String) -> void:
	if condition:
		return
	push_error("NPC_AMBIENT_RUNTIME_CADENCE_FAIL: %s" % label)
	quit(1)
