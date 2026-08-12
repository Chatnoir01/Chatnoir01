extends SceneTree

func _init() -> void:
	var response := NpcPoliceResponse.new()
	response.configure(17, Vector3(10.0, 0.0, 20.0))

	if response.phase != NpcPoliceResponse.Phase.PATROL:
		_fail("police should start in patrol")
		return

	var incident := Vector3(40.0, 0.0, 60.0)
	response.report_incident(incident, 0.35, 101)
	if response.phase != NpcPoliceResponse.Phase.INVESTIGATE:
		_fail("moderate incident should investigate")
		return
	if response.current_incident_id != 101:
		_fail("incident id should be tracked")
		return

	response.report_incident(incident, 0.95, 101)
	if response.phase != NpcPoliceResponse.Phase.PURSUIT:
		_fail("high severity incident should pursue")
		return
	if not response.should_request_vehicle_support(65.0):
		_fail("long pursuit should request vehicle support through interface")
		return

	response.update_threat(true, 0.55, 0.20)
	if response.phase != NpcPoliceResponse.Phase.PURSUIT:
		_fail("one moderate visible threat sample must not instantly collapse pursuit")
		return
	response.update_threat(true, 0.55, 1.40)
	if response.phase != NpcPoliceResponse.Phase.INVESTIGATE:
		_fail("sustained moderate visible threat should downgrade pursuit to investigate")
		return

	response.report_incident(incident, 0.95, 101)
	response.update_threat(false, 0.0, 7.0)
	if response.phase != NpcPoliceResponse.Phase.DEESCALATE:
		_fail("lost threat should enter de-escalation, not remain in pursuit")
		return

	response.update_threat(false, 0.0, 16.0)
	if response.phase != NpcPoliceResponse.Phase.RETURN_TO_PATROL:
		_fail("sustained calm should return toward patrol")
		return

	response.arrive_at_patrol_anchor()
	if response.phase != NpcPoliceResponse.Phase.PATROL:
		_fail("arrival at patrol anchor should restore patrol")
		return
	if response.current_incident_id != -1:
		_fail("incident should be cleared after return")
		return

	print("NPC_POLICE_RESPONSE_OK")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	print("NPC_POLICE_RESPONSE_FAIL: %s" % message)
	quit(1)
