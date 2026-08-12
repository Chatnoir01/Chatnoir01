extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _fail(message: String) -> void:
	push_error("NPC_POLICE_CUSTODY_REQUEST_FAIL: %s" % message)
	quit(1)

func _run() -> void:
	var response := NpcPoliceResponse.new()
	response.configure(9, Vector3.ZERO)
	response.report_incident(Vector3(8.0, 0.0, 0.0), 0.72, 81)
	var request := NpcPoliceCustodyRequest.new()

	var contact := request.build(response, 12, Vector3(8.0, 0.0, 0.0), false, false, true, false)
	if int(contact.get("action", -1)) != NpcPoliceCustodyRequest.Action.CONTACT:
		_fail("missing legal basis must remain a contact-only request")
		return
	if bool(contact.get("additional_support_requested", true)):
		_fail("calm compliant contact should not request additional support")
		return

	var detained := request.build(response, 12, Vector3(8.0, 0.0, 0.0), true, false, true, false)
	if int(detained.get("action", -1)) != NpcPoliceCustodyRequest.Action.DETAIN:
		_fail("confirmed basis without arrest authorization should request detention only")
		return

	var transfer := request.build(response, 12, Vector3(8.0, 0.0, 0.0), true, true, false, true)
	if int(transfer.get("action", -1)) != NpcPoliceCustodyRequest.Action.REQUEST_ARREST_TRANSFER:
		_fail("explicit arrest authorization should request external transfer")
		return
	if not bool(transfer.get("additional_support_requested", false)):
		_fail("non-compliant immediate-risk transfer should request additional support")
		return

	response.update_threat(false, 0.0, 30.0)
	var inactive := request.build(response, 12, Vector3.ZERO, true, true, false, true)
	if int(inactive.get("action", -1)) != NpcPoliceCustodyRequest.Action.NONE:
		_fail("patrol/return state must not create a new custody action")
		return

	var release := request.build_release(12, Vector3(1.0, 0.0, 2.0), 81)
	if int(release.get("action", -1)) != NpcPoliceCustodyRequest.Action.RELEASE:
		_fail("release request should be explicit")
		return
	if bool(release.get("additional_support_requested", true)):
		_fail("release should clear support request")
		return

	print("NPC_POLICE_CUSTODY_REQUEST_OK")
	quit(0)