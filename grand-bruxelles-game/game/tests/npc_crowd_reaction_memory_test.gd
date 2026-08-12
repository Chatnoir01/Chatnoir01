extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _fail(message: String) -> void:
	push_error("NPC_CROWD_REACTION_MEMORY_FAIL: %s" % message)
	quit(1)

func _run() -> void:
	var reaction := NpcCrowdReaction.new()
	reaction.configure(42)
	var agent := Vector3.ZERO
	var event := Vector3(4.0, 0.0, 0.0)

	var first := reaction.reaction_for_at(agent, event, 1.0, false, 10.0)
	if bool(first.get("suppressed", true)):
		_fail("first exposure must not be suppressed")
		return
	if StringName(first.get("action", &"observe")) != &"flee":
		_fail("strong nearby first exposure should trigger flee")
		return

	var duplicate := reaction.reaction_for_at(agent, event + Vector3(0.8, 0.0, 0.7), 1.0, false, 10.4)
	if not bool(duplicate.get("suppressed", false)):
		_fail("same local event inside cooldown should be suppressed")
		return
	if float(duplicate.get("intensity", 1.0)) != 0.0 or StringName(duplicate.get("action", &"observe")) != &"maintain":
		_fail("suppressed duplicate should maintain current response without a fresh stimulus")
		return

	var after_cooldown := reaction.reaction_for_at(agent, event, 1.0, false, 12.0)
	if bool(after_cooldown.get("suppressed", true)):
		_fail("event should be reactable after cooldown")
		return
	if float(after_cooldown.get("intensity", 1.0)) >= float(first.get("intensity", 0.0)):
		_fail("recent repeated event should be mildly habituated")
		return

	var different_event := reaction.reaction_for_at(agent, Vector3(18.0, 0.0, 0.0), 1.0, false, 12.1)
	if bool(different_event.get("suppressed", true)):
		_fail("different spatial event must not inherit cooldown")
		return

	var recovered := reaction.reaction_for_at(agent, event, 1.0, false, 21.0)
	if bool(recovered.get("suppressed", true)):
		_fail("memory should expire after decay window")
		return
	if absf(float(recovered.get("intensity", 0.0)) - float(first.get("intensity", 0.0))) > 0.001:
		_fail("expired memory should restore full deterministic reaction intensity")
		return
	if reaction.memory_size() > 2:
		_fail("expired reaction memory should be pruned")
		return

	print("NPC_CROWD_REACTION_MEMORY_OK")
	quit(0)
