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

    var streets := scene.get_node_or_null("OfficialStreetSurfaces") as MeshInstance3D
    var buildings := scene.get_node_or_null("OfficialBuildings") as MeshInstance3D
    if streets == null or streets.mesh == null:
        _fail("official UrbIS street surface mesh missing")
        return
    if buildings == null or buildings.mesh == null:
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

    var official_holes := int(stats.get("official_polygon_holes", 0))
    var palais5_cutouts := int(stats.get("palais5_source_cutouts", 0))
    if official_holes < 14:
        _fail("UrbIS polygon interior rings were discarded: %s" % stats)
        return
    if palais5_cutouts != 1:
        _fail("Palais 5 must be subtracted from exactly one Expo aggregate polygon: %s" % stats)
        return

    if streets.mesh.get_surface_count() <= 0 or buildings.mesh.get_surface_count() <= 0:
        _fail("topology-aware source meshes have no surfaces")
        return

    print("LAEKEN_JETTE_SMOKE_OK: official geometry + Atomium hero loaded; holes=%d palais5_cutouts=%d %s" % [official_holes, palais5_cutouts, JSON.stringify(stats)])
    scene.queue_free()
    await process_frame
    quit(0)
