extends SceneTree

func _init() -> void:
	var a := NpcDialogueSession.new("npc-midi-001", "Samir", "Saint-Gilles")
	var b := NpcDialogueSession.new("npc-centre-002", "Nora", "Bruxelles-Ville")
	var board := {"threat": 0.2, "hp": 100.0, "police": false, "distance": 2.0, "zone": "Midi"}
	var allowed := NpcDialogueRules.allowed_actions(board)

	a.remember("Salut", {"action": "idle", "line": "Salut, ça va ?"})
	if a.history_size() != 1 or b.history_size() != 0:
		_fail("NPC memories are not isolated")
		return
	var messages_a := a.build_messages("Tu habites où ?", board, allowed)
	var messages_b := b.build_messages("Tu habites où ?", board, allowed)
	if messages_a.size() <= messages_b.size():
		_fail("session A history was not included independently")
		return
	if not String(messages_a[0].get("content", "")).contains("Samir"):
		_fail("session A persona missing")
		return
	if not String(messages_b[0].get("content", "")).contains("Nora"):
		_fail("session B persona missing")
		return
	if String(messages_b[0].get("content", "")).contains("Samir"):
		_fail("persona leaked between NPC sessions")
		return

	for i in range(8):
		a.remember("u%d" % i, {"action": "idle", "line": "l%d" % i})
	if a.history_size() != NpcDialogueSession.MEMORY_TURNS:
		_fail("short memory cap is not enforced")
		return

	print("NPC_DIALOGUE_SESSION_OK")
	quit(0)

func _fail(message: String) -> void:
	printerr("NPC_DIALOGUE_SESSION_FAIL: %s" % message)
	quit(1)
