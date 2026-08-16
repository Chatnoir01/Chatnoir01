extends SceneTree

const DialogueCatalog = preload("res://game/scripts/npc_dialogue_catalog.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    print("NPC_DIALOGUE_CATALOG_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var catalog = DialogueCatalog.new()
    var payload := {
        "schema": "grand-bruxelles-npc-dialogue-v1",
        "generator": {"mode": "offline_llm_bake", "version": "test"},
        "personas": [
            {
                "id": "jette_local_01",
                "zone": "jette",
                "locale": "fr-BE",
                "intents": {
                    "greeting": ["Salut.", "Bonjour."],
                    "smalltalk": ["Il y a du monde aujourd'hui."],
                    "warning": ["Fais attention."],
                },
            },
            {
                "id": "ixelles_local_01",
                "zone": "ixelles",
                "locale": "fr-BE",
                "intents": {
                    "greeting": ["Bonsoir."],
                    "smalltalk": ["Je rentre chez moi."],
                },
            },
        ],
    }
    if not catalog.load_from_dictionary(payload):
        _fail("valid baked payload rejected: %s" % catalog.last_error)
        return
    if catalog.persona_count() != 2:
        _fail("expected two personas")
        return
    if catalog.runtime_network_enabled():
        _fail("runtime network must stay disabled")
        return
    var first: String = catalog.select_line("jette_local_01", "greeting", 42)
    var second: String = catalog.select_line("jette_local_01", "greeting", 42)
    if first != second or first not in ["Salut.", "Bonjour."]:
        _fail("selection must be deterministic and come from bake")
        return
    var fallback: String = catalog.select_line("jette_local_01", "unknown_intent", 9)
    if fallback != "Il y a du monde aujourd'hui.":
        _fail("unknown intent should fall back to smalltalk")
        return
    var invalid := payload.duplicate(true)
    invalid["personas"][0]["intents"]["greeting"] = ["dup", "dup"]
    if catalog.load_from_dictionary(invalid):
        _fail("duplicate generated lines must be rejected")
        return
    var overlong := payload.duplicate(true)
    overlong["personas"][0]["intents"]["greeting"] = ["x".repeat(181)]
    if catalog.load_from_dictionary(overlong):
        _fail("overlong generated line must be rejected")
        return
    print("NPC_DIALOGUE_CATALOG_OK: personas=2 deterministic=true runtime_network=false")
    quit(0)
