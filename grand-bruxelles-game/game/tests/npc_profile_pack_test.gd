extends SceneTree

const PACK_SCRIPT := preload("res://game/scripts/npc_profile_pack.gd")
const CATALOG_SCRIPT := preload("res://game/scripts/npc_dialogue_catalog.gd")
const SESSION_SCRIPT := preload("res://game/scripts/npc_llm_session.gd")
const PACK_PATH := "res://data/npc/packs/midi_resident.pack.game.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("NPC_PROFILE_PACK_FAIL: %s" % message)
    quit(1)

func _expect(condition: bool, message: String) -> bool:
    if not condition: _fail(message); return false
    return true

func _run() -> void:
    var pack = PACK_SCRIPT.new()
    if not _expect(pack.load_from_file(PACK_PATH), "pack rejected: %s" % pack.last_error): return
    if not _expect(pack.profile_count() == 1 and pack.total_dialogue_lines("midi_resident_01") == 20, "pack size contract failed"): return
    if not _expect(not pack.runtime_network_enabled(), "pack enabled runtime network"): return
    var profile: Dictionary = pack.profile_snapshot("midi_resident_01")
    var thresholds := profile.get("thresholds", {}) as Dictionary
    if not _expect(float(thresholds.get("fear", -1.0)) == 0.55 and float(thresholds.get("aggression", -1.0)) == 0.2, "profile thresholds lost"): return

    var catalog = CATALOG_SCRIPT.new()
    if not _expect(catalog.load_from_dictionary(pack.dialogue_payload("midi_resident_01")), "embedded dialogue rejected: %s" % catalog.last_error): return
    var session = SESSION_SCRIPT.new()
    root.add_child(session)
    session.configure("npc-pack-offline-01", "Nora", "midi", "midi_resident_01", catalog, "")
    var result: Dictionary = await session.request_turn("Salut, ça va ?", {
        "threat": 0.0, "health": 100.0, "police_nearby": false,
        "distance_to_player": 1.5, "zone": "midi", "event_serial": 8,
    })
    if not _expect(str(result.get("source", "")) == "fallback", "model-off turn did not use pack"): return
    if not _expect(str(result.get("action", "")) == "idle" and not str(result.get("line", "")).is_empty(), "model-off NPC did not talk"): return
    var persona: Dictionary = catalog.persona_snapshot("midi_resident_01")
    var intents := persona.get("intents", {}) as Dictionary
    var smalltalk := intents.get("smalltalk", []) as Array
    if not _expect(str(result.get("line", "")) in smalltalk, "model-off line did not come from baked pack"): return
    print("NPC_PROFILE_PACK_OK: profiles=1 lines=20 thresholds=true model_off_talk=true")
    quit(0)
