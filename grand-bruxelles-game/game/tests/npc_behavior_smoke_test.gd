extends SceneTree

func _init() -> void:
	var civilian := NpcBehaviorModel.new()
	civilian.configure(NpcBehaviorModel.Role.CIVILIAN, 42, Vector3.ZERO)
	if civilian.archetype == &"":
		_fail("civilian archetype missing")
		return
	if civilian.state != NpcBehaviorModel.State.IDLE:
		_fail("civilian must start idle")
		return
	civilian.apply_stimulus(25.0, Vector3(4.0, 0.0, 0.0))
	if civilian.state != NpcBehaviorModel.State.AVOIDING:
		_fail("civilian did not avoid moderate stimulus")
		return
	civilian.apply_stimulus(35.0, Vector3(4.0, 0.0, 0.0))
	if civilian.state != NpcBehaviorModel.State.FLEEING:
		_fail("civilian did not flee strong stimulus")
		return
	civilian.calm_down(80.0)
	if civilian.state != NpcBehaviorModel.State.IDLE:
		_fail("civilian did not recover to idle")
		return

	var police := NpcBehaviorModel.new()
	police.configure(NpcBehaviorModel.Role.POLICE, 7, Vector3(10.0, 0.0, 0.0))
	if police.state != NpcBehaviorModel.State.PATROLLING:
		_fail("police must start patrolling")
		return
	police.apply_stimulus(30.0, Vector3(15.0, 0.0, 0.0))
	if police.state != NpcBehaviorModel.State.INVESTIGATING:
		_fail("police did not investigate moderate alert")
		return
	police.apply_stimulus(45.0, Vector3(20.0, 0.0, 0.0))
	if police.state != NpcBehaviorModel.State.PURSUING:
		_fail("police did not pursue high alert")
		return
	police.calm_down(72.0)
	if police.state != NpcBehaviorModel.State.PATROLLING:
		_fail("police did not return to patrol after alert cleared")
		return

	var deterministic_a := NpcBehaviorModel.new()
	var deterministic_b := NpcBehaviorModel.new()
	deterministic_a.configure(NpcBehaviorModel.Role.CIVILIAN, 1234, Vector3.ZERO)
	deterministic_b.configure(NpcBehaviorModel.Role.CIVILIAN, 1234, Vector3.ZERO)
	if deterministic_a.archetype != deterministic_b.archetype or not is_equal_approx(deterministic_a.preferred_speed, deterministic_b.preferred_speed):
		_fail("variation must be deterministic for a stable seed")
		return

	print("NPC_BEHAVIOR_SMOKE_OK")
	quit(0)

func _fail(message: String) -> void:
	printerr("NPC_BEHAVIOR_SMOKE_FAIL: %s" % message)
	quit(1)
