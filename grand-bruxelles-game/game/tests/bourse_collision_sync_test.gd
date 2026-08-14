extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("BOURSE_COLLISION_SYNC_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    for _frame: int in range(5):
        await process_frame
    await physics_frame

    var reveal := main.get_node_or_null("BourseFrontWallReveal")
    var walls := main.get_node_or_null("UrbISHeroGeometry/Hero_Bourse/Walls") as MeshInstance3D
    if reveal == null or walls == null or walls.mesh == null:
        _fail("Bourse reveal or authoritative Walls mesh missing")
        return

    var removed_triangles := int(reveal.call("diagnostic_removed_triangles"))
    if removed_triangles <= 0:
        _fail("front reveal did not remove any source-bounded wall triangles")
        return

    if not bool(walls.get_meta("collision_synced_after_runtime_adjustments", false)):
        _fail("Walls collision was not rebuilt after runtime mesh adjustments")
        return

    var visible_vertex_count := walls.mesh.surface_get_array_len(0)
    var collision_source_vertex_count := int(walls.get_meta("collision_source_vertex_count", -1))
    if visible_vertex_count <= 0 or collision_source_vertex_count != visible_vertex_count:
        _fail("collision source does not match final visible Walls mesh: collision=%d visible=%d" % [collision_source_vertex_count, visible_vertex_count])
        return

    var collision_bodies := 0
    for child: Node in walls.get_children():
        if child is CollisionObject3D:
            collision_bodies += 1
    if collision_bodies != int(walls.get_meta("collision_body_count", -1)) or collision_bodies <= 0:
        _fail("final Walls mesh has no synchronized physical collision body")
        return

    print("BOURSE_COLLISION_SYNC_OK: removed_triangles=%d visible_vertices=%d collision_bodies=%d stale_invisible_wall=false" % [removed_triangles, visible_vertex_count, collision_bodies])
    quit(0)
