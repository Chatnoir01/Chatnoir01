extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("JETTE_STATION_VISUAL_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var packed: PackedScene = load("res://game/zones/laeken_jette/jette_phase2.tscn")
    if packed == null:
        _fail("Jette phase 2 scene did not load")
        return

    var scene := packed.instantiate()
    root.add_child(scene)
    await process_frame
    await process_frame

    var hero := scene.get_node_or_null("JetteStationOfficialFootprintHero")
    if hero == null:
        _fail("authoritative UrbIS station footprint hero disappeared")
        return

    var visual := scene.get_node_or_null("JetteStationVisualPass")
    if visual == null:
        _fail("station visual pass missing")
        return

    var stats: Dictionary = visual.get("visual_stats")
    if int(stats.get("window_panels", 0)) < 12:
        _fail("insufficient facade articulation: %s" % JSON.stringify(stats))
        return
    if int(stats.get("stone_bands", 0)) != 2:
        _fail("stone datum contract failed: %s" % JSON.stringify(stats))
        return
    if int(stats.get("canopy_segments", 0)) != 1:
        _fail("canopy cue contract failed: %s" % JSON.stringify(stats))
        return
    if visual.get_node_or_null("JetteStationCanopy") == null:
        _fail("canopy mesh missing")
        return

    var source_stats: Dictionary = scene.get("last_stats")
    if int(source_stats.get("buildings", 0)) < 100:
        _fail("official Jette geometry no longer loaded: %s" % JSON.stringify(source_stats))
        return

    print("JETTE_STATION_VISUAL_TEST_OK: source_backed_envelope=true stats=%s" % JSON.stringify(stats))
    scene.queue_free()
    await process_frame
    quit(0)
