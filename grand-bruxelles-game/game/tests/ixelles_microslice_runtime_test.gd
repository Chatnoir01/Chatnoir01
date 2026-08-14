extends SceneTree

const SLICE_SCRIPT := preload("res://game/zones/ixelles/ixelles_microslice_draped.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("IXELLES_MICROSLICE_RUNTIME_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var slice := SLICE_SCRIPT.new()
    root.add_child(slice)
    await process_frame
    await process_frame
    if not slice.runtime_loaded:
        _fail("runtime did not load")
        return
    if slice.cell_id != "bxl-e149000-n169000-s500":
        _fail("wrong cell")
        return
    if slice.terrain_sample_count != 63001 or slice.terrain_triangle_count != 125000:
        _fail("2 m terrain topology drifted")
        return
    if slice.street_surface_count != 309 or slice.street_segment_count != 277:
        _fail("official street counts drifted")
        return
    if slice.street_drape_triangle_count <= 309 or slice.street_drape_vertex_count != slice.street_drape_triangle_count * 3:
        _fail("StreetSurface drape was not deterministically tessellated")
        return
    if slice.street_drape_triangle_count > 500000:
        _fail("StreetSurface drape triangle budget exceeded: %d" % slice.street_drape_triangle_count)
        return
    if slice.street_drape_outside_source_vertices != 0:
        _fail("densified StreetSurface vertex left its official source polygon")
        return
    if not is_finite(slice.street_drape_min_check_clearance_m) or slice.street_drape_min_check_clearance_m < -0.001:
        _fail("DTM-supported StreetSurface still drops beneath rendered terrain: %.6f m" % slice.street_drape_min_check_clearance_m)
        return
    if slice.street_drape_max_leaf_edge_m > 8.001:
        _fail("StreetSurface leaf edge exceeds adaptive presentation limit")
        return
    if slice.eligible_height_count != 260 or slice.building_count != 260 or slice.skipped_unapproved_height_buildings != 460:
        _fail("strong-height allowlist or fail-closed building count drifted")
        return
    if slice.get_node_or_null("StrongSourceBackedIxellesBuildings") == null:
        _fail("strong source-backed building root missing")
        return
    var collision := slice.get_node_or_null("OfficialIxellesDTMCollision/OfficialIxellesDTMHeightMapCollision") as CollisionShape3D
    if collision == null or not collision.shape is HeightMapShape3D:
        _fail("heightmap collision missing")
        return
    var shape := collision.shape as HeightMapShape3D
    if shape.map_width != 251 or shape.map_depth != 251 or shape.map_data.size() != 63001:
        _fail("collision grid drifted from render grid")
        return
    if absf(collision.scale.x - 2.0) > 0.0001 or absf(collision.scale.z - 2.0) > 0.0001:
        _fail("collision scale is not 2 m")
        return
    var sw := slice.lambert_to_game(149000.0, 169000.0)
    var ne := slice.lambert_to_game(149500.0, 169500.0)
    if absf(sw.x - 463.20577208066) > 0.001 or absf(sw.z - 1166.46414926197) > 0.001:
        _fail("Lambert72 -> game transform drifted at SW corner")
        return
    if absf(ne.x - 963.20577208066) > 0.001 or absf(ne.z - 666.46414926197) > 0.001:
        _fail("Lambert72 -> game transform drifted at NE corner")
        return
    var render_mesh := slice.get_node_or_null("OfficialIxellesDTMMesh") as MeshInstance3D
    if render_mesh == null or render_mesh.mesh == null:
        _fail("render mesh missing")
        return
    var arrays := render_mesh.mesh.surface_get_arrays(0)
    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    if vertices.size() != 63001:
        _fail("render vertex count drifted")
        return
    if absf(vertices[0].y) > 0.0001 or absf(shape.map_data[0]) > 0.0001:
        _fail("source-backed vertical reference is not shared by render/collision")
        return
    for index: int in [0, 250, 31500, 62750, 63000]:
        if absf(vertices[index].y - shape.map_data[index]) > 0.0001:
            _fail("collision/render height mismatch at %d" % index)
            return
    if slice.vertical_reference_absolute_m < 40.0 or slice.vertical_reference_absolute_m > 100.0:
        _fail("vertical reference is not a plausible official DTM elevation")
        return
    print("IXELLES_MICROSLICE_RUNTIME_OK: cell=%s samples=%d triangles=%d streets=%d drape_triangles=%d unsupported=%d drape_min_clearance=%.5f max_sampler_render_lift=%.5f buildings=%d skipped=%d reference_z=%.3f" % [slice.cell_id, slice.terrain_sample_count, slice.terrain_triangle_count, slice.street_surface_count, slice.street_drape_triangle_count, slice.street_drape_unsupported_triangle_count, slice.street_drape_min_check_clearance_m, slice.street_drape_max_sampler_render_lift_m, slice.building_count, slice.skipped_unapproved_height_buildings, slice.vertical_reference_absolute_m])
    quit(0)
