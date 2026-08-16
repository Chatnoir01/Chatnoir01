extends SceneTree

func _init() -> void:
	var calm := {"threat": 0.0, "hp": 100.0, "police": false, "distance": 4.0, "zone": "Midi", "combat_enabled": false}
	var threatened := {"threat": 0.8, "hp": 82.0, "police": false, "distance": 1.5, "zone": "Midi", "combat_enabled": false}
	var fighter := {"threat": 0.8, "hp": 82.0, "police": false, "distance": 1.5, "zone": "Midi", "combat_enabled": true, "aggression": 0.8}

	if NpcDialogueRules.allowed_actions(calm).has("fight"):
		_fail("fight must not be allowed without combat rules")
		return
	if not NpcDialogueRules.allowed_actions(threatened).has("flee"):
		_fail("flee must be allowed under strong threat")
		return
	if not NpcDialogueRules.allowed_actions(fighter).has("fight"):
		_fail("fight must be allowed only when combat rules explicitly allow it")
		return

	var valid := NpcDialogueRules.filter_output("action: alert\nline: Hé, doucement là.", threatened)
	if not bool(valid.get("accepted", false)) or String(valid.get("action", "")) != "alert":
		_fail("valid rule-compliant output was rejected")
		return

	var illegal := NpcDialogueRules.filter_output("action: fight\nline: Viens ici.", threatened)
	if bool(illegal.get("accepted", true)) or String(illegal.get("source", "")) != "fallback_rule_reject":
		_fail("out-of-rules fight was not rejected")
		return
	if not NpcDialogueRules.allowed_actions(threatened).has(String(illegal.get("action", ""))):
		_fail("fallback action is outside game rules")
		return

	var disclosure := NpcDialogueRules.filter_output("action: idle\nline: Je suis une IA.", calm)
	if bool(disclosure.get("accepted", true)) or String(disclosure.get("source", "")) != "fallback_line_reject":
		_fail("AI disclosure line was not rejected")
		return

	var malformed := NpcDialogueRules.filter_output("je fais ce que je veux", calm)
	if bool(malformed.get("accepted", true)) or String(malformed.get("source", "")) != "fallback_parse":
		_fail("malformed output did not fall back")
		return

	print("NPC_DIALOGUE_RULES_OK")
	quit(0)

func _fail(message: String) -> void:
	printerr("NPC_DIALOGUE_RULES_FAIL: %s" % message)
	quit(1)
