extends SceneTree

func _fail(message: String) -> void:
    push_error("BOURSE_GROUND_VISIBILITY_FAIL: %s" % message)
    quit(1)

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    if scene == null:
        _fail("main scene did not instantiate")
        return
    root.add_child(scene)
    await process_frame
    await process_frame

    var controller := root.get_node_or_null("BourseGroundSurfaceVisibility")
    if controller != null and controller.has_method("apply_to_scene"):
        controller.call("apply_to_scene", scene)

    var hero := scene.get_node_or_null("UrbISHeroGeometry/Hero_Bourse")
    if hero == null:
        _fail("Hero_Bourse missing")
        return
    var ground := hero.get_node_or_null("Ground") as MeshInstance3D
    var walls := hero.get_node_or_null("Walls") as MeshInstance3D
    var roofs := hero.get_node_or_null("Roofs") as MeshInstance3D
    if ground == null or ground.mesh == null:
        _fail("official GROUNDSURFACE mesh missing")
        return
    if walls == null or not walls.visible or walls.mesh == null:
        _fail("official WALLSURFACE was hidden or lost")
        return
    if roofs == null or not roofs.visible or roofs.mesh == null:
        _fail("official ROOFSURFACE was hidden or lost")
        return

    var arrays: Array = ground.mesh.surface_get_arrays(0)
    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    if vertices.is_empty() or vertices.size() % 3 != 0:
        _fail("official GROUNDSURFACE triangle buffer was lost")
        return
    if ground.visible:
        _fail("LoD2 exterior-base GROUNDSURFACE is still presented as visible architecture")
        return
    if not bool(ground.get_meta("bourse_groundsurface_source_preserved", false)):
        _fail("source-preservation metadata missing")
        return
    var preserved := int(ground.get_meta("bourse_groundsurface_triangle_count_preserved", -1))
    if preserved != vertices.size() / 3:
        _fail("preserved triangle count drifted")
        return

    print("BOURSE_GROUND_VISIBILITY_OK preserved_triangles=%d walls_visible=true roofs_visible=true" % preserved)
    scene.queue_free()
    quit(0)
