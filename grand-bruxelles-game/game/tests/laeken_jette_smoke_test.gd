extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("LAEKEN_JETTE_SMOKE_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var packed: PackedScene = load("res://game/zones/laeken_jette/laeken_jette.tscn")
    if packed == null:
        _fail("zone scene did not load")
        return

    var scene: Node = packed.instantiate()
    root.add_child(scene)
    await process_frame

    var atomium := scene.get_node_or_null("AtomiumHero")
    if atomium == null:
        _fail("Atomium hero node missing")
        return

    var sphere_count := 0
    for child in atomium.get_children():
        if child.name.begins_with("Sphere_"):
            sphere_count += 1
    if sphere_count != 9:
        _fail("Atomium must have 9 spheres, got %d" % sphere_count)
        return

    if scene.get_node_or_null("OfficialStreetSurfaces") == null:
        _fail("official UrbIS street surface mesh missing")
        return
    if scene.get_node_or_null("OfficialBuildings") == null:
        _fail("official UrbIS building mesh missing")
        return
    if scene.get_node_or_null("OfficialTramNetwork") == null:
        _fail("official UrbIS tram mesh missing")
        return

    var stats: Dictionary = scene.get("last_stats")
    if int(stats.get("buildings", 0)) < 100:
        _fail("too few buildings in official slice: %s" % stats)
        return
    if int(stats.get("street_axes", 0)) < 50:
        _fail("too few street axes in official slice: %s" % stats)
        return
    if int(stats.get("street_surfaces", 0)) <= 0:
        _fail("street surface layer empty: %s" % stats)
        return
    if int(stats.get("tram_network", 0)) <= 0:
        _fail("tram layer empty: %s" % stats)
        return

    print("LAEKEN_JETTE_SMOKE_OK: official geometry + Atomium hero loaded %s" % JSON.stringify(stats))
    scene.queue_free()
    await process_frame
    quit(0)
