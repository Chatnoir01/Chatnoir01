extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("LAEKEN_JETTE_BASE_SMOKE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var packed: PackedScene = load("res://game/zones/laeken_jette/laeken_jette_authoritative_base.tscn")
    if packed == null:
        _fail("authoritative base scene did not load")
        return
    var scene: Node = packed.instantiate()
    root.add_child(scene)
    await process_frame
    if scene.get_node_or_null("AtomiumHero") != null:
        _fail("base integration must not promote the provisional Atomium hero")
        return
    var streets := scene.get_node_or_null("OfficialStreetSurfaces") as MeshInstance3D
    var buildings := scene.get_node_or_null("OfficialBuildings") as MeshInstance3D
    if streets == null or streets.mesh == null:
        _fail("official UrbIS street surface mesh missing")
        return
    if buildings == null or buildings.mesh == null:
        _fail("official UrbIS building mesh missing")
        return
    if scene.get_node_or_null("OfficialTramNetwork") == null or scene.get_node_or_null("OfficialTrainNetwork") == null:
        _fail("official rail layers missing")
        return
    var stats: Dictionary = scene.get("last_stats")
    if int(stats.get("buildings", 0)) != 9518:
        _fail("expected 9518 official buildings: %s" % stats)
        return
    if int(stats.get("street_surfaces", 0)) != 3572:
        _fail("expected 3572 official street surfaces: %s" % stats)
        return
    if int(stats.get("street_axes", 0)) != 955:
        _fail("expected 955 official street axes: %s" % stats)
        return
    if int(stats.get("tram_network", 0)) != 326 or int(stats.get("train_network", 0)) != 326:
        _fail("official transit counts changed: %s" % stats)
        return
    if int(stats.get("palais5_source_cutouts", 0)) != 1:
        _fail("Palais 5 source cutout must remain exactly one: %s" % stats)
        return
    print("LAEKEN_JETTE_BASE_SMOKE_OK: %s" % JSON.stringify(stats))
    scene.queue_free()
    await process_frame
    quit(0)
