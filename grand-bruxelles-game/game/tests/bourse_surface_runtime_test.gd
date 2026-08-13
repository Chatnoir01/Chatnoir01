extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("BOURSE_SURFACE_RUNTIME_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    await process_frame
    await process_frame

    var surfaces := scene.get_node_or_null("UrbISBourseSurfaceContext")
    if surfaces == null:
        _fail("official Bourse surface node is missing")
        return
    var counts: Dictionary = surfaces.official_type_counts()
    var expected := {"I": 2, "P": 2, "S": 1, "SW": 2}
    if counts != expected:
        _fail("official type counts drifted: %s" % str(counts))
        return
    if int(surfaces.official_surface_count()) != 7:
        _fail("expected exactly 7 official Bourse surface polygons")
        return
    if int(surfaces.official_runtime_vertex_count()) != 195:
        _fail("expected exactly 195 runtime polygon vertices")
        return
    if absf(float(surfaces.official_source_area_m2()) - 2385.0) > 0.01:
        _fail("source area drifted")
        return
    if int(surfaces.official_triangle_count()) != 181:
        _fail("official surface triangle count drifted")
        return

    var mask := scene.get_node_or_null("UrbISBourseSurfaceMask")
    if mask == null:
        _fail("Bourse surface mask is missing")
        return
    if int(mask.diagnostic_axis_hidden_count()) != 3:
        _fail("the three superseded diagnostic axis strips were not hidden")
        return

    print(
        "BOURSE_SURFACE_RUNTIME_OK: 7 source-backed polygons, %d triangles, %.0f m2; StreetSurface 21944 added at LVL=0" %
        [surfaces.official_triangle_count(), surfaces.official_source_area_m2()]
    )
    scene.queue_free()
    quit(0)
