class_name NpcLlmClient
extends Node

@export var endpoint: String = "http://127.0.0.1:8089/v1/chat/completions"
@export var model_name: String = "grand-bruxelles-npc-qwen"
@export_range(1.0, 30.0, 0.5) var timeout_seconds: float = 8.0
@export_range(8, 256, 1) var max_tokens: int = 64

func request_decision(session: NpcDialogueSession, player_text: String, blackboard: Dictionary) -> Dictionary:
	var allowed := NpcDialogueRules.allowed_actions(blackboard)
	var messages := session.build_messages(player_text, blackboard, allowed)
	var request := HTTPRequest.new()
	request.timeout = timeout_seconds
	add_child(request)
	var payload := {
		"model": model_name,
		"messages": messages,
		"temperature": 0.2,
		"max_tokens": max_tokens,
		"stream": false,
		"grammar": NpcDialogueRules.build_grammar(allowed),
	}
	var error := request.request(
		endpoint,
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if error != OK:
		request.queue_free()
		return _remember_fallback(session, player_text, blackboard, "fallback_transport")

	var response: Array = await request.request_completed
	request.queue_free()
	if response.size() < 4:
		return _remember_fallback(session, player_text, blackboard, "fallback_transport")
	var result_code := int(response[0])
	var http_code := int(response[1])
	if result_code != HTTPRequest.RESULT_SUCCESS or http_code < 200 or http_code >= 300:
		return _remember_fallback(session, player_text, blackboard, "fallback_transport")

	var response_body: PackedByteArray = response[3]
	var decoded = JSON.parse_string(response_body.get_string_from_utf8())
	if typeof(decoded) != TYPE_DICTIONARY:
		return _remember_fallback(session, player_text, blackboard, "fallback_response")
	var choices = decoded.get("choices", [])
	if typeof(choices) != TYPE_ARRAY or choices.is_empty():
		return _remember_fallback(session, player_text, blackboard, "fallback_response")
	var first = choices[0]
	if typeof(first) != TYPE_DICTIONARY:
		return _remember_fallback(session, player_text, blackboard, "fallback_response")
	var message = first.get("message", {})
	if typeof(message) != TYPE_DICTIONARY:
		return _remember_fallback(session, player_text, blackboard, "fallback_response")
	var raw_text := String(message.get("content", ""))
	var decision := NpcDialogueRules.filter_output(raw_text, blackboard)
	session.remember(player_text, decision)
	return decision

func _remember_fallback(session: NpcDialogueSession, player_text: String, blackboard: Dictionary, source: String) -> Dictionary:
	var decision := NpcDialogueRules.fallback(blackboard, source)
	session.remember(player_text, decision)
	return decision
