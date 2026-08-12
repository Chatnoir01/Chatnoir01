extends SceneTree

func _init() -> void:
	var civilian := NpcAgent.new()
	civilian.set_spawn_context(NpcBehaviorModel.Role.CIVILIAN, 31, Vector3(3.0, 0.0, 0.0))
	var crowd_result := civilian.react_to_local_crowd_event(Vector3.ZERO, 1.0, false)
	if crowd_result["action"] != &"flee":
		_fail("near civilian should receive fleeing crowd reaction")
		return
	if civilian.behavior.state != NpcBehaviorModel.State.FLEEING:
		_fail("crowd reaction should drive civilian behavior state")
		return

	var officer := NpcAgent.new()
	officer.set_spawn_context(NpcBehaviorModel.Role.POLICE, 9, Vector3(10.0, 0.0, 20.0))
	var incident := Vector3(45.0, 0.0, 60.0)
	if officer.report_police_incident(incident, 0.9, 77) != NpcPoliceResponse.Phase.PURSUIT:
		_fail("police agent should enter pursuit through response model")
		return
	if not officer.police_should_request_vehicle_support(70.0):
		_fail("police agent should expose vehicle support request without traffic coupling")
		return
	if officer.update_police_threat(false, 0.0, 8.0) != NpcPoliceResponse.Phase.DEESCALATE:
		_fail("police agent should de-escalate when threat is gone")
		return
	if officer.update_police_threat(false, 0.0, 16.0) != NpcPoliceResponse.Phase.RETURN_TO_PATROL:
		_fail("police agent should return toward patrol after sustained calm")
		return

	civilian.free()
	officer.free()
	print("NPC_AGENT_RESPONSE_INTEGRATION_OK")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	print("NPC_AGENT_RESPONSE_INTEGRATION_FAIL: %s" % message)
	quit(1)
