extends SceneTree

func _init() -> void:
	var crowd := NpcCrowdReaction.new()
	crowd.configure(23)

	var near_direct := crowd.reaction_for(Vector3(4.0, 0.0, 0.0), Vector3.ZERO, 1.0, false)
	crowd.clear_memory()
	var farther_direct := crowd.reaction_for(Vector3(18.0, 0.0, 0.0), Vector3.ZERO, 1.0, false)
	if float(near_direct["intensity"]) <= float(farther_direct["intensity"]):
		_fail("reaction intensity should attenuate with distance")
		return
	if near_direct["action"] != &"flee":
		_fail("near high-intensity civilian should flee")
		return

	crowd.clear_memory()
	var sheltered := crowd.reaction_for(Vector3(8.0, 0.0, 0.0), Vector3.ZERO, 0.8, true)
	crowd.clear_memory()
	var exposed := crowd.reaction_for(Vector3(8.0, 0.0, 0.0), Vector3.ZERO, 0.8, false)
	if float(sheltered["intensity"]) >= float(exposed["intensity"]):
		_fail("occlusion/shelter should reduce propagated reaction")
		return

	crowd.clear_memory()
	var distant := crowd.reaction_for(Vector3(45.0, 0.0, 0.0), Vector3.ZERO, 0.6, false)
	if distant["action"] == &"flee":
		_fail("distant moderate stimulus should not synchronize a mass flee")
		return

	crowd.clear_memory()
	var repeat_a := crowd.reaction_for(Vector3(12.0, 0.0, 3.0), Vector3.ZERO, 0.7, false)
	crowd.clear_memory()
	var repeat_b := crowd.reaction_for(Vector3(12.0, 0.0, 3.0), Vector3.ZERO, 0.7, false)
	if repeat_a != repeat_b:
		_fail("same seed/context must stay deterministic when reaction memory is reset")
		return

	print("NPC_CROWD_REACTION_OK")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	print("NPC_CROWD_REACTION_FAIL: %s" % message)
	quit(1)