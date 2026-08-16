class_name NpcDialogueRules
extends RefCounted

const ACTIONS := PackedStringArray(["idle", "walk", "alert", "defend", "fight", "flee", "hurt"])
const MAX_LINE_LENGTH := 140
const FORBIDDEN_LINE_MARKERS := PackedStringArray([
	"je suis une ia",
	"je suis un modèle",
	"je suis un modele",
	"en tant qu'ia",
	"en tant que ia",
	"chatgpt",
	"qwen",
	"modèle de langage",
	"modele de langage",
	"prompt système",
	"prompt systeme",
	"system prompt",
])

static func allowed_actions(blackboard: Dictionary) -> PackedStringArray:
	var allowed := PackedStringArray(["idle", "walk"])
	var threat := clampf(float(blackboard.get("threat", 0.0)), 0.0, 1.0)
	var hp := clampf(float(blackboard.get("hp", 100.0)), 0.0, 100.0)
	var distance := maxf(float(blackboard.get("distance", 9999.0)), 0.0)
	var combat_enabled := bool(blackboard.get("combat_enabled", false))
	var aggression := clampf(float(blackboard.get("aggression", 0.0)), 0.0, 1.0)
	var police_present := bool(blackboard.get("police", false))

	if threat >= 0.20:
		allowed.append("alert")
	if hp < 100.0:
		allowed.append("hurt")
	if threat >= 0.55 or hp <= 20.0:
		allowed.append("flee")
	if combat_enabled and threat >= 0.45 and distance <= 2.5:
		allowed.append("defend")
		if aggression >= 0.60 and hp >= 25.0 and not police_present:
			allowed.append("fight")
	return allowed

static func parse_output(raw_text: String) -> Dictionary:
	var action := ""
	var line := ""
	for raw_line in raw_text.replace("\r", "").split("\n", false):
		var stripped := String(raw_line).strip_edges()
		var lower := stripped.to_lower()
		if lower.begins_with("action:") and action.is_empty():
			action = stripped.substr(stripped.find(":") + 1).strip_edges().to_lower()
		elif lower.begins_with("line:") and line.is_empty():
			line = stripped.substr(stripped.find(":") + 1).strip_edges()
	if action.is_empty() or line.is_empty() or not ACTIONS.has(action):
		return {}
	line = _sanitize_line(line)
	if line.is_empty():
		return {}
	return {"action": action, "line": line}

static func filter_output(raw_text: String, blackboard: Dictionary) -> Dictionary:
	var parsed := parse_output(raw_text)
	if parsed.is_empty():
		return fallback(blackboard, "fallback_parse")
	var action := String(parsed.get("action", ""))
	if not allowed_actions(blackboard).has(action):
		return fallback(blackboard, "fallback_rule_reject")
	var line := String(parsed.get("line", ""))
	if not line_allowed(line):
		return fallback(blackboard, "fallback_line_reject")
	return {
		"action": action,
		"line": line,
		"accepted": true,
		"source": "llm",
	}

static func fallback(blackboard: Dictionary, source: String = "fallback_offline") -> Dictionary:
	var allowed := allowed_actions(blackboard)
	var threat := clampf(float(blackboard.get("threat", 0.0)), 0.0, 1.0)
	var hp := clampf(float(blackboard.get("hp", 100.0)), 0.0, 100.0)
	var action := "idle"
	var line := "Ça va, tranquille."
	if allowed.has("flee") and (threat >= 0.55 or hp <= 20.0):
		action = "flee"
		line = "Laisse-moi passer, j'me casse."
	elif allowed.has("alert"):
		action = "alert"
		line = "Hé, doucement là."
	elif allowed.has("hurt") and hp < 100.0:
		action = "hurt"
		line = "Aïe... ça va pas."
	return {
		"action": action,
		"line": line,
		"accepted": false,
		"source": source,
	}

static func line_allowed(line: String) -> bool:
	var normalized := line.strip_edges().to_lower()
	if normalized.is_empty() or normalized.length() > MAX_LINE_LENGTH:
		return false
	for marker in FORBIDDEN_LINE_MARKERS:
		if normalized.contains(marker):
			return false
	return true

static func build_grammar(allowed: PackedStringArray) -> String:
	var actions: Array[String] = []
	for action in allowed:
		actions.append('"%s"' % _escape_gbnf_literal(String(action)))
	if actions.is_empty():
		actions.append('"idle"')
	return 'root ::= "action: " action "\\nline: " [^\\n]{1,%d}\naction ::= %s' % [MAX_LINE_LENGTH, " | ".join(actions)]

static func _sanitize_line(value: String) -> String:
	var line := value.replace("\r", " ").replace("\n", " ").strip_edges()
	while line.contains("  "):
		line = line.replace("  ", " ")
	if line.length() > MAX_LINE_LENGTH:
		line = line.substr(0, MAX_LINE_LENGTH).strip_edges()
	return line

static func _escape_gbnf_literal(value: String) -> String:
	return value.replace("\\", "\\\\").replace('"', '\\"')
