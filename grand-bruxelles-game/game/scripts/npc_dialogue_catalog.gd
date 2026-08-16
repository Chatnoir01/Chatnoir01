class_name NpcDialogueCatalog
extends RefCounted

const SCHEMA := "grand-bruxelles-npc-dialogue-v1"
const MAX_PERSONAS := 512
const MAX_LINES_PER_INTENT := 12
const MAX_LINE_LENGTH := 180
const ALLOWED_LOCALES := ["fr-BE", "nl-BE", "en"]

var last_error: String = ""
var _personas: Dictionary = {}

func runtime_network_enabled() -> bool:
    return false

func persona_count() -> int:
    return _personas.size()

func clear() -> void:
    last_error = ""
    _personas.clear()

func load_from_dictionary(payload: Dictionary) -> bool:
    clear()
    if str(payload.get("schema", "")) != SCHEMA:
        return _reject("invalid schema")

    var generator_value: Variant = payload.get("generator", null)
    if not generator_value is Dictionary:
        return _reject("generator metadata missing")
    var generator := generator_value as Dictionary
    if str(generator.get("mode", "")) != "offline_llm_bake":
        return _reject("runtime or unknown generator mode forbidden")

    var personas_value: Variant = payload.get("personas", null)
    if not personas_value is Array:
        return _reject("personas must be an array")
    var personas := personas_value as Array
    if personas.is_empty() or personas.size() > MAX_PERSONAS:
        return _reject("persona count outside contract")

    for raw_persona: Variant in personas:
        if not raw_persona is Dictionary:
            return _reject("persona row must be an object")
        if not _validate_and_store_persona(raw_persona as Dictionary):
            return false
    return true

func load_from_file(path: String) -> bool:
    clear()
    if not FileAccess.file_exists(path):
        return _reject("catalog file missing")
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not parsed is Dictionary:
        return _reject("catalog JSON invalid")
    return load_from_dictionary(parsed as Dictionary)

func select_line(persona_id: String, intent: String, context_seed: int) -> String:
    if not _personas.has(persona_id):
        return ""
    var persona: Dictionary = _personas[persona_id]
    var intents: Dictionary = persona.get("intents", {})
    var selected_intent := intent
    if not intents.has(selected_intent):
        if intents.has("smalltalk"):
            selected_intent = "smalltalk"
        elif intents.has("greeting"):
            selected_intent = "greeting"
        else:
            var keys: Array = intents.keys()
            keys.sort()
            if keys.is_empty():
                return ""
            selected_intent = str(keys[0])
    var lines_value: Variant = intents.get(selected_intent, [])
    if not lines_value is Array or (lines_value as Array).is_empty():
        return ""
    var lines := lines_value as Array
    var stable_seed := _stable_hash("%s|%s|%d" % [persona_id, selected_intent, context_seed])
    return str(lines[stable_seed % lines.size()])

func persona_snapshot(persona_id: String) -> Dictionary:
    if not _personas.has(persona_id):
        return {}
    return (_personas[persona_id] as Dictionary).duplicate(true)

func _validate_and_store_persona(persona: Dictionary) -> bool:
    var persona_id := str(persona.get("id", "")).strip_edges()
    if not _is_safe_identifier(persona_id):
        return _reject("invalid persona id")
    if _personas.has(persona_id):
        return _reject("duplicate persona id: %s" % persona_id)

    var zone := str(persona.get("zone", "")).strip_edges()
    if not _is_safe_identifier(zone):
        return _reject("invalid zone for %s" % persona_id)

    var locale := str(persona.get("locale", ""))
    if locale not in ALLOWED_LOCALES:
        return _reject("unsupported locale for %s" % persona_id)

    var intents_value: Variant = persona.get("intents", null)
    if not intents_value is Dictionary:
        return _reject("intents missing for %s" % persona_id)
    var intents := intents_value as Dictionary
    if intents.is_empty():
        return _reject("intents empty for %s" % persona_id)

    var normalized_intents: Dictionary = {}
    for raw_key: Variant in intents.keys():
        var intent := str(raw_key).strip_edges()
        if not _is_safe_identifier(intent):
            return _reject("invalid intent for %s" % persona_id)
        var lines_value: Variant = intents.get(raw_key, null)
        if not lines_value is Array:
            return _reject("intent lines must be an array for %s" % persona_id)
        var lines := lines_value as Array
        if lines.is_empty() or lines.size() > MAX_LINES_PER_INTENT:
            return _reject("line count outside contract for %s/%s" % [persona_id, intent])
        var seen: Dictionary = {}
        var normalized_lines: Array[String] = []
        for raw_line: Variant in lines:
            if not raw_line is String:
                return _reject("generated line must be text for %s/%s" % [persona_id, intent])
            var line := str(raw_line).strip_edges()
            if line.is_empty() or line.length() > MAX_LINE_LENGTH:
                return _reject("generated line length outside contract for %s/%s" % [persona_id, intent])
            if "\n" in line or "\r" in line or "\t" in line:
                return _reject("generated line contains control whitespace for %s/%s" % [persona_id, intent])
            if seen.has(line):
                return _reject("duplicate generated line for %s/%s" % [persona_id, intent])
            seen[line] = true
            normalized_lines.append(line)
        normalized_intents[intent] = normalized_lines

    if not normalized_intents.has("greeting") and not normalized_intents.has("smalltalk"):
        return _reject("persona needs greeting or smalltalk: %s" % persona_id)

    _personas[persona_id] = {
        "id": persona_id,
        "zone": zone,
        "locale": locale,
        "intents": normalized_intents,
    }
    return true

func _is_safe_identifier(value: String) -> bool:
    if value.is_empty() or value.length() > 64:
        return false
    for index: int in range(value.length()):
        var code := value.unicode_at(index)
        var is_digit := code >= 48 and code <= 57
        var is_upper := code >= 65 and code <= 90
        var is_lower := code >= 97 and code <= 122
        if not is_digit and not is_upper and not is_lower and code != 45 and code != 95:
            return false
    return true

func _stable_hash(value: String) -> int:
    var result: int = 2166136261
    for index: int in range(value.length()):
        result = result ^ value.unicode_at(index)
        result = (result * 16777619) & 0x7fffffff
    return result

func _reject(message: String) -> bool:
    last_error = message
    _personas.clear()
    return false
