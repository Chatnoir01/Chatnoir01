extends "res://game/zones/ixelles/ixelles_microslice_draped.gd"

## Direct official-polygon ∩ DTM-triangle presentation tessellation.
## No intermediate triangulation diagonals are introduced inside a StreetSurface polygon.
## Every emitted triangle is contained in one exact official source polygon and one exact
## 2 m DTM render triangle, then receives the existing renderer-only 3.5 cm depth bias.

var street_drape_source_intersection_piece_count := 0
var street_drape_source_intersection_empty_count := 0
var street_drape_source_polygon_count := 0

func _emit_bounded_piece(target: SurfaceTool, bounded_piece: PackedVector2Array) -> void:
    if bounded_piece.size() < 3:
        return
    var indices := Geometry2D.triangulate_polygon(bounded_piece)
    if indices.size() < 3:
        return
    street_drape_source_intersection_piece_count += 1
    street_drape_clipped_piece_count += 1
    for offset: int in range(0, indices.size(), 3):
        var p0 := bounded_piece[indices[offset]]
        var p1 := bounded_piece[indices[offset + 1]]
        var p2 := bounded_piece[indices[offset + 2]]
        var v0 := Vector3(p0.x, _draped_height(p0), p0.y)
        var v1 := Vector3(p1.x, _draped_height(p1), p1.y)
        var v2 := Vector3(p2.x, _draped_height(p2), p2.y)
        var max_edge := maxf(p0.distance_to(p1), maxf(p1.distance_to(p2), p2.distance_to(p0)))
        street_drape_max_leaf_edge_m = maxf(street_drape_max_leaf_edge_m, max_edge)
        var centroid := (v0 + v1 + v2) / 3.0
        var terrain_y := _terrain_render_height(centroid.x, centroid.z)
        if is_finite(terrain_y):
            street_drape_min_check_clearance_m = minf(street_drape_min_check_clearance_m, centroid.y - terrain_y)
        for vertex: Vector3 in [v0, v1, v2]:
            target.set_normal(Vector3.UP)
            target.add_vertex(vertex)
            street_drape_vertex_count += 1
        street_drape_triangle_count += 1

func _drape_source_polygon(target: SurfaceTool, source_ring: PackedVector2Array) -> void:
    street_drape_source_polygon_count += 1
    var min_col_f := INF
    var max_col_f := -INF
    var min_row_f := INF
    var max_row_f := -INF
    for point: Vector2 in source_ring:
        var grid := _game_to_grid(point)
        min_col_f = minf(min_col_f, grid.x)
        max_col_f = maxf(max_col_f, grid.x)
        min_row_f = minf(min_row_f, grid.y)
        max_row_f = maxf(max_row_f, grid.y)
    var min_col := clampi(int(floor(min_col_f)), 0, _width - 2)
    var max_col := clampi(int(floor(max_col_f)), 0, _width - 2)
    var min_row := clampi(int(floor(min_row_f)), 0, _height - 2)
    var max_row := clampi(int(floor(max_row_f)), 0, _height - 2)
    if max_col < min_col or max_row < min_row:
        street_drape_unsupported_triangle_count += 1
        return

    var emitted_before := street_drape_triangle_count
    for row: int in range(min_row, max_row + 1):
        for col: int in range(min_col, max_col + 1):
            var p00v := _grid_game_position(row, col)
            var p01v := _grid_game_position(row + 1, col)
            var p10v := _grid_game_position(row, col + 1)
            var p11v := _grid_game_position(row + 1, col + 1)
            var terrain_a := PackedVector2Array([Vector2(p00v.x, p00v.z), Vector2(p01v.x, p01v.z), Vector2(p10v.x, p10v.z)])
            var terrain_b := PackedVector2Array([Vector2(p10v.x, p10v.z), Vector2(p01v.x, p01v.z), Vector2(p11v.x, p11v.z)])
            var intersections_a: Array[PackedVector2Array] = Geometry2D.intersect_polygons(terrain_a, source_ring)
            if intersections_a.is_empty():
                street_drape_source_intersection_empty_count += 1
            else:
                for bounded_a: PackedVector2Array in intersections_a:
                    _emit_bounded_piece(target, bounded_a)
            var intersections_b: Array[PackedVector2Array] = Geometry2D.intersect_polygons(terrain_b, source_ring)
            if intersections_b.is_empty():
                street_drape_source_intersection_empty_count += 1
            else:
                for bounded_b: PackedVector2Array in intersections_b:
                    _emit_bounded_piece(target, bounded_b)
    if street_drape_triangle_count == emitted_before:
        street_drape_unsupported_triangle_count += 1

func _build_street_surfaces() -> void:
    var cell: Dictionary = get_meta("ixelles_cell_contract", {})
    var surfaces: Variant = cell.get("street_surfaces", [])
    if not surfaces is Array:
        return
    var grouped := {}
    for feature: Variant in surfaces:
        if not feature is Dictionary:
            continue
        var ring := _ring(feature.get("polygon", []))
        if ring.size() < 3:
            continue
        var key := str(feature.get("type", ""))
        if not grouped.has(key):
            var tool := SurfaceTool.new()
            tool.begin(Mesh.PRIMITIVE_TRIANGLES)
            tool.set_material(_surface_material(key))
            grouped[key] = tool
        _drape_source_polygon(grouped[key] as SurfaceTool, ring)
        street_surface_count += 1

    var root := Node3D.new()
    root.name = "OfficialIxellesStreetSurfaces"
    add_child(root)
    for key: Variant in grouped.keys():
        var mesh: ArrayMesh = (grouped[key] as SurfaceTool).commit()
        if mesh.get_surface_count() == 0:
            continue
        var instance := MeshInstance3D.new()
        instance.name = "StreetSurfaces_%s" % str(key)
        instance.mesh = mesh
        root.add_child(instance)

    var network: Dictionary = get_meta("ixelles_network_contract", {})
    var stats: Variant = network.get("stats", {})
    if stats is Dictionary:
        street_segment_count = int(stats.get("street_segments", 0))

    print("IXELLES_STREET_DRAPE: surfaces=%d source_polygons=%d source_intersections=%d triangles=%d vertices=%d outside_source=%d unsupported=%d min_clearance=%.5f max_leaf_edge=%.3f max_sampler_render_lift=%.5f" % [street_surface_count, street_drape_source_polygon_count, street_drape_source_intersection_piece_count, street_drape_triangle_count, street_drape_vertex_count, street_drape_outside_source_vertices, street_drape_unsupported_triangle_count, street_drape_min_check_clearance_m, street_drape_max_leaf_edge_m, street_drape_max_sampler_render_lift_m])
