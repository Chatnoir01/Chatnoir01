extends "res://game/zones/ixelles/ixelles_microslice_draped.gd"

## Boundary-safe presentation layer for the same official Ixelles StreetSurfaces.
## Every DTM-aligned piece is intersected again with its exact official source polygon.
## This preserves the in-source portion of boundary pieces instead of dropping an entire
## DTM triangle when point-in-polygon classification is numerically ambiguous.

var street_drape_source_intersection_piece_count := 0
var street_drape_source_intersection_empty_count := 0

func _emit_piece(target: SurfaceTool, source_ring: PackedVector2Array, piece: PackedVector2Array) -> void:
    if piece.size() < 3:
        return
    var intersections: Array[PackedVector2Array] = Geometry2D.intersect_polygons(piece, source_ring)
    if intersections.is_empty():
        street_drape_source_intersection_empty_count += 1
        return
    for bounded_piece: PackedVector2Array in intersections:
        if bounded_piece.size() < 3:
            continue
        var indices := Geometry2D.triangulate_polygon(bounded_piece)
        if indices.size() < 3:
            continue
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
