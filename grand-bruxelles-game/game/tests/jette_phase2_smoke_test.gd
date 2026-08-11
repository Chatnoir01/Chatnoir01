extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("JETTE_PHASE2_SMOKE_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var packed: PackedScene = load("res://game/zones/laeken_jette/jette_phase2.tscn")
    if packed == null:
        _fail("Jette phase 2 scene did not load")
        return

    var scene: Node = packed.instantiate()
    root.add_child(scene)
    await process_frame

    for node_name in [
        "JetteOfficialStreetSurfaces",
        "JetteOfficialBuildings",
        "JetteOfficialTrainNetwork",
        "JetteStationOfficialFootprintHero",
        "JetteStationStoneBand",
    ]:
        if scene.get_node_or_null(node_name) == null:
            _fail("required node missing: %s" % node_name)
            return

    var stats: Dictionary = scene.get("last_stats")
    if int(stats.get("buildings", 0)) < 100:
        _fail("too few official buildings: %s" % stats)
        return
    if int(stats.get("street_axes", 0)) < 50:
        _fail("too few official street axes: %s" % stats)
        return
    if int(stats.get("street_surfaces", 0)) <= 0:
        _fail("official street surfaces empty: %s" % stats)
        return
    if int(stats.get("train_network", 0)) <= 0:
        _fail("official train network empty: %s" % stats)
        return

    var station_distance := float(scene.get("station_feature_distance_m"))
    if not is_finite(station_distance) or station_distance > 100.0:
        _fail("station footprint identification too far from sourced station anchor: %.2f m" % station_distance)
        return

    print("JETTE_PHASE2_SMOKE_OK: official geometry + sourced station footprint loaded %s distance=%.2f" % [JSON.stringify(stats), station_distance])
    scene.queue_free()
    await process_frame
    quit(0)
