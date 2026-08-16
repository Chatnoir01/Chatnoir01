class_name NpcLlmSession
extends Node

const ALLOWED_ACTIONS := ["idle", "walk", "alert", "defend", "fight", "flee", "hurt"]
const MAX_MEMORY := 4
const MAX_LINE_LENGTH := 180
const DEFAULT_ENDPOINT := "http://127.0.0.1:8765/v1/npc/respond"

var _npc_id := ""
var _persona_name := ""
var _zone := ""
var _persona_id := ""
var _catalog: NpcDialogueCatalog = null
var _endpoint := DEFAULT_ENDPOINT
var _memory: Array[Dictionary] = []

func configure(
    npc_id_value: String,
    persona_name: String,
    zone: String,
    persona_id: String,
    catalog: NpcDialogueCatalog,
    endpoint: String = DEFAULT_ENDPOINT
) -> void:
    _npc_id = npc_id_value.strip_edges()
    _persona_name = persona_name.strip_edges()
    _zone = zone.strip_edges()
    _persona_id = persona_id.strip_edges()
    _catalog = catalog
    _endpoint = endpoint.strip_edges()
    _memory.clear()

func npc_id() -> String:
    return _npc_id

func runtime_model_optional() -> bool:
    return true

func memory_snapshot() -> Array:
    return _memory.duplicate(true)

func clear_memory() -> void:
    _memory.clear()

func build_request_payload(user_message: String, blackboard: Dictionary) -> Dictionary:
    return {
        "npc_id": _npc_id,
        "persona": {
            "name": _persona_name,
            "zone": _zone,
        },
        "blackboard": blackboard.duplicate(true),
        "memory": _memory.duplicate(true),
        "user_message": user_message.strip_edges().left(320),
    }

func resolve_model_text(user_message: String, raw_text: String, blackboard: Dictionary) -> Dictionary:
    var filtered := filter_model_text(raw_text, blackboard)
    var result: Dictionary
    if bool(filtered.get("accepted", false)):
        result = {
            "accepted": true,
            "action": str(filtered.get("action", "idle")),
            "line": str(filtered.get("line", "")),
            "source": "llm",
            "reason": "",
        }
    else:
        result = _fallback_result(blackboard, str(filtered.get("reason", "model_rejected")))
    _remember(user_message, result)
    return result

func request_turn(user_message: String, blackboard: Dictionary) -> Dictionary:
    if user_message.strip_edges().is_empty():
        var empty_result := _fallback_result(blackboard, "empty_user_message")
        _remember(user_message, empty_result)
        return empty_result
    if _endpoint.is_empty() or OS.has_feature("web") or not is_inside_tree():
        var unavailable := _fallback_result(blackboard, "model_unavailable")
        _remember(user_message, unavailable)
        return unavailable

    var http := HTTPRequest.new()
    http.timeout = 8.0
    add_child(http)
    var headers := PackedStringArray(["Content-Type: application/json"])
    var error := http.request(
        _endpoint,
        headers,
        HTTPClient.METHOD_POST,
        JSON.stringify(build_request_payload(user_message, blackboard))
    )
    if error != OK:
        http.queue_free()
        var request_failed := _fallback_result(blackboard, "request_start_failed")
        _remember(user_message, request_failed)
        return request_failed

    var response: Array = await http.request_completed
    http.queue_free()
    if response.size() < 4:
        var malformed := _fallback_result(blackboard, "http_result_malformed")
        _remember(user_message, malformed)
        return malformed

    var request_result := int(response[0])
    var response_code := int(response[1])
    var body_value: Variant = response[3]
    if request_result != HTTPRequest.RESULT_SUCCESS or response_code != 200 or not body_value is PackedByteArray:
        var network_failed := _fallback_result(blackboard, "model_unavailable")
        _remember(user_message, network_failed)
        return network_failed

    var parsed: Variant = JSON.parse_string((body_value as PackedByteArray).get_string_from_utf8())
    if not parsed is Dictionary:
        var invalid_json := _fallback_result(blackboard, "server_json_invalid")
        _remember(user_message, invalid_json)
        return invalid_json
    var payload := parsed as Dictionary
    if str(payload.get("npc_id", "")) != _npc_id:
        var wrong_session := _fallback_result(blackboard, "npc_session_mismatch")
        _remember(user_message, wrong_session)
        return wrong_session
    return resolve_model_text(user_message, str(payload.get("text", "")), blackboard)

func filter_model_text(raw_text: String, blackboard: Dictionary) -> Dictionary:
    var non_empty: Array[String] = []
    for raw_line: String in raw_text.replace("\r", "").split("\n"):
        var line := raw_line.strip_edges()
        if not line.is_empty():
            non_empty.append(line)
    if non_empty.size() != 2:
        return {"accepted": false, "reason": "format"}
    if not non_empty[0].begins_with("action:") or not non_empty[1].begins_with("line:"):
        return {"accepted": false, "reason": "format"}

    var action := non_empty[0].substr("action:".length()).strip_edges().to_lower()
    var line := non_empty[1].substr("line:".length()).strip_edges()
    if action not in ALLOWED_ACTIONS:
        return {"accepted": false, "reason": "illegal_action"}
    if not _action_allowed_by_rules(action, blackboard):
        return {"accepted": false, "reason": "action_blocked_by_rules"}
    if not _line_allowed(line):
        return {"accepted": false, "reason": "illegal_line"}
    return {
        "accepted": true,
        "action": action,
        "line": line,
        "reason": "",
    }

func _action_allowed_by_rules(action: String, blackboard: Dictionary) -> bool:
    var board_zone := str(blackboard.get("zone", _zone))
    if not _zone.is_empty() and board_zone != _zone:
        return false
    var health := clampf(float(blackboard.get("health", 100.0)), 0.0, 100.0)
    var threat := clampf(float(blackboard.get("threat", 0.0)), 0.0, 1.0)
    var distance := maxf(0.0, float(blackboard.get("distance_to_player", 9999.0)))
    var police_nearby := bool(blackboard.get("police_nearby", false))

    match action:
        "fight":
            return health > 0.0 and threat >= 0.35 and distance <= 3.0
        "defend":
            return health > 0.0 and threat >= 0.25 and distance <= 4.0
        "flee":
            return health > 0.0 and threat >= 0.20
        "alert":
            return threat >= 0.10 or police_nearby
        "hurt":
            return health < 100.0
        "walk", "idle":
            return health > 0.0
        _:
            return false

func _line_allowed(line: String) -> bool:
    if line.is_empty() or line.length() > MAX_LINE_LENGTH:
        return false
    if "\t" in line or "\n" in line or "\r" in line:
        return false
    var lowered := line.to_lower()
    var forbidden := [
        "je suis une ia",
        "je suis un modèle",
        "je suis un modele",
        "modèle de langage",
        "modele de langage",
        "language model",
        "prompt système",
        "prompt systeme",
        "system prompt",
        "mon prompt",
    ]
    for token: String in forbidden:
        if token in lowered:
            return false
    return true

func _fallback_result(blackboard: Dictionary, reason: String) -> Dictionary:
    var health := clampf(float(blackboard.get("health", 100.0)), 0.0, 100.0)
    var threat := clampf(float(blackboard.get("threat", 0.0)), 0.0, 1.0)
    var distance := maxf(0.0, float(blackboard.get("distance_to_player", 9999.0)))
    var action := "idle"
    var intent := "smalltalk"
    if health < 100.0:
        action = "hurt"
        intent = "hurt"
    elif health <= 25.0 and threat >= 0.20:
        action = "flee"
        intent = "warning"
    elif threat >= 0.65 and distance <= 2.5:
        action = "defend"
        intent = "warning"
    elif threat >= 0.20:
        action = "alert"
        intent = "warning"

    var line := "Salut."
    if _catalog != null and not _persona_id.is_empty():
        var seed := int(blackboard.get("event_serial", 0)) + _stable_hash(_npc_id)
        var baked := _catalog.select_line(_persona_id, intent, seed)
        if not baked.is_empty() and _line_allowed(baked):
            line = baked
        elif intent != "smalltalk":
            baked = _catalog.select_line(_persona_id, "smalltalk", seed)
            if not baked.is_empty() and _line_allowed(baked):
                line = baked
    return {
        "accepted": false,
        "action": action,
        "line": line,
        "source": "fallback",
        "reason": reason,
    }

func _remember(user_message: String, result: Dictionary) -> void:
    var user := user_message.strip_edges().left(320)
    var line := str(result.get("line", "")).strip_edges().left(MAX_LINE_LENGTH)
    var action := str(result.get("action", "idle"))
    if user.is_empty() or line.is_empty() or action not in ALLOWED_ACTIONS:
        return
    _memory.append({
        "user": user,
        "action": action,
        "line": line,
    })
    while _memory.size() > MAX_MEMORY:
        _memory.pop_front()

func _stable_hash(value: String) -> int:
    var result: int = 2166136261
    for index: int in range(value.length()):
        result = result ^ value.unicode_at(index)
        result = (result * 16777619) & 0x7fffffff
    return result
