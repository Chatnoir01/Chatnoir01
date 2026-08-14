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

    var police_model := NpcBehaviorModel.new()
    police_model.configure(NpcBehaviorModel.Role.POLICE, 17, Vector3.ZERO)
    police_model.apply_stimulus(82.0, Vector3(12.0, 0.0, -4.0))
    if police_model.state != NpcBehaviorModel.State.PURSUING:
        _fail("shipped police model did not enter pursuing")
        return

    var police := CONTRACT.new(police_model)
    police.sync_perception(true, 14.0, police_model.target_position, 0.4)
    if police.limbo_branch() != &"pursue":
        _fail("Limbo bridge did not map pursuing state")
        return
    if not police.should_request_backup():
        _fail("pursuit did not expose backup request")
        return

    police_model.calm_down(30.0)
    police.sync_perception(false, 24.0, Vector3.ZERO, 0.5)
    if police.limbo_branch() != &"investigate":
        _fail("Limbo bridge did not follow shipped investigate transition")
        return

    var civilian_model := NpcBehaviorModel.new()
    civilian_model.configure(NpcBehaviorModel.Role.CIVILIAN, 31, Vector3.ZERO)
    civilian_model.apply_stimulus(70.0, Vector3(2.0, 0.0, 3.0))
    var civilian := CONTRACT.new(civilian_model)
    civilian.sync_perception(true, 8.0, civilian_model.target_position, 0.2)
    if civilian.limbo_branch() != &"flee":
        _fail("Limbo bridge did not map civilian flee state")
        return

    var bb := police.blackboard_snapshot()
    for key: String in ["role", "state", "branch", "alert_level", "target_visible", "last_seen_position", "preferred_speed", "archetype", "request_backup"]:
        if not bb.has(key):
            _fail("blackboard bridge missing %s" % key)
            return

    var action := civilian.action_request()
    if StringName(action.get("action", &"none")) != &"flee" or float(action.get("speed_scale", 0.0)) <= 1.0:
        _fail("civilian flee action request invalid")
        return

    print("LIMBOAI_NPC_PROBE_OK: extension loaded; existing NpcBehaviorModel is preserved and mapped to LimboAI branches/blackboard")
    quit(0)
