extends SceneTree

var _failed := false

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene missing")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    current_scene = scene
    for _frame in range(6):
        await process_frame

    var runtime := root.get_node_or_null("VisibleCityRuntime")
    if runtime == null:
        _fail("VisibleCityRuntime autoload missing")
        return

    runtime.call("ensure_zone_for_test", "midi")
    for _frame in range(5):
        await process_frame

    var counts: Dictionary = runtime.call("visible_population_counts")
    if int(counts.get("civilians", 0)) < 8:
        _fail("expected at least 8 behavioral civilians at Midi")
        return
    if int(counts.get("police", 0)) < 2:
        _fail("expected at least 2 visible police officers at Midi")
        return

    var living_agents := get_nodes_in_group("living_city_agent")
    if living_agents.size() < 10:
        _fail("living-city agents were not mounted in the real scene")
        return
    for node: Node in living_agents:
        if not node is NpcAgent:
            _fail("living-city group must contain NpcAgent instances only")
            return
        var agent := node as NpcAgent
        if not agent.has_meta("source_anchor"):
            _fail("visible agent missing source anchor metadata")
            return
        if agent.get_node_or_null("RuntimeCharacterCollision") == null:
            _fail("visible NpcAgent missing completed physical collision")
            return

    runtime.call("trigger_incident_for_test", Vector3(-668.5, 0.16, 627.84))
    for _frame in range(5):
        await process_frame

    var police_in_response := 0
    var civilians_reacting := 0
    for node: Node in living_agents:
        if not is_instance_valid(node) or not node is NpcAgent:
            continue
        var agent := node as NpcAgent
        if agent.role == NpcBehaviorModel.Role.POLICE:
            if agent.police_response.phase == NpcPoliceResponse.Phase.PURSUIT or agent.police_response.phase == NpcPoliceResponse.Phase.INVESTIGATE:
                police_in_response += 1
        elif agent.behavior.state == NpcBehaviorModel.State.FLEEING or agent.behavior.state == NpcBehaviorModel.State.AVOIDING:
            civilians_reacting += 1

    if police_in_response < 1:
        _fail("incident did not activate visible police response")
        return
    if civilians_reacting < 1:
        _fail("incident did not produce a visible crowd reaction")
        return

    var hud_text := str(runtime.call("status_text_for_test"))
    if not hud_text.contains("POLICE"):
        _fail("player-facing police state is not exposed in the HUD")
        return

    print("VISIBLE_CITY_RUNTIME_OK: civilians=%d police=%d reacting=%d responders=%d" % [
        int(counts.get("civilians", 0)),
        int(counts.get("police", 0)),
        civilians_reacting,
        police_in_response,
    ])
    quit(0)

func _fail(message: String) -> void:
    if _failed:
        return
    _failed = true
    push_error(message)
    print("VISIBLE_CITY_RUNTIME_FAIL: %s" % message)
    quit(1)
