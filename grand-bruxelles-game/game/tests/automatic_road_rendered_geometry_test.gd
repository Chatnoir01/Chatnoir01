extends SceneTree

const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const ROAD_ID := 359177328


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("AUTOMATIC_ROAD_RENDERED_GEOMETRY_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var world := Node3D.new()
    world.name = "Main"
    root.add_child(world)

    var resolver := RESOLVER_SCRIPT.new()
    root.add_child(resolver)

    # A name-only decoy must never authorize a player-visible destination.
    var name_only_decoy := Node3D.new()
    name_only_decoy.name = "Road_%d_NameOnlyDecoy" % ROAD_ID
    world.add_child(name_only_decoy)
    if resolver._road_is_rendered(world, ROAD_ID):
        _fail("name-only Node3D was accepted as rendered road geometry")
        return
    name_only_decoy.queue_free()
    await process_frame

    # A visible GeometryInstance3D with no mesh payload is still not proof.
    var empty_mesh_decoy := MeshInstance3D.new()
    empty_mesh_decoy.name = "Road_%d_EmptyMeshDecoy" % ROAD_ID
    world.add_child(empty_mesh_decoy)
    await process_frame
    if resolver._road_is_rendered(world, ROAD_ID):
        _fail("visible MeshInstance3D without a mesh was accepted as rendered road geometry")
        return
    empty_mesh_decoy.queue_free()
    await process_frame

    # A non-null Mesh resource with zero surfaces also renders nothing.
    var zero_surface_mesh_decoy := MeshInstance3D.new()
    zero_surface_mesh_decoy.name = "Road_%d_ZeroSurfaceMeshDecoy" % ROAD_ID
    zero_surface_mesh_decoy.mesh = ArrayMesh.new()
    world.add_child(zero_surface_mesh_decoy)
    await process_frame
    if resolver._road_is_rendered(world, ROAD_ID):
        _fail("MeshInstance3D with zero mesh surfaces was accepted as rendered road geometry")
        return
    zero_surface_mesh_decoy.queue_free()
    await process_frame

    # A populated MultiMesh with zero visible instances also renders nothing.
    var zero_visible_multimesh_decoy := MultiMeshInstance3D.new()
    zero_visible_multimesh_decoy.name = "Road_%d_ZeroVisibleMultiMeshDecoy" % ROAD_ID
    var zero_visible_multimesh := MultiMesh.new()
    zero_visible_multimesh.mesh = BoxMesh.new()
    zero_visible_multimesh.instance_count = 1
    zero_visible_multimesh.visible_instance_count = 0
    zero_visible_multimesh_decoy.multimesh = zero_visible_multimesh
    world.add_child(zero_visible_multimesh_decoy)
    await process_frame
    if resolver._road_is_rendered(world, ROAD_ID):
        _fail("MultiMeshInstance3D with zero visible instances was accepted as rendered road geometry")
        return
    zero_visible_multimesh_decoy.queue_free()
    await process_frame

    # A MultiMesh with instances but an empty Mesh resource still renders nothing.
    var zero_surface_multimesh_decoy := MultiMeshInstance3D.new()
    zero_surface_multimesh_decoy.name = "Road_%d_ZeroSurfaceMultiMeshDecoy" % ROAD_ID
    var zero_surface_multimesh := MultiMesh.new()
    zero_surface_multimesh.mesh = ArrayMesh.new()
    zero_surface_multimesh.instance_count = 1
    zero_surface_multimesh.visible_instance_count = 1
    zero_surface_multimesh_decoy.multimesh = zero_surface_multimesh
    world.add_child(zero_surface_multimesh_decoy)
    await process_frame
    if resolver._road_is_rendered(world, ROAD_ID):
        _fail("MultiMeshInstance3D with zero mesh surfaces was accepted as rendered road geometry")
        return
    zero_surface_multimesh_decoy.queue_free()
    await process_frame

    # CSGPolygon3D is a CSGShape3D but its default empty polygon renders nothing.
    var empty_csg_polygon := CSGPolygon3D.new()
    empty_csg_polygon.name = "Road_%d_EmptyCSGPolygonDecoy" % ROAD_ID
    world.add_child(empty_csg_polygon)
    await process_frame
    if resolver._road_is_rendered(world, ROAD_ID):
        _fail("empty CSGPolygon3D was accepted as rendered road geometry")
        return
    empty_csg_polygon.queue_free()
    await process_frame

    # Three collinear points are still a zero-area profile and must fail closed.
    var collinear_csg_polygon := CSGPolygon3D.new()
    collinear_csg_polygon.name = "Road_%d_CollinearCSGPolygonDecoy" % ROAD_ID
    collinear_csg_polygon.polygon = PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(2.0, 0.0)])
    world.add_child(collinear_csg_polygon)
    await process_frame
    if resolver._road_is_rendered(world, ROAD_ID):
        _fail("collinear CSGPolygon3D was accepted as rendered road geometry")
        return
    collinear_csg_polygon.queue_free()
    await process_frame

    # Invalid nested polygon content must not make a matching combiner look rendered.
    var invalid_nested_combiner := CSGCombiner3D.new()
    invalid_nested_combiner.name = "Road_%d_InvalidNestedCombinerDecoy" % ROAD_ID
    var invalid_nested_polygon := CSGPolygon3D.new()
    invalid_nested_polygon.polygon = PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(2.0, 0.0)])
    invalid_nested_combiner.add_child(invalid_nested_polygon)
    world.add_child(invalid_nested_combiner)
    await process_frame
    if resolver._road_is_rendered(world, ROAD_ID):
        _fail("combiner with only degenerate CSGPolygon3D was accepted as rendered road geometry")
        return
    invalid_nested_combiner.queue_free()
    await process_frame

    # CSGCombiner3D inherits CSGShape3D but renders nothing without child CSG geometry.
    var empty_csg_combiner := CSGCombiner3D.new()
    empty_csg_combiner.name = "Road_%d_EmptyCSGCombinerDecoy" % ROAD_ID
    world.add_child(empty_csg_combiner)
    await process_frame
    if resolver._road_is_rendered(world, ROAD_ID):
        _fail("empty CSGCombiner3D was accepted as rendered road geometry")
        return
    empty_csg_combiner.queue_free()
    await process_frame

    # A valid nested polygon is real CSG content and must remain accepted.
    var valid_nested_combiner := CSGCombiner3D.new()
    valid_nested_combiner.name = "Road_%d_ValidNestedCombiner" % ROAD_ID
    var valid_nested_polygon := CSGPolygon3D.new()
    valid_nested_polygon.polygon = PackedVector2Array([Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0)])
    valid_nested_combiner.add_child(valid_nested_polygon)
    world.add_child(valid_nested_combiner)
    await process_frame
    if not resolver._road_is_rendered(world, ROAD_ID):
        _fail("combiner with valid visible CSGPolygon3D was rejected")
        return
    valid_nested_combiner.queue_free()
    await process_frame

    # Even real geometry is not player-visible evidence while hidden.
    var road_geometry := CSGBox3D.new()
    road_geometry.name = "Road_%d_VisibleGeometry" % ROAD_ID
    road_geometry.size = Vector3(4.0, 0.2, 12.0)
    road_geometry.visible = false
    world.add_child(road_geometry)
    await process_frame
    if resolver._road_is_rendered(world, ROAD_ID):
        _fail("hidden GeometryInstance3D was accepted as rendered road geometry")
        return

    road_geometry.visible = true
    await process_frame
    if not resolver._road_is_rendered(world, ROAD_ID):
        _fail("visible GeometryInstance3D with exact road identity was rejected")
        return

    print("AUTOMATIC_ROAD_RENDERED_GEOMETRY_GREEN: road_id=%d name_only_rejected=true empty_mesh_rejected=true zero_surface_mesh_rejected=true zero_visible_multimesh_rejected=true zero_surface_multimesh_rejected=true empty_csg_polygon_rejected=true collinear_csg_polygon_rejected=true invalid_nested_csg_polygon_rejected=true empty_csg_combiner_rejected=true valid_nested_csg_polygon_accepted=true hidden_geometry_rejected=true visible_geometry_accepted=true destination_advertisable=false jouable=false" % ROAD_ID)
    quit(0)
