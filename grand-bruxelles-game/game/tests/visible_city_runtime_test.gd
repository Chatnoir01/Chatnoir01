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

    var police_agents: Array[NpcAgent] = []
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
        var legacy_visual := agent.get_node_or_null("VisibleHumanoid") as Node3D
        if legacy_visual == null:
            _fail("visible NpcAgent missing legacy/profile visual")
            return
        if absf(legacy_visual.position.y - 0.90) > 0.001:
            _fail("ground-origin NpcAgent visual lift drifted for %s: y=%.3f" % [agent.name, legacy_visual.position.y])
            return
        if agent.role == NpcBehaviorModel.Role.POLICE:
            police_agents.append(agent)

    if police_agents.size() < 2:
        _fail("expected two behavioral police agents for dual-patrol regression")
        return
    police_agents.sort_custom(func(a: NpcAgent, b: NpcAgent) -> bool: return a.variation_seed < b.variation_seed)

    var routes_value: Variant = runtime.get("_routes")
    if not routes_value is Dictionary:
        _fail("VisibleCityRuntime route registry unavailable")
        return
    var routes: Dictionary = routes_value
    var first_route_value: Variant = routes.get(police_agents[0].get_instance_id(), [])
    var second_route_value: Variant = routes.get(police_agents[1].get_instance_id(), [])
    if not first_route_value is Array or not second_route_value is Array:
        _fail("police patrol routes were not registered")
        return
    var first_route: Array = first_route_value
    var second_route: Array = second_route_value
    if first_route.size() < 2 or second_route.size() < 2:
        _fail("police patrol routes need at least two points")
        return
    if not first_route[0] is Vector3 or not first_route[1] is Vector3 or not second_route[0] is Vector3 or not second_route[1] is Vector3:
        _fail("police patrol route points must be Vector3")
        return

    var first_a: Vector3 = first_route[0]
    var first_b: Vector3 = first_route[1]
    var second_a: Vector3 = second_route[0]
    var second_b: Vector3 = second_route[1]
    var route_separation := _planar_segment_separation(first_a, first_b, second_a, second_b)
    if route_separation < 1.0:
        _fail("Midi police patrol routes overlap on one sidewalk: separation=%.3f m" % route_separation)
        return

    var police_start_positions: Dictionary = {}
    for officer: NpcAgent in police_agents.slice(0, 2):
        police_start_positions[officer.get_instance_id()] = officer.get_world_position()

    for _frame in range(120):
        await physics_frame

    for officer: NpcAgent in police_agents.slice(0, 2):
        if not is_instance_valid(officer) or not officer.active:
            _fail("both Midi police officers must remain active during patrol")
            return
        var start_value: Variant = police_start_positions.get(officer.get_instance_id(), officer.get_world_position())
        if not start_value is Vector3:
            _fail("police patrol start position missing")
            return
        var start_position: Vector3 = start_value
        var moved := Vector2(
            officer.get_world_position().x - start_position.x,
            officer.get_world_position().z - start_position.z
        ).length()
        if moved < 0.35:
            _fail("both Midi police officers must move in patrol: %s moved %.3f m" % [officer.name, moved])
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

    print("VISIBLE_CITY_RUNTIME_OK: civilians=%d police=%d reacting=%d responders=%d grounded_visuals=true dual_patrol=true route_separation=%.3f" % [
        int(counts.get("civilians", 0)),
        int(counts.get("police", 0)),
        civilians_reacting,
        police_in_response,
        route_separation,
    ])
    quit(0)

func _planar_segment_separation(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3) -> float:
    return minf(
        minf(_planar_point_segment_distance(a0, b0, b1), _planar_point_segment_distance(a1, b0, b1)),
        minf(_planar_point_segment_distance(b0, a0, a1), _planar_point_segment_distance(b1, a0, a1))
    )

func _planar_point_segment_distance(point: Vector3, segment_a: Vector3, segment_b: Vector3) -> float:
    var p := Vector2(point.x, point.z)
    var a := Vector2(segment_a.x, segment_a.z)
    var b := Vector2(segment_b.x, segment_b.z)
    var segment := b - a
    var length_squared := segment.length_squared()
    if length_squared <= 0.0001:
        return p.distance_to(a)
    var t := clampf((p - a).dot(segment) / length_squared, 0.0, 1.0)
    return p.distance_to(a + segment * t)

func _fail(message: String) -> void:
    if _failed:
        return
    _failed = true
    push_error(message)
    print("VISIBLE_CITY_RUNTIME_FAIL: %s" % message)
    quit(1)
