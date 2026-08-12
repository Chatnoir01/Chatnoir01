extends SceneTree

func _fail(message: String) -> void:
	push_error("NPC_POLICE_ACTION_REQUEST_FAIL: %s" % message)
	quit(1)

func _initialize() -> void:
	var response := NpcPoliceResponse.new()
	response.configure(8, Vector3.ZERO)
	var request_builder := NpcPoliceActionRequest.new()

	response.report_incident(Vector3(20.0, 0.0, 0.0), 0.45, 12)
	var investigate: Dictionary = request_builder.build(response, Vector3.ZERO)
	if int(investigate.get("action", -1)) != NpcPoliceActionRequest.Action.INVESTIGATE:
		_fail("moderate incident should request investigation")
	if bool(investigate.get("vehicle_support_requested", true)):
		_fail("investigation must not implicitly claim a vehicle")

	response.report_incident(Vector3(30.0, 0.0, 0.0), 0.9, 13)
	var foot: Dictionary = request_builder.build(response, Vector3.ZERO)
	if int(foot.get("action", -1)) != NpcPoliceActionRequest.Action.FOOT_PURSUIT:
		_fail("near pursuit should remain a foot pursuit")

	response.report_incident(Vector3(80.0, 0.0, 0.0), 0.9, 14)
	var support: Dictionary = request_builder.build(response, Vector3.ZERO)
	if int(support.get("action", -1)) != NpcPoliceActionRequest.Action.REQUEST_VEHICLE_SUPPORT:
		_fail("distant pursuit should request external vehicle support")
	if not bool(support.get("vehicle_support_requested", false)):
		_fail("vehicle support flag must be explicit")

	response.update_threat(false, 0.0, 16.0)
	var returning: Dictionary = request_builder.build(response, Vector3(80.0, 0.0, 0.0))
	if int(returning.get("action", -1)) != NpcPoliceActionRequest.Action.RETURN_TO_PATROL:
		_fail("calm police unit should request return to patrol")
	if Vector3(returning.get("target_position", Vector3.ONE)) != Vector3.ZERO:
		_fail("return request must target patrol anchor")

	print("NPC_POLICE_ACTION_REQUEST_OK")
	quit(0)
