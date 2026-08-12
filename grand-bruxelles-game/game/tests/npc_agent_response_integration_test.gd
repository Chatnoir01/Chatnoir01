extends SceneTree

func _fail(message: String) -> void:
	push_error("NPC_AGENT_RESPONSE_INTEGRATION_FAIL: %s" % message)
	quit(1)

func _initialize() -> void:
	var police := NpcAgent.new()
	police.set_spawn_context(NpcBehaviorModel.Role.POLICE, 41, Vector3(2.0, 0.0, 3.0))
	var incident := Vector3(80.0, 0.0, -20.0)
	var phase := police.report_police_incident(incident, 0.92, 77)
	if phase != NpcPoliceResponse.Phase.PURSUIT:
		_fail("severe incident must enter PURSUIT")
	if police.behavior.state != NpcBehaviorModel.State.PURSUING:
		_fail("police behavior must mirror PURSUIT")
	if police.behavior.target_position != incident:
		_fail("police pursuit target must be incident position")
	if not police.police_requires_vehicle_support(65.0):
		_fail("long pursuit should request vehicle support through clean interface")

	phase = police.update_police_threat(false, 0.0, 6.0)
	if phase != NpcPoliceResponse.Phase.DEESCALATE:
		_fail("lost threat must de-escalate after calm window")
	phase = police.update_police_threat(false, 0.0, 10.0)
	if phase != NpcPoliceResponse.Phase.RETURN_TO_PATROL:
		_fail("continued calm must return toward patrol anchor")
	if police.behavior.state != NpcBehaviorModel.State.RETURNING:
		_fail("behavior state must mirror patrol return")
	if police.behavior.target_position != Vector3(2.0, 0.0, 3.0):
		_fail("return target must be original patrol anchor")
	police.mark_police_patrol_anchor_reached()
	if police.behavior.state != NpcBehaviorModel.State.PATROLLING:
		_fail("patrol arrival must restore PATROLLING")

	var civilian := NpcAgent.new()
	civilian.set_spawn_context(NpcBehaviorModel.Role.CIVILIAN, 17, Vector3.ZERO)
	var near_reaction := civilian.apply_local_crowd_stimulus(Vector3(2.0, 0.0, 0.0), 1.0, false)
	if StringName(near_reaction.get("action", &"")) != &"flee":
		_fail("strong nearby stimulus must produce flee reaction")
	if civilian.behavior.state != NpcBehaviorModel.State.FLEEING:
		_fail("flee reaction must drive civilian behavior state")

	var sheltered := NpcAgent.new()
	sheltered.set_spawn_context(NpcBehaviorModel.Role.CIVILIAN, 17, Vector3.ZERO)
	var sheltered_reaction := sheltered.apply_local_crowd_stimulus(Vector3(20.0, 0.0, 0.0), 0.7, true)
	if StringName(sheltered_reaction.get("action", &"")) == &"flee":
		_fail("shelter/occlusion should reduce synchronized fleeing")

	print("NPC_AGENT_RESPONSE_INTEGRATION_OK")
	quit(0)
