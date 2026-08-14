extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_SIDEWALK_RUNTIME_FAIL: %s" % message)
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
    var overlay := scene.get_node_or_null("BourseFrontWallReveal/OfficialSidewalkOverlay")
    if overlay == null:
        _fail("official sidewalk overlay missing")
        return
    if int(overlay.official_sidewalk_overlay_count()) != 5:
        _fail("expected 5 bounded sidewalk polygons")
        return
    if int(overlay.official_sidewalk_overlay_vertex_count()) != 62:
        _fail("expected 62 sidewalk vertices")
        return
    if int(overlay.official_sidewalk_overlay_triangle_count()) != 52:
        _fail("expected 52 sidewalk triangles")
        return
    if not bool(overlay.sidewalk_overlay_height_is_renderer_bias_only()):
        _fail("overlay must not claim physical curb elevation")
        return
    var sidewalk_mesh := overlay.get_node_or_null("OfficialBourseSidewalkMesh") as MeshInstance3D
    if sidewalk_mesh == null or sidewalk_mesh.mesh == null:
        _fail("official sidewalk render mesh missing")
        return
    var material := sidewalk_mesh.mesh.surface_get_material(0) as StandardMaterial3D
    if material == null:
        _fail("official sidewalk material missing")
        return
    if str(material.get_meta("source_material_identity", "")) != "blue_stone_paving":
        _fail("official Bourse foreground must use the source-confirmed blue-stone paving family")
        return
    if not bool(material.get_meta("authored_presentation_values", false)):
        _fail("uncalibrated paving presentation values must stay explicitly authored")
        return
    if bool(material.get_meta("copyrighted_photo_texture_used", true)):
        _fail("paving family must not embed a copyrighted photo texture")
        return
    print("BOURSE_SIDEWALK_RUNTIME_OK: 5 official foreground sidewalk polygons; source-confirmed blue-stone paving; curb elevation unresolved")
    scene.queue_free()
    quit(0)
