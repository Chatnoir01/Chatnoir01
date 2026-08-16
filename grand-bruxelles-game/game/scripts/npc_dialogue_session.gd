class_name NpcDialogueSession
extends RefCounted

const MEMORY_TURNS := 4

var npc_id: String = ""
var npc_name: String = ""
var neighborhood: String = "Bruxelles"
var _history: Array[Dictionary] = []

func _init(id: String = "", display_name: String = "", home_neighborhood: String = "Bruxelles") -> void:
	configure(id, display_name, home_neighborhood)

func configure(id: String, display_name: String, home_neighborhood: String) -> void:
	npc_id = id.strip_edges()
	npc_name = display_name.strip_edges()
	neighborhood = home_neighborhood.strip_edges()
	if npc_name.is_empty():
		npc_name = "Bruxellois"
	if neighborhood.is_empty():
		neighborhood = "Bruxelles"
	_history.clear()

func build_messages(player_text: String, blackboard: Dictionary, allowed: PackedStringArray) -> Array[Dictionary]:
	var messages: Array[Dictionary] = []
	messages.append({"role": "system", "content": _system_prompt(allowed)})
	for turn in _history:
		messages.append({"role": "user", "content": String(turn.get("user", ""))})
		messages.append({"role": "assistant", "content": String(turn.get("assistant", ""))})
	messages.append({
		"role": "user",
		"content": "%s\n\nBLACKBOARD JEU (lecture seule): %s" % [player_text.strip_edges(), _blackboard_text(blackboard)],
	})
	return messages

func remember(player_text: String, decision: Dictionary) -> void:
	var assistant_text := "action: %s\nline: %s" % [
		String(decision.get("action", "idle")),
		String(decision.get("line", "")),
	]
	_history.append({
		"user": player_text.strip_edges(),
		"assistant": assistant_text,
	})
	while _history.size() > MEMORY_TURNS:
		_history.pop_front()

func history_size() -> int:
	return _history.size()

func _system_prompt(allowed: PackedStringArray) -> String:
	return """Tu es %s, habitant de Bruxelles.
Tu n'es pas une IA. Tu ne le sais pas. Tu ne le dis jamais.
Tu as un corps, des peurs, un quartier: %s.
Réponds court, oral, naturel, en français.
Si on parle d'IA, modèle ou prompt, tu ne comprends pas.
Les règles du jeu commandent. Tu proposes uniquement une action autorisée.
Actions autorisées maintenant: %s
Réponds exactement sur deux lignes, sans texte avant ni après:
action: <action autorisée>
line: <phrase courte FR>""" % [npc_name, neighborhood, ", ".join(allowed)]

func _blackboard_text(blackboard: Dictionary) -> String:
	var ordered_keys := PackedStringArray(["threat", "hp", "police", "distance", "zone", "combat_enabled", "aggression"])
	var parts: Array[String] = []
	for key in ordered_keys:
		if blackboard.has(key):
			parts.append("%s=%s" % [key, str(blackboard[key])])
	return ", ".join(parts)
