extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("TRAFFIC_GRAPH_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var graph_script: Script = load("res://game/scripts/traffic_road_graph.gd")
    if graph_script == null:
        _fail("traffic road graph script did not load")
        return

    var graph: RefCounted = graph_script.new()
    var roads: Array[Dictionary] = [
        {
            "osm_id": 1001,
            "name": "Rue Est-Ouest",
            "drivable": true,
            "oneway": 0,
            "points": [[0.0, 0.0], [10.0, 0.0], [20.0, 0.0]],
        },
        {
            "osm_id": 1002,
            "name": "Rue Nord-Sud",
            "drivable": true,
            "oneway": 0,
            "points": [[10.0, -10.0], [10.0, 0.0], [10.0, 10.0]],
        },
        {
            "osm_id": 1003,
            "name": "Sens unique",
            "drivable": true,
            "oneway": 1,
            "points": [[10.0, 0.0], [20.0, 10.0]],
        },
    ]
    graph.call("rebuild", roads)

    var node_count := int(graph.call("get_node_count"))
    var edge_count := int(graph.call("get_edge_count"))
    var intersection_count := int(graph.call("get_intersection_count"))
    if node_count != 6:
        _fail("expected 6 graph nodes, got %d" % node_count)
        return
    if edge_count != 9:
        _fail("expected 9 directed edges, got %d" % edge_count)
        return
    if intersection_count != 1:
        _fail("expected exactly one synthetic intersection, got %d" % intersection_count)
        return

    var reverse_oneway_found := false
    for edge_id: int in range(edge_count):
        var edge: Dictionary = graph.call("get_edge", edge_id)
        if int(edge.get("osm_id", 0)) != 1003:
            continue
        var start: Vector3 = edge.get("from", Vector3.ZERO)
        var finish: Vector3 = edge.get("to", Vector3.ZERO)
        if is_equal_approx(start.x, 20.0) and is_equal_approx(start.z, 10.0) \
        and is_equal_approx(finish.x, 10.0) and is_equal_approx(finish.z, 0.0):
            reverse_oneway_found = true
            break
    if reverse_oneway_found:
        _fail("one-way road incorrectly received a reverse directed edge")
        return

    var rng := RandomNumberGenerator.new()
    rng.seed = 7
    var walk: Array = graph.call("build_random_walk", 0, rng, 15.0, 80.0, 4)
    if walk.size() < 2:
        _fail("random walk did not continue through the intersection")
        return

    var first: Dictionary = graph.call("get_edge", int(walk[0]))
    var second: Dictionary = graph.call("get_edge", int(walk[1]))
    if str(second.get("to_key", "")) == str(first.get("from_key", "")):
        _fail("route performed an immediate U-turn at the intersection")
        return

    print(
        "TRAFFIC_GRAPH_OK: %d nodes, %d directed edges, %d intersection, walk=%s" %
        [node_count, edge_count, intersection_count, str(walk)]
    )
    quit(0)
