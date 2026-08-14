extends "res://game/zones/ixelles/ixelles_microslice_draped.gd"

## Exact source-partition guard layered on the DTM-aligned presentation drape.
## Geometry2D triangulates each official StreetSurface polygon into source triangles.
## We first prove each source triangle belongs to its source polygon, then require every
## clipped presentation vertex to remain in that triangle. This avoids boundary-only
## point-in-polygon numerical false negatives without widening or moving source geometry.

const STREET_SOURCE_TRIANGLE_EPSILON_M := 0.0005

var street_drape_invalid_source_partition_triangles := 0
var street_drape_exact_clip_rejections := 0

func _point_in_or_on_triangle(point: Vector2, triangle: PackedVector2Array) -> bool:
    if triangle.size() != 3:
        return false
    var a := triangle[0]
    var b := triangle[1]
    var c := triangle[2]
    var orientation := _cross(b - a, c - a)
    if absf(orientation) <= 0.0000001:
        return false
    var sign := 1.0 if orientation > 0.0 else -1.0
    return sign * _cross(b - a, point - a) >= -STREET_SOURCE_TRIANGLE_EPSILON_M \
        and sign * _cross(c - b, point - b) >= -STREET_SOURCE_TRIANGLE_EPSILON_M \
        and sign * _cross(a - c, point - c) >= -STREET_SOURCE_TRIANGLE_EPSILON_M

func _source_triangle_belongs_to_polygon(source_ring: PackedVector2Array, triangle: PackedVector2Array) -> bool:
    if triangle.size() != 3:
        return false
    var a := triangle[0]
    var b := triangle[1]
    var c := triangle[2]
    # All triangle corners are original source-ring vertices. Validate interior witnesses
    # so a malformed/self-crossing source polygon fails closed instead of being inferred.
    for witness: Vector2 in [(a + b + c) / 3.0, (a + b) * 0.5, (b + c) * 0.5, (c + a) * 0.5]:
        if not _point_in_or_on_polygon(witness, source_ring):
            return false
    return true

func _emit_exact_piece(target: SurfaceTool, source_triangle: PackedVector2Array, piece: PackedVector2Array) -> void:
    if piece.size() < 3:
        return
    var indices := Geometry2D.triangulate_polygon(piece)
    if indices.size() < 3:
        return
    street_drape_clipped_piece_count += 1
    for offset: int in range(0, indices.size(), 3):
        var p0 := piece[indices[offset]]
        var p1 := piece[indices[offset + 1]]
        var p2 := piece[indices[offset + 2]]
        var exact_source_ok := _point_in_or_on_triangle(p0, source_triangle) \
            and _point_in_or_on_triangle(p1, source_triangle) \
            and _point_in_or_on_triangle(p2, source_triangle)
        if not exact_source_ok:
            street_drape_exact_clip_rejections += 1
            continue
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

func _drape_source_triangle(target: SurfaceTool, source_ring: PackedVector2Array, source_triangle: PackedVector2Array) -> void:
    street_drape_source_triangle_count += 1
    if not _source_triangle_belongs_to_polygon(source_ring, source_triangle):
        street_drape_invalid_source_partition_triangles += 1
        return
    var grid0 := _game_to_grid(source_triangle[0])
    var grid1 := _game_to_grid(source_triangle[1])
    var grid2 := _game_to_grid(source_triangle[2])
    var min_col := clampi(int(floor(minf(grid0.x, minf(grid1.x, grid2.x)))), 0, _width - 2)
    var max_col := clampi(int(floor(maxf(grid0.x, maxf(grid1.x, grid2.x)))), 0, _width - 2)
    var min_row := clampi(int(floor(minf(grid0.y, minf(grid1.y, grid2.y)))), 0, _height - 2)
    var max_row := clampi(int(floor(maxf(grid0.y, maxf(grid1.y, grid2.y)))), 0, _height - 2)
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
            var clipped_a := _clip_to_convex(source_triangle, terrain_a)
            if clipped_a.size() >= 3:
                _emit_exact_piece(target, source_triangle, clipped_a)
            var clipped_b := _clip_to_convex(source_triangle, terrain_b)
            if clipped_b.size() >= 3:
                _emit_exact_piece(target, source_triangle, clipped_b)
    if street_drape_triangle_count == emitted_before:
        street_drape_unsupported_triangle_count += 1
