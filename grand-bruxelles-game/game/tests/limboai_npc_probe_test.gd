extends SceneTree

const CONTRACT := preload("res://game/prototypes/ai/npc_ai_contract.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("LIMBOAI_NPC_PROBE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    # The CI prototype vendors LimboAI v1.8.0 only for this job.
    if not ClassDB.class_exists("BTPlayer"):
        _fail("BTPlayer class not registered")
        return
    if not ClassDB.class_exists("LimboHSM"):
        _fail("LimboHSM class not registered")
        return

    var police := CONTRACT.new(CONTRACT.Role.POLICE)
    var civilian := CONTRACT.new(CONTRACT.Role.CIVILIAN)

    var police_state: int = police.tick(0.8, true, 14.0, 0.82, Vector3(12.0, 0.0, -4.0))
    if police_state != CONTRACT.State.CHASE:
        _fail("police failed to enter chase")
        return
    if not police.request_backup:
        _fail("high-threat police chase failed to request backup")
        return

    police_state = police.tick(0.5, false, 24.0, 0.40, Vector3.ZERO)
    if police_state != CONTRACT.State.SEARCH:
        _fail("police failed to search after losing target")
        return

    var civilian_state: int = civilian.tick(0.4, true, 8.0, 0.75, Vector3(2.0, 0.0, 3.0))
    if civilian_state != CONTRACT.State.FLEE:
        _fail("civilian failed to flee credible threat")
        return

    var bb := police.blackboard_snapshot()
    for key: String in ["role", "state", "target_visible", "last_seen_position", "suspicion", "alert_level", "request_backup"]:
        if not bb.has(key):
            _fail("blackboard contract missing %s" % key)
            return

    print("LIMBOAI_NPC_PROBE_OK: BTPlayer+LimboHSM registered; police chase/search/backup and civilian flee contract valid")
    quit(0)
