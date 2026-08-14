extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/stib_suede_runtime.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("STIB_SUEDE_RUNTIME_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var runtime := RUNTIME_SCRIPT.new()
    root.add_child(runtime)
    await process_frame

    if runtime.stop_id != "2539":
        _fail("official stop_id drifted")
        return
    if runtime.name_fr != "Suède" or runtime.name_nl != "Zweden":
        _fail("bilingual identity drifted")
        return
    if runtime.source_crs84 != Vector2(4.33581842, 50.83409624):
        _fail("official CRS84 source point drifted")
        return
    var expected := Vector3(-856.297, 0.16, 868.715)
    if runtime.stop_anchor.distance_to(expected) > 0.05:
        _fail("game-space source anchor drifted: %s" % runtime.stop_anchor)
        return
    if runtime.get_node_or_null("StopIdentity") == null:
        _fail("visible bilingual stop identity missing")
        return
    if runtime.get_node_or_null("Shelter") != null or runtime.get_node_or_null("Timetable") != null:
        _fail("unsourced stop furniture/service semantics present")
        return
    if runtime.transit_stop == null or runtime.transit_stop.stop_id != "2539":
        _fail("NpcTransitStop source identity missing")
        return
    if runtime.waiting_agents.size() < 3:
        _fail("runtime queue is not player-visible")
        return
    for index in range(runtime.waiting_agents.size()):
        var agent: NpcAgent = runtime.waiting_agents[index]
        if agent.transit_state != NpcAgent.TransitState.WAITING:
            _fail("agent %d is not using existing transit wait behavior" % index)
            return
        if agent.transit_stop != runtime.transit_stop:
            _fail("agent %d is not attached to the sourced stop" % index)
            return

    print("STIB_SUEDE_RUNTIME_OK stop=2539 name=Suède/Zweden queue=%d" % runtime.waiting_agents.size())
    runtime.queue_free()
    quit(0)
