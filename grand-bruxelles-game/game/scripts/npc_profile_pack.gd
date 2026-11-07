class_name NpcProfilePack
extends RefCounted

const SCHEMA := "grand-bruxelles-npc-pack-v1"
const DIALOGUE_SCHEMA := "grand-bruxelles-npc-dialogue-v1"
const ARCHETYPES := ["civilian", "aggressive", "runner"]
const LOCALES := ["fr-BE", "nl-BE", "en"]

var last_error := ""
var _generator: Dictionary = {}
var _profiles: Dictionary = {}

func runtime_network_enabled() -> bool:
    return false

func profile_count() -> int:
    return _profiles.size()

func load_from_file(path: String) -> bool:
    if not FileAccess.file_exists(path):
        return _reject("pack file missing")
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not parsed is Dictionary:
        return _reject("pack JSON invalid")
    return load_from_dictionary(parsed as Dictionary)

func load_from_dictionary(payload: Dictionary) -> bool:
    last_error = ""
    _profiles.clear()
    if str(payload.get("schema", "")) != SCHEMA:
        return _reject("invalid pack schema")
    var generator_value: Variant = payload.get("generator", null)
    if not generator_value is Dictionary or str((generator_value as Dictionary).get("mode", "")) != "offline_llm_bake":
        return _reject("offline bake metadata required")
    _generator = (generator_value as Dictionary).duplicate(true)
    var rows_value: Variant = payload.get("profiles", null)
    if not rows_value is Array or (rows_value as Array).is_empty():
        return _reject("profiles missing")
    for raw: Variant in rows_value as Array:
        if not raw is Dictionary or not _store_profile(raw as Dictionary):
            return false
    return true

func profile_snapshot(profile_id: String) -> Dictionary:
    if not _profiles.has(profile_id):
        return {}
    return (_profiles[profile_id] as Dictionary).duplicate(true)

func total_dialogue_lines(profile_id: String) -> int:
    var profile := profile_snapshot(profile_id)
    if profile.is_empty():
        return 0
    var total := 0
    for lines_value: Variant in (profile.get("dialogue", {}) as Dictionary).values():
        if lines_value is Array:
            total += (lines_value as Array).size()
    return total

func dialogue_payload(profile_id: String) -> Dictionary:
    var profile := profile_snapshot(profile_id)
    if profile.is_empty():
        return {}
    return {
        "schema": DIALOGUE_SCHEMA,
        "generator": _generator.duplicate(true),
        "personas": [{
            "id": profile_id,
            "zone": str(profile.get("zone", "")),
            "locale": str(profile.get("locale", "fr-BE")),
            "intents": (profile.get("dialogue", {}) as Dictionary).duplicate(true),
        }],
    }

func _store_profile(raw: Dictionary) -> bool:
    var profile_id := str(raw.get("id", "")).strip_edges()
    if profile_id.is_empty() or profile_id.length() > 64 or _profiles.has(profile_id):
        return _reject("invalid or duplicate profile id")
    var zone := str(raw.get("zone", "")).strip_edges()
    var locale := str(raw.get("locale", ""))
    var archetype := str(raw.get("archetype", ""))
    if zone.is_empty() or locale not in LOCALES or archetype not in ARCHETYPES:
        return _reject("profile identity outside contract")
    var persona_value: Variant = raw.get("persona", null)
    var thresholds_value: Variant = raw.get("thresholds", null)
    var dialogue_value: Variant = raw.get("dialogue", null)
    if not persona_value is Dictionary or not thresholds_value is Dictionary or not dialogue_value is Dictionary:
        return _reject("profile sections missing")
    var persona := persona_value as Dictionary
    if str(persona.get("name", "")).strip_edges().is_empty() or str(persona.get("summary", "")).strip_edges().is_empty():
        return _reject("persona incomplete")
    var thresholds := thresholds_value as Dictionary
    for key: String in ["fear", "aggression", "flee_health"]:
        var value := float(thresholds.get(key, -1.0))
        if value < 0.0 or value > 1.0:
            return _reject("threshold outside contract")
    var dialogue := dialogue_value as Dictionary
    if not dialogue.has("greeting") or not dialogue.has("smalltalk"):
        return _reject("required intents missing")
    var seen: Dictionary = {}
    var total := 0
    for lines_value: Variant in dialogue.values():
        if not lines_value is Array or (lines_value as Array).is_empty() or (lines_value as Array).size() > 12:
            return _reject("intent lines outside contract")
        for raw_line: Variant in lines_value as Array:
            var line := str(raw_line).strip_edges()
            if line.is_empty() or line.length() > 180 or seen.has(line):
                return _reject("invalid or duplicate dialogue line")
            seen[line] = true
            total += 1
    if total < 20 or total > 40:
        return _reject("profile must contain 20-40 dialogue lines")
    _profiles[profile_id] = raw.duplicate(true)
    return true

func _reject(message: String) -> bool:
    last_error = message
    _profiles.clear()
    return false
