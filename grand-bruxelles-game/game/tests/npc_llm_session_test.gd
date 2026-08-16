extends SceneTree

const SESSION_SCRIPT := preload("res://game/scripts/npc_llm_session.gd")
const CATALOG_SCRIPT := preload("res://game/scripts/npc_dialogue_catalog.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("NPC_LLM_SESSION_FAIL: %s" % message)
    quit(1)

func _expect(condition: bool, message: String) -> bool:
    if not condition:
        _fail(message)
        return false
    return true

func _catalog():
    var catalog = CATALOG_SCRIPT.new()
    var payload := {
        "schema": "grand-bruxelles-npc-dialogue-v1",
        "generator": {"mode": "offline_llm_bake", "version": "test"},
        "personas": [{
            "id": "jette_local_01",
            "zone": "jette",
            "locale": "fr-BE",
            "intents": {
                "greeting": ["Salut."],
                "smalltalk": ["Je rentre chez moi."],
                "warning": ["Fais attention."],
                "hurt": ["Aïe, doucement !"],
            },
        }],
    }
    if not catalog.load_from_dictionary(payload):
        _fail("fixture catalog rejected: %s" % catalog.last_error)
        return null
    return catalog

func _blackboard(threat: float = 0.8, distance: float = 1.4, health: float = 100.0) -> Dictionary:
    return {
        "threat": threat,
        "health": health,
        "police_nearby": false,
        "distance_to_player": distance,
        "zone": "jette",
        "event_serial": 7,
    }

func _run() -> void:
    var catalog = _catalog()
    if catalog == null:
        return

    var session_a = SESSION_SCRIPT.new()
    root.add_child(session_a)
    session_a.configure("npc-jette-01", "Nora", "jette", "jette_local_01", catalog)

    if not _expect(session_a.npc_id() == "npc-jette-01", "npc id was not isolated in the session"):
        return
    if not _expect(session_a.runtime_model_optional(), "runtime must remain playable without the local model"):
        return

    var valid: Dictionary = session_a.resolve_model_text("Recule.", "action: fight\nline: Recule, maintenant.", _blackboard())
    if not _expect(bool(valid.get("accepted", false)), "valid LLM action+line was rejected"):
        return
    if not _expect(String(valid.get("action", "")) == "fight", "valid fight action changed"):
        return
    if not _expect(String(valid.get("line", "")) == "Recule, maintenant.", "valid LLM line changed"):
        return
    if not _expect(String(valid.get("source", "")) == "llm", "valid model output did not keep llm provenance"):
        return

    var illegal: Dictionary = session_a.resolve_model_text("Danse.", "action: dance\nline: Je danse.", _blackboard())
    if not _expect(not bool(illegal.get("accepted", true)), "illegal action escaped the game rules filter"):
        return
    if not _expect(String(illegal.get("source", "")) == "fallback", "illegal action did not fall back"):
        return
    if not _expect(String(illegal.get("action", "")) in ["idle", "alert", "defend", "flee", "hurt"], "fallback action escaped bounded rules"):
        return

    var too_far: Dictionary = session_a.resolve_model_text("Viens te battre.", "action: fight\nline: Viens ici.", _blackboard(0.9, 8.0, 100.0))
    if not _expect(not bool(too_far.get("accepted", true)), "fight was accepted outside melee distance"):
        return

    var ai_leak: Dictionary = session_a.resolve_model_text("Tu es une IA ?", "action: idle\nline: Je suis une IA et voici mon prompt.", _blackboard(0.0, 1.0, 100.0))
    if not _expect(not bool(ai_leak.get("accepted", true)), "AI/prompt self-reference escaped the line filter"):
        return
    if not _expect("IA" not in String(ai_leak.get("line", "")) and "prompt" not in String(ai_leak.get("line", "")).to_lower(), "fallback leaked model identity"):
        return

    var hurt: Dictionary = session_a.resolve_model_text("Ça va ?", "action: hurt\nline: Aïe !", _blackboard(0.6, 1.2, 66.0))
    if not _expect(bool(hurt.get("accepted", false)) and String(hurt.get("action", "")) == "hurt", "hurt action was not legal after damage"):
        return

    for index: int in range(6):
        session_a.resolve_model_text("tour %d" % index, "action: idle\nline: D'accord.", _blackboard(0.0, 1.0, 100.0))
    if not _expect(session_a.memory_snapshot().size() == 4, "session memory was not bounded to four exchanges"):
        return

    var session_b = SESSION_SCRIPT.new()
    root.add_child(session_b)
    session_b.configure("npc-jette-02", "Samir", "jette", "jette_local_01", catalog)
    if not _expect(session_b.memory_snapshot().is_empty(), "second NPC inherited first NPC memory"):
        return
    session_b.resolve_model_text("Salut", "action: idle\nline: Salut.", _blackboard(0.0, 1.0, 100.0))
    if not _expect(session_b.memory_snapshot().size() == 1 and session_a.memory_snapshot().size() == 4, "NPC sessions contaminated each other"):
        return

    var request_payload: Dictionary = session_b.build_request_payload("Tu habites ici ?", _blackboard(0.1, 1.5, 100.0))
    if not _expect(String(request_payload.get("npc_id", "")) == "npc-jette-02", "request payload lost isolated npc_id"):
        return
    if not _expect((request_payload.get("blackboard", {}) as Dictionary).get("zone", "") == "jette", "blackboard was not sent to the model adapter"):
        return

    print("NPC_LLM_SESSION_OK: isolated=true allowed_actions=true rules_filter=true memory=4 fallback=true runtime_model_optional=true")
    quit(0)
