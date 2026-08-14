extends SceneTree

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
    for _frame in range(5):
        await process_frame

    var minimap := scene.get_node_or_null("MiniMap")
    if minimap == null:
        _fail("MiniMap missing")
        return
    if not minimap.has_method("force_route_for_test"):
        _fail("mission GPS API missing")
        return

    var start := Vector2(-668.5, 627.84)
    var anneessens := Vector2(-272.04, -217.07)
    var route_value: Variant = minimap.call("force_route_for_test", start, anneessens)
    if not route_value is Array:
        _fail("route result is not an array")
        return
    var route: Array = route_value
    var snapshot: Dictionary = minimap.call("route_snapshot_for_test")
    if int(snapshot.get("graph_points", 0)) < 100:
        _fail("OSM road graph is unexpectedly small")
        return
    if route.size() < 3:
        _fail("Midi -> Anneessens did not resolve onto OSM road graph")
        return
    var first_value: Variant = route[0]
    var last_value: Variant = route[route.size() - 1]
    if not first_value is Vector2 or not last_value is Vector2:
        _fail("route endpoints are invalid")
        return
    if (first_value as Vector2).distance_to(start) > 0.5:
        _fail("route does not start at active actor")
        return
    if (last_value as Vector2).distance_to(anneessens) > 0.5:
        _fail("route does not end at mission target")
        return
    var distance := float(snapshot.get("distance_m", 0.0))
    if distance < start.distance_to(anneessens) or distance > 2500.0:
        _fail("route distance is implausible: %.1f m" % distance)
        return

    var bourse := Vector2(81.54, -664.58)
    var grand_place := Vector2(319.01, -535.20)
    var return_route: Array = minimap.call("force_route_for_test", grand_place, bourse)
    if return_route.size() < 3:
        _fail("Grand-Place -> Bourse return mission route missing")
        return

    print("MISSION_GPS_OK: graph=%d midi_anneessens_points=%d distance=%.1f return_points=%d" % [
        int(snapshot.get("graph_points", 0)), route.size(), distance, return_route.size()
    ])
    quit(0)

func _fail(message: String) -> void:
    push_error(message)
    print("MISSION_GPS_FAIL: %s" % message)
    quit(1)
