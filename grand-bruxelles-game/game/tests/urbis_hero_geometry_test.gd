extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("URBIS_HERO_GEOMETRY_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    await process_frame

    var old_osm := scene.get_node_or_null("BrusselsOSM/GeneratedBuildings/Building_13494623")
    if old_osm != null:
        _fail("the 6.3 m OSM fallback still renders beneath the authoritative hero")
        return
    var hero := scene.get_node_or_null("UrbISHeroGeometry/Hero_Bourse") as Node3D
    if hero == null:
        _fail("authoritative Bourse hero root is missing")
        return
    if int(hero.get_meta("triangle_count", 0)) != 1818:
        _fail("expected 1818 audited triangles, got %s" % hero.get_meta("triangle_count", 0))
        return
    if bool(hero.get_meta("source_runtime_approved", true)):
        _fail("runtime_approved must remain false until photo-match and performance proof pass")
        return
    var walls := hero.get_node_or_null("Walls") as MeshInstance3D
    var roofs := hero.get_node_or_null("Roofs") as MeshInstance3D
    if walls == null or roofs == null:
        _fail("wall or roof surface is missing")
        return
    var combined := walls.get_aabb().merge(roofs.get_aabb())
    if absf(combined.size.y - 40.1553) > 0.01:
        _fail("authoritative height mismatch: %.4f m" % combined.size.y)
        return
    if combined.size.x < 80.0 or combined.size.z < 70.0:
        _fail("authoritative footprint bounds are unexpectedly small: %s" % combined.size)
        return

    print(
        "URBIS_HERO_GEOMETRY_OK: Bourse %.4f m, 1818 triangles, OSM fallback suppressed" %
        combined.size.y
    )
    scene.queue_free()
    quit(0)
