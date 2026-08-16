extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var client := NpcLlmClient.new()
	client.endpoint = "http://127.0.0.1:9/v1/chat/completions"
	client.timeout_seconds = 1.0
	root.add_child(client)
	var session := NpcDialogueSession.new("npc-offline-001", "Samir", "Saint-Gilles")
	var board := {"threat": 0.75, "hp": 70.0, "police": false, "distance": 2.0, "zone": "Midi", "combat_enabled": false}
	var decision: Dictionary = await client.request_decision(session, "Hé toi !", board)
	if bool(decision.get("accepted", true)):
		_fail("offline path unexpectedly reports LLM acceptance")
		return
	if not String(decision.get("source", "")).begins_with("fallback_"):
		_fail("offline path did not use fallback")
		return
	if not NpcDialogueRules.allowed_actions(board).has(String(decision.get("action", ""))):
		_fail("offline fallback action violates game rules")
		return
	if session.history_size() != 1:
		_fail("offline fallback was not remembered in isolated session")
		return
	print("NPC_LLM_OFFLINE_OK action=%s source=%s line=%s" % [decision.get("action"), decision.get("source"), decision.get("line")])
	quit(0)

func _fail(message: String) -> void:
	printerr("NPC_LLM_OFFLINE_FAIL: %s" % message)
	quit(1)
