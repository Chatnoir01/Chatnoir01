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

	# Recovery must carry an immutable snapshot of the exact pre-incident
	# routine so the live agent can restore transit waiting or ambient activity
	# instead of only recovering a geometric destination.
	var activity_recovery := CivilianRecovery.new()
	activity_recovery.configure(2201)
	var routine_snapshot := {
		"activity_kind": &"transit_wait",
		"transit_state": NpcAgent.TransitState.WAITING,
		"passenger_id": 42,
		"ambient_state": NpcAmbientState.State.WAIT_TRANSIT,
		"ambient_sequence_index": 7,
		"routine_target": Vector3(4.0, 0.0, -9.0),
	}
	var activity_plan: Dictionary = activity_recovery.begin_recovery(0.6, 40.0, "transit_hub", routine_snapshot)
	if not bool(activity_plan.get("routine_snapshot_captured", false)):
		_fail("recovery plan must report that a pre-incident routine snapshot was captured")
		return
	# Mutating the caller-owned dictionary after begin_recovery must not corrupt
	# the stored recovery handoff.
	routine_snapshot["passenger_id"] = 99
	routine_snapshot["activity_kind"] = &"corrupted"
	var activity_total := float(activity_plan.get("settle_seconds", 0.0)) + float(activity_plan.get("recovery_seconds", 0.0))
	var activity_held: Dictionary = activity_recovery.sample(40.0 + activity_total * 0.4, true)
	if activity_held.has("routine_snapshot"):
		_fail("routine snapshot must not be exposed while the threat remains active")
		return
	var activity_finished: Dictionary = activity_recovery.sample(40.0 + activity_total + 0.2, false)
	var restored_snapshot_value: Variant = activity_finished.get("routine_snapshot", null)
	if not (restored_snapshot_value is Dictionary):
		_fail("finished recovery must return the captured routine snapshot")
		return
	var restored_snapshot: Dictionary = restored_snapshot_value as Dictionary
	if StringName(restored_snapshot.get("activity_kind", &"")) != &"transit_wait":
		_fail("recovery must preserve the original activity kind")
		return
	if int(restored_snapshot.get("passenger_id", -1)) != 42:
		_fail("recovery snapshot must be isolated from caller mutation")
		return
	if int(restored_snapshot.get("ambient_state", -1)) != NpcAmbientState.State.WAIT_TRANSIT:
		_fail("recovery must preserve transit ambient state")
		return
	if int(restored_snapshot.get("ambient_sequence_index", -1)) != 7:
		_fail("recovery must preserve ambient sequence progress")
		return
	if restored_snapshot.get("routine_target", Vector3.ZERO) != Vector3(4.0, 0.0, -9.0):
		_fail("recovery must preserve the exact routine target")
		return

	print("NPC_CIVILIAN_RECOVERY_OK")
	quit(0)

func _fail(message: String) -> void:
	push_error("NPC_CIVILIAN_RECOVERY_FAIL: %s" % message)
	quit(1)
