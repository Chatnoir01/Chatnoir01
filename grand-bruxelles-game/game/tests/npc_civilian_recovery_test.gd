extends SceneTree

const CivilianRecovery = preload("res://game/scripts/npc_civilian_recovery.gd")

func _initialize() -> void:
	var recovery_a := CivilianRecovery.new()
	recovery_a.configure(1701)
	var recovery_b := CivilianRecovery.new()
	recovery_b.configure(1701)
	var start_a: Dictionary = recovery_a.begin_recovery(0.85, 10.0, "transit_hub")
	var start_b: Dictionary = recovery_b.begin_recovery(0.85, 10.0, "transit_hub")
	if start_a != start_b:
		_fail("same civilian seed and incident must recover deterministically")
		return

	var settle := float(start_a.get("settle_seconds", -1.0))
	var recovery_seconds := float(start_a.get("recovery_seconds", -1.0))
	if settle < 1.0 or settle > 7.0:
		_fail("post-incident settle delay must be bounded")
		return
	if recovery_seconds < 4.0 or recovery_seconds > 22.0:
		_fail("recovery duration must be gradual but bounded")
		return

	var held: Dictionary = recovery_a.sample(10.0 + settle * 0.5, true)
	if bool(held.get("resume_routine", true)):
		_fail("an active threat must never resume normal routine")
		return

	var early: Dictionary = recovery_a.sample(10.0 + settle + recovery_seconds * 0.2, false)
	var late: Dictionary = recovery_a.sample(10.0 + settle + recovery_seconds * 0.8, false)
	if float(late.get("alertness", 1.0)) >= float(early.get("alertness", 0.0)):
		_fail("alertness must decrease progressively after danger clears")
		return
	if float(late.get("movement_scale", 0.0)) <= float(early.get("movement_scale", 1.0)):
		_fail("movement must return progressively instead of snapping to full pace")
		return

	var finished: Dictionary = recovery_a.sample(10.0 + settle + recovery_seconds + 0.1, false)
	if not bool(finished.get("resume_routine", false)):
		_fail("civilian must eventually return to routine")
		return
	if float(finished.get("movement_scale", 0.0)) < 0.99:
		_fail("finished recovery must restore normal movement")
		return

	var other := CivilianRecovery.new()
	other.configure(1702)
	var other_start: Dictionary = other.begin_recovery(0.85, 10.0, "transit_hub")
	if is_equal_approx(float(start_a.get("settle_seconds", 0.0)), float(other_start.get("settle_seconds", 0.0))) and is_equal_approx(float(start_a.get("recovery_seconds", 0.0)), float(other_start.get("recovery_seconds", 0.0))):
		_fail("nearby civilians must not all recover on the same timer")
		return

	var civilian := NpcAgent.new()
	civilian.set_spawn_context(NpcBehaviorModel.Role.CIVILIAN, 1701, Vector3.ZERO)
	civilian.set_destination(Vector3(18.0, 0.0, 0.0))
	var routine_target := civilian.behavior.target_position
	civilian.apply_local_crowd_stimulus(Vector3(1.0, 0.0, 0.0), 1.0, false)
	if civilian.behavior.state != NpcBehaviorModel.State.FLEEING:
		_fail("test setup must put civilian into fleeing state")
		return
	var recovery_plan: Dictionary = civilian.begin_civilian_recovery(0.85, 20.0, "commercial_street")
	var total := float(recovery_plan.get("settle_seconds", 0.0)) + float(recovery_plan.get("recovery_seconds", 0.0))
	var agent_finished: Dictionary = civilian.update_civilian_recovery(20.0 + total + 0.2, false)
	if not bool(agent_finished.get("resume_routine", false)):
		_fail("agent integration must finish recovery")
		return
	if civilian.behavior.target_position != routine_target:
		_fail("civilian must resume the pre-incident destination")
		return
	if civilian.behavior.state != NpcBehaviorModel.State.WALKING:
		_fail("civilian must return to walking rather than remain in incident state")
		return

	print("NPC_CIVILIAN_RECOVERY_OK")
	quit(0)

func _fail(message: String) -> void:
	push_error("NPC_CIVILIAN_RECOVERY_FAIL: %s" % message)
	quit(1)
