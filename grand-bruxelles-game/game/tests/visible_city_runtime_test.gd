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

    var midi_counts: Dictionary = runtime.call("visible_population_counts")
    if int(midi_counts.get("civilians", 0)) < 8:
        _fail("expected at least 8 behavioral civilians at Midi")
        return
    if int(midi_counts.get("police", 0)) < 4:
        _fail("expected at least 4 visible police officers at Midi")
        return

    var routes_value: Variant = runtime.get("_routes")
    if not routes_value is Dictionary:
        _fail("VisibleCityRuntime route registry unavailable")
        return
    var routes: Dictionary = routes_value

    var midi_police := _collect_police_by_anchor("midi_fonsny_existing_sidewalk_alignment")
    if midi_police.size() < 4:
        _fail("expected four source-bounded Midi police patrols")
        return
    midi_police.sort_custom(func(a: NpcAgent, b: NpcAgent) -> bool: return a.variation_seed < b.variation_seed)
    if not _validate_visible_agents(get_nodes_in_group("living_city_agent")):
        return
    if not _validate_registered_routes(midi_police, routes, "Midi"):
        return

    var minimum_midi_route_separation := INF
    for first_index in range(midi_police.size()):
        var first_route: Array = routes[midi_police[first_index].get_instance_id()]
        for second_index in range(first_index + 1, midi_police.size()):
            var second_route: Array = routes[midi_police[second_index].get_instance_id()]
            var separation := _planar_segment_separation(
                first_route[0] as Vector3,
                first_route[1] as Vector3,
                second_route[0] as Vector3,
                second_route[1] as Vector3
            )
            minimum_midi_route_separation = minf(minimum_midi_route_separation, separation)
            if separation < 1.0:
                _fail("Midi police patrol routes overlap: %s/%s separation=%.3f m" % [
                    midi_police[first_index].name,
                    midi_police[second_index].name,
                    separation,
                ])
                return

    var midi_start_positions: Dictionary = {}
    for officer: NpcAgent in midi_police:
        midi_start_positions[officer.get_instance_id()] = officer.get_world_position()
    for _frame in range(120):
        await physics_frame
    for officer: NpcAgent in midi_police:
        if not is_instance_valid(officer) or not officer.active:
            _fail("Midi police patrol must remain active near Midi: %s" % officer.name)
            return
        var start_value: Variant = midi_start_positions.get(officer.get_instance_id(), officer.get_world_position())
        if not start_value is Vector3:
            _fail("Midi police patrol start position missing")
            return
        var moved := _planar_distance(officer.get_world_position(), start_value as Vector3)
        if moved < 0.35:
            _fail("Midi police patrol must move: %s moved %.3f m" % [officer.name, moved])
            return

    # Enter Bourse before mounting the LABO population. NpcAgent is distance-budgeted,
    # so remote Midi actors are allowed to deactivate once the player leaves Midi.
    var player := scene.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _fail("player missing before Bourse LABO approach")
        return
    var bourse_points_value: Variant = runtime.get("_bourse_points")
    if not bourse_points_value is Array:
        _fail("Bourse official sidewalk centroids unavailable")
        return
    var bourse_points: Array = bourse_points_value
    if bourse_points.is_empty() or not bourse_points[0] is Vector3:
        _fail("Bourse official sidewalk centroids empty")
        return
    var bourse_observer := bourse_points[0] as Vector3
    player.global_position = Vector3(bourse_observer.x, player.global_position.y, bourse_observer.z)

    var runtime_observer_value: Variant = runtime.call("_active_player_position")
    if not runtime_observer_value is Vector3:
        _fail("VisibleCity Bourse observer is not a Vector3")
        return
    var runtime_observer := runtime_observer_value as Vector3
    var observer_player_gap := _planar_distance(runtime_observer, player.global_position)
    if observer_player_gap > 1.0:
        _fail("VisibleCity observer did not follow player at Bourse: gap=%.3f player=%s observer=%s" % [
            observer_player_gap,
            player.global_position,
            runtime_observer,
        ])
        return

    runtime.call("ensure_zone_for_test", "bourse")
    for _frame in range(5):
        await process_frame

    var combined_counts: Dictionary = runtime.call("visible_population_counts")
    if not bool(combined_counts.get("bourse_spawned", false)):
        _fail("Bourse LABO population was not mounted")
        return
    if int(combined_counts.get("police", 0)) < 8:
        _fail("expected 4 Midi + 4 Bourse police instances after LABO mount")
        return

    var bourse_police := _collect_police_by_anchor("official_bourse_sidewalk_centroids")
    if bourse_police.size() < 4:
        _fail("expected four police officers on official Bourse sidewalk centroids")
        return
    bourse_police.sort_custom(func(a: NpcAgent, b: NpcAgent) -> bool: return a.variation_seed < b.variation_seed)
    if not _validate_visible_agents(get_nodes_in_group("living_city_agent")):
        return
    if not _validate_registered_routes(bourse_police, routes, "Bourse"):
        return
    for officer: NpcAgent in bourse_police:
        if not bool(officer.get_meta("source_bounded_runtime", false)):
            _fail("Bourse police must remain source-bounded: %s" % officer.name)
            return
        if str(officer.get_meta("source_anchor", "")) != "official_bourse_sidewalk_centroids":
            _fail("Bourse police lost official sidewalk provenance: %s" % officer.name)
            return
        var home := officer.behavior.home_position
        var captured_observer := officer.observer_position
        var observer_budget_gap := home.distance_to(captured_observer)
        if observer_budget_gap > officer.despawn_distance:
            _fail("Bourse police spawned outside observer budget: %s gap=%.3f home=%s observer=%s" % [
                officer.name,
                observer_budget_gap,
                home,
                captured_observer,
            ])
            return

    var bourse_start_positions: Dictionary = {}
    for officer: NpcAgent in bourse_police:
        bourse_start_positions[officer.get_instance_id()] = officer.get_world_position()
    for _frame in range(120):
        await physics_frame
    for officer: NpcAgent in bourse_police:
        if not is_instance_valid(officer) or not officer.active:
            _fail("Bourse police patrol must remain active near Bourse: %s home=%s observer=%s gap=%.3f" % [
                officer.name,
                officer.behavior.home_position,
                officer.observer_position,
                officer.behavior.home_position.distance_to(officer.observer_position),
            ])
            return
        var start_value: Variant = bourse_start_positions.get(officer.get_instance_id(), officer.get_world_position())
        if not start_value is Vector3:
            _fail("Bourse police patrol start position missing")
            return
        var moved := _planar_distance(officer.get_world_position(), start_value as Vector3)
        if moved < 0.35:
            _fail("Bourse police patrol must move: %s moved %.3f m" % [officer.name, moved])
            return

    runtime.call("trigger_incident_for_test", player.global_position)
    for _frame in range(5):
        await process_frame

    var police_in_response := 0
    for officer: NpcAgent in bourse_police:
        if officer.police_response.phase == NpcPoliceResponse.Phase.PURSUIT or officer.police_response.phase == NpcPoliceResponse.Phase.INVESTIGATE:
            police_in_response += 1

    var civilians_reacting := 0
    for node: Node in get_nodes_in_group("behavioral_civilian"):
        if not node is NpcAgent:
            continue
        var civilian := node as NpcAgent
        if str(civilian.get_meta("source_anchor", "")) != "official_bourse_sidewalk_centroids":
            continue
        if civilian.behavior.state == NpcBehaviorModel.State.FLEEING or civilian.behavior.state == NpcBehaviorModel.State.AVOIDING:
            civilians_reacting += 1

    if police_in_response < 1:
        _fail("Bourse incident did not activate Bourse police response")
        return
    if civilians_reacting < 1:
        _fail("Bourse incident did not produce a Bourse crowd reaction")
        return

    var hud_text := str(runtime.call("status_text_for_test"))
    if not hud_text.contains("POLICE"):
        _fail("player-facing police state is not exposed in the HUD")
        return

    print("VISIBLE_CITY_RUNTIME_OK: civilians=%d police=%d reacting=%d responders=%d grounded_visuals=true expanded_patrol=true midi_police=%d bourse_police=%d midi_route_separation=%.3f" % [
        int(combined_counts.get("civilians", 0)),
        int(combined_counts.get("police", 0)),
        civilians_reacting,
        police_in_response,
        midi_police.size(),
        bourse_police.size(),
        minimum_midi_route_separation,
    ])
    quit(0)

func _collect_police_by_anchor(anchor: String) -> Array[NpcAgent]:
    var result: Array[NpcAgent] = []
    for node: Node in get_nodes_in_group("police_officer"):
        if not node is NpcAgent:
            continue
        var officer := node as NpcAgent
        if str(officer.get_meta("source_anchor", "")) == anchor:
            result.append(officer)
    return result

func _validate_visible_agents(nodes: Array[Node]) -> bool:
    for node: Node in nodes:
        if not node is NpcAgent:
            _fail("living-city group must contain NpcAgent instances only")
            return false
        var agent := node as NpcAgent
        if not agent.has_meta("source_anchor"):
            _fail("visible agent missing source anchor metadata")
            return false
        if agent.get_node_or_null("RuntimeCharacterCollision") == null:
            _fail("visible NpcAgent missing completed physical collision")
            return false
        var legacy_visual := agent.get_node_or_null("VisibleHumanoid") as Node3D
        if legacy_visual == null:
            _fail("visible NpcAgent missing legacy/profile visual")
            return false
        if absf(legacy_visual.position.y - 0.90) > 0.001:
            _fail("ground-origin NpcAgent visual lift drifted for %s: y=%.3f" % [agent.name, legacy_visual.position.y])
            return false
    return true

func _validate_registered_routes(police_agents: Array[NpcAgent], routes: Dictionary, zone_name: String) -> bool:
    for officer: NpcAgent in police_agents:
        var route_value: Variant = routes.get(officer.get_instance_id(), [])
        if not route_value is Array:
            _fail("%s police patrol route was not registered: %s" % [zone_name, officer.name])
            return false
        var route: Array = route_value
        if route.size() < 2 or not route[0] is Vector3 or not route[1] is Vector3:
            _fail("%s police patrol route needs two Vector3 points: %s" % [zone_name, officer.name])
            return false
    return true

func _planar_distance(a: Vector3, b: Vector3) -> float:
    return Vector2(a.x - b.x, a.z - b.z).length()

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