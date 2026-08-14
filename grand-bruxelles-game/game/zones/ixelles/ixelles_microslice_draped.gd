extends "res://game/zones/ixelles/ixelles_microslice.gd"

## Presentation-only StreetSurface drape for the bounded Ixelles micro-slice.
## Official source polygon boundaries are never moved. Each already-valid source polygon
## is first triangulated, then each source triangle is clipped against the exact 2 m DTM
## render triangles it overlaps. Added presentation vertices therefore stay inside the
## source polygon and inside one terrain triangle. Heights still resample sample_height()
## at every emitted vertex; a renderer-only 3.5 cm bias is applied above the actual DTM
## render triangle so this overlay makes no physical road-height claim.

const STREET_RENDER_BIAS_M := 0.035
const STREET_SOURCE_BOUNDARY_EPSILON_M := 0.02
const STREET_CLIP_EPSILON_M := 0.0001
const STREET_MAX_EXPECTED_EDGE_M := 2.829

var street_drape_triangle_count := 0
var street_drape_vertex_count := 0
var street_drape_outside_source_vertices := 0
var street_drape_rejected_outside_triangles := 0
var street_drape_unsupported_triangle_count := 0
var street_drape_clearance_refinement_count := 0
var street_drape_min_check_clearance_m := INF
var street_drape_max_leaf_edge_m := 0.0
var street_drape_max_subdivision_depth := 0
var street_drape_max_sampler_render_lift_m := 0.0
var street_drape_source_triangle_count := 0
var street_drape_clipped_piece_count := 0

func _point_segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
    var edge := b - a
    var length_sq := edge.length_squared()
    if length_sq <= 0.0000001:
        return point.distance_to(a)
    var t := clampf((point - a).dot(edge) / length_sq, 0.0, 1.0)
    return point.distance_to(a + edge * t)

func _point_in_or_on_polygon(point: Vector2, polygon: PackedVector2Array) -> bool:
    if Geometry2D.is_point_in_polygon(point, polygon):
        return true
    for i: int in range(polygon.size()):
        if _point_segment_distance(point, polygon[i], polygon[(i + 1) % polygon.size()]) <= STREET_SOURCE_BOUNDARY_EPSILON_M:
            return true
    return false

func _cross(a: Vector2, b: Vector2) -> float:
    return a.x * b.y - a.y * b.x

func _signed_area(polygon: PackedVector2Array) -> float:
    var area := 0.0
    for i: int in range(polygon.size()):
        area += _cross(polygon[i], polygon[(i + 1) % polygon.size()])
    return area * 0.5

func _line_intersection(segment_a: Vector2, segment_b: Vector2, clip_a: Vector2, clip_b: Vector2) -> Vector2:
    var segment := segment_b - segment_a
    var clip_edge := clip_b - clip_a
    var denominator := _cross(segment, clip_edge)
    if absf(denominator) <= 0.0000001:
        return segment_b
    var t := _cross(clip_a - segment_a, clip_edge) / denominator
    return segment_a + segment * clampf(t, 0.0, 1.0)

func _inside_clip_edge(point: Vector2, edge_a: Vector2, edge_b: Vector2, orientation: float) -> bool:
    return orientation * _cross(edge_b - edge_a, point - edge_a) >= -STREET_CLIP_EPSILON_M

func _clip_to_convex(subject: PackedVector2Array, clipper: PackedVector2Array) -> PackedVector2Array:
    if subject.size() < 3 or clipper.size() < 3:
        return PackedVector2Array()
    var orientation := 1.0 if _signed_area(clipper) >= 0.0 else -1.0
    var output := subject
    for edge_index: int in range(clipper.size()):
        if output.is_empty():
            break
        var input := output
        output = PackedVector2Array()
        var edge_a := clipper[edge_index]
        var edge_b := clipper[(edge_index + 1) % clipper.size()]
        var previous := input[input.size() - 1]
        var previous_inside := _inside_clip_edge(previous, edge_a, edge_b, orientation)
        for current: Vector2 in input:
            var current_inside := _inside_clip_edge(current, edge_a, edge_b, orientation)
            if current_inside:
                if not previous_inside:
                    output.append(_line_intersection(previous, current, edge_a, edge_b))
                output.append(current)
            elif previous_inside:
                output.append(_line_intersection(previous, current, edge_a, edge_b))
            previous = current
            previous_inside = current_inside
    return output

func _terrain_render_height(game_x: float, game_z: float) -> float:
    var e := _origin_e + (game_x - _world_anchor_x)
    var n := _origin_n - (game_z - _world_anchor_z)
    var col_f := (e - _bbox.position.x) / _spacing
    var row_f := (n - _bbox.position.y) / _spacing
    if col_f < -0.0001 or row_f < -0.0001 or col_f > float(_width - 1) + 0.0001 or row_f > float(_height - 1) + 0.0001:
        return NAN
    col_f = clampf(col_f, 0.0, float(_width - 1))
    row_f = clampf(row_f, 0.0, float(_height - 1))
    var c0 := clampi(int(floor(col_f)), 0, _width - 1)
    var r0 := clampi(int(floor(row_f)), 0, _height - 1)
    var c1 := mini(c0 + 1, _width - 1)
    var r1 := mini(r0 + 1, _height - 1)
    var tx := col_f - float(c0)
    var ty := row_f - float(r0)
    var h00 := _heights_relative[_index(r0, c0)]
    var h01 := _heights_relative[_index(r1, c0)]
    var h10 := _heights_relative[_index(r0, c1)]
    var h11 := _heights_relative[_index(r1, c1)]
    if tx + ty <= 1.0:
        return h00 + tx * (h10 - h00) + ty * (h01 - h00)
    return (1.0 - ty) * h10 + (1.0 - tx) * h01 + (tx + ty - 1.0) * h11

func _draped_height(point: Vector2) -> float:
    var sampled := sample_height(point.x, point.y)
    var rendered := _terrain_render_height(point.x, point.y)
    if not is_finite(rendered):
        return sampled + STREET_RENDER_BIAS_M
    street_drape_max_sampler_render_lift_m = maxf(street_drape_max_sampler_render_lift_m, rendered - sampled)
    return maxf(sampled, rendered) + STREET_RENDER_BIAS_M

func _emit_piece(target: SurfaceTool, source_ring: PackedVector2Array, piece: PackedVector2Array) -> void:
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
        var source_ok := true
        for point: Vector2 in [p0, p1, p2]:
            if not _point_in_or_on_polygon(point, source_ring):
                source_ok = false
                break
        if not source_ok:
            street_drape_rejected_outside_triangles += 1
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

func _game_to_grid(point: Vector2) -> Vector2:
    var e := _origin_e + (point.x - _world_anchor_x)
    var n := _origin_n - (point.y - _world_anchor_z)
    return Vector2((e - _bbox.position.x) / _spacing, (n - _bbox.position.y) / _spacing)

func _drape_source_triangle(target: SurfaceTool, source_ring: PackedVector2Array, source_triangle: PackedVector2Array) -> void:
    street_drape_source_triangle_count += 1
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
                _emit_piece(target, source_ring, clipped_a)
            var clipped_b := _clip_to_convex(source_triangle, terrain_b)
            if clipped_b.size() >= 3:
                _emit_piece(target, source_ring, clipped_b)
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
        var indices := Geometry2D.triangulate_polygon(ring)
        if indices.size() < 3:
            continue
        var key := str(feature.get("type", ""))
        if not grouped.has(key):
            var tool := SurfaceTool.new()
            tool.begin(Mesh.PRIMITIVE_TRIANGLES)
            tool.set_material(_surface_material(key))
            grouped[key] = tool
        var target: SurfaceTool = grouped[key]
        for offset: int in range(0, indices.size(), 3):
            var source_triangle := PackedVector2Array([ring[indices[offset]], ring[indices[offset + 1]], ring[indices[offset + 2]]])
            _drape_source_triangle(target, ring, source_triangle)
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

    print("IXELLES_STREET_DRAPE: surfaces=%d source_triangles=%d clipped_pieces=%d triangles=%d vertices=%d outside_source=%d rejected_outside=%d unsupported=%d min_clearance=%.5f max_leaf_edge=%.3f max_sampler_render_lift=%.5f" % [street_surface_count, street_drape_source_triangle_count, street_drape_clipped_piece_count, street_drape_triangle_count, street_drape_vertex_count, street_drape_outside_source_vertices, street_drape_rejected_outside_triangles, street_drape_unsupported_triangle_count, street_drape_min_check_clearance_m, street_drape_max_leaf_edge_m, street_drape_max_sampler_render_lift_m])
