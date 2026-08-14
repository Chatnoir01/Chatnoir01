extends SceneTree

const PILOT_SCENE := preload("res://game/prototypes/ai/npc_limbo_pilot.tscn")


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("LIMBOAI_NPC_PILOT_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    if not ClassDB.class_exists(&"LimboHSM") or not ClassDB.class_exists(&"LimboState"):
        _fail("LimboAI HSM classes are not registered")
        return

    var pilot := PILOT_SCENE.instantiate()
    root.add_child(pilot)
    await process_frame
    await process_frame

    var civilian := pilot.get_node_or_null("Civilian") as NpcAgent
    var police := pilot.get_node_or_null("Police") as NpcAgent
    var civilian_ai := pilot.get_node_or_null("CivilianLimboPilot")
    var police_ai := pilot.get_node_or_null("PoliceLimboPilot")
    if civilian == null or police == null or civilian_ai == null or police_ai == null:
        _fail("pilot scene is missing civilian, police or orchestrator")
        return

    if not bool(civilian_ai.get("extension_available")) or not bool(police_ai.get("extension_available")):
        _fail("pilot HSM build failed: civilian_bound=%s civilian_error=%s police_bound=%s police_error=%s" % [
            civilian_ai.get("agent") != null,
            str(civilian_ai.get("last_build_error")),
            police_ai.get("agent") != null,
            str(police_ai.get("last_build_error")),
        ])
        return
    if StringName(civilian_ai.get("active_branch")) != &"routine" or StringName(police_ai.get("active_branch")) != &"routine":
        _fail("pilot agents did not begin on authoritative routine branch")
        return
    if StringName(civilian_ai.call("hsm_active_state_name")) != &"routine" or StringName(police_ai.call("hsm_active_state_name")) != &"routine":
        _fail("LimboHSM initial active state is not routine")
        return

    # Police: authoritative response model enters pursuit, LimboHSM mirrors it.
    police.report_police_incident(Vector3(12.0, 0.0, -4.0), 0.85, 101)
    var police_branch := StringName(police_ai.call("sync_from_agent", true, 14.0, Vector3(12.0, 0.0, -4.0), 0.1))
    if police_branch != &"pursue" or StringName(police_ai.call("hsm_active_state_name")) != &"pursue":
        _fail("police pursuit was not mirrored by LimboHSM")
        return
    var police_action: Dictionary = police_ai.get("last_action_request")
    if not bool(police_action.get("request_backup", false)):
        _fail("police pursuit action lost the existing backup request contract")
        return

    # After the shipped pursuit downgrade hold, the existing police model owns
    # the transition to investigate; LimboAI follows instead of redefining it.
    police.update_police_threat(true, 0.40, 1.6)
    police_branch = StringName(police_ai.call("sync_from_agent", true, 20.0, police.behavior.target_position, 1.6))
    if police_branch != &"investigate" or StringName(police_ai.call("hsm_active_state_name")) != &"investigate":
        _fail("police investigate downgrade was not mirrored by LimboHSM")
        return

    police.update_police_threat(false, 0.0, 5.1)
    police_branch = StringName(police_ai.call("sync_from_agent", false, 28.0, police.behavior.target_position, 5.1))
    if police_branch != &"return" or StringName(police_ai.call("hsm_active_state_name")) != &"return":
        _fail("police de-escalation/return branch was not mirrored by LimboHSM")
        return

    # Civilian: existing alert thresholds trigger flee, then observation as the
    # model calms. LimboAI only orchestrates the active branch.
    civilian.react_to_event(70.0, Vector3(-1.0, 0.0, 3.0))
    var civilian_branch := StringName(civilian_ai.call("sync_from_agent", true, 8.0, Vector3(-1.0, 0.0, 3.0), 0.2))
    if civilian_branch != &"flee" or StringName(civilian_ai.call("hsm_active_state_name")) != &"flee":
        _fail("civilian flee state was not mirrored by LimboHSM")
        return

    civilian.behavior.calm_down(55.0)
    civilian_branch = StringName(civilian_ai.call("sync_from_agent", false, 18.0, civilian.behavior.target_position, 0.4))
    if civilian_branch != &"observe" or StringName(civilian_ai.call("hsm_active_state_name")) != &"observe":
        _fail("civilian observation recovery was not mirrored by LimboHSM")
        return

    var police_snapshot: Dictionary = police_ai.call("blackboard_snapshot")
    for key: String in ["role", "state", "branch", "target_visible", "last_seen_position", "limbo_extension_available", "limbo_active_branch", "limbo_transition_count"]:
        if not police_snapshot.has(key):
            _fail("pilot blackboard snapshot missing %s" % key)
            return

    var police_transitions := int(police_ai.get("transition_count"))
    var civilian_transitions := int(civilian_ai.get("transition_count"))
    if police_transitions < 3 or civilian_transitions < 2:
        _fail("pilot did not execute enough real HSM transitions: police=%d civilian=%d" % [police_transitions, civilian_transitions])
        return

    print("LIMBOAI_NPC_PILOT_OK: real_hsm=true police=routine>pursue>investigate>return civilian=routine>flee>observe transitions=%d/%d authoritative_model_preserved=true" % [police_transitions, civilian_transitions])
    quit(0)
