extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _fail(message: String) -> void:
	push_error("NPC_POLICE_CUSTODY_COORDINATOR_FAIL: %s" % message)
	quit(1)

func _run() -> void:
	var coordinator := NpcPoliceCustodyCoordinator.new()

	var contact_request := {
		"action": NpcPoliceCustodyRequest.Action.CONTACT,
		"subject_id": 40,
		"incident_id": 5,
	}
	if coordinator.apply_request(contact_request) != NpcPoliceCustodyCoordinator.State.CONTACT:
		_fail("contact request should enter CONTACT state")
		return
	coordinator.advance(12.1, false, true, false)
	if coordinator.state != NpcPoliceCustodyCoordinator.State.RELEASED:
		_fail("contact without confirmed legal basis should time out to RELEASED")
		return

	var detained_request := {
		"action": NpcPoliceCustodyRequest.Action.DETAIN,
		"subject_id": 41,
		"incident_id": 6,
	}
	coordinator.apply_request(detained_request)
	if not coordinator.is_movement_restricted():
		_fail("detained state should expose movement restriction")
		return
	coordinator.advance(8.1, true, true, false)
	if not coordinator.reassessment_due:
		_fail("calm compliant detention should become due for reassessment")
		return
	if coordinator.state != NpcPoliceCustodyCoordinator.State.DETAINED:
		_fail("reassessment must not silently release while legal basis remains confirmed")
		return
	coordinator.acknowledge_reassessment()
	if coordinator.reassessment_due:
		_fail("acknowledging reassessment should clear the due flag")
		return
	coordinator.advance(0.1, false, true, false)
	if coordinator.state != NpcPoliceCustodyCoordinator.State.RELEASED:
		_fail("loss of confirmed legal basis should explicitly release detention")
		return

	var transfer_request := {
		"action": NpcPoliceCustodyRequest.Action.REQUEST_ARREST_TRANSFER,
		"subject_id": 42,
		"incident_id": 7,
	}
	coordinator.apply_request(transfer_request)
	if coordinator.state != NpcPoliceCustodyCoordinator.State.TRANSFER_PENDING:
		_fail("authorized transfer request should enter TRANSFER_PENDING")
		return
	if not coordinator.confirm_transfer_complete():
		_fail("transfer completion should be accepted only from pending state")
		return
	if coordinator.state != NpcPoliceCustodyCoordinator.State.TRANSFERRED:
		_fail("completed transfer should retain a brief TRANSFERRED handoff state")
		return
	if coordinator.subject_id != 42 or coordinator.incident_id != 7:
		_fail("transfer handoff should retain subject and incident identity")
		return
	if coordinator.is_movement_restricted():
		_fail("transferred subject should no longer be movement-restricted by this coordinator")
		return
	coordinator.advance(NpcPoliceCustodyCoordinator.TRANSFER_HANDOFF_SECONDS - 0.1, true, true, false)
	if coordinator.state != NpcPoliceCustodyCoordinator.State.TRANSFERRED:
		_fail("transfer handoff should not clear before its continuity window elapses")
		return
	coordinator.advance(0.2, true, true, false)
	if coordinator.state != NpcPoliceCustodyCoordinator.State.CLEAR or coordinator.subject_id != -1:
		_fail("transfer handoff should clear after its continuity window")
		return

	print("NPC_POLICE_CUSTODY_COORDINATOR_OK")
	quit(0)
