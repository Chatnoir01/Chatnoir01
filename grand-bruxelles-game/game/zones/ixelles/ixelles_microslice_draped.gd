extends "res://game/zones/ixelles/ixelles_microslice.gd"

## Presentation-only StreetSurface drape for the bounded Ixelles micro-slice.
## Source polygon boundaries are unchanged. Added vertices are internal tessellation only
## and are re-sampled against the same official 2 m DTM used by the base slice.

const STREET_RENDER_BIAS_M := 0.035
const STREET_MAX_EDGE_M := 2.0
const STREET_MIN_CHECK_CLEARANCE_M := 0.004
const STREET_MAX_SUBDIVISION_DEPTH := 8

var street_drape_triangle_count := 0
var street_drape_vertex_count := 0
var street_drape_outside_source_vertices := 0
var street_drape_min_check_clearance_m := INF
var street_drape_max_leaf_edge_m := 0.0
var street_drape_max_subdivision_depth := 0

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
        if _point_segment_distance(point, polygon[i], polygon[(i + 1) % polygon.size()]) <= 0.001:
            return true
    return false

func _draped_vertex(point: Vector2) -> Vector3:
    return Vector3(point.x, sample_height(point.x, point.y) + STREET_RENDER_BIAS_M, point.y)

func _leaf_clearance(a: Vector3, b: Vector3, c: Vector3) -> float:
    var minimum := INF
    var centroid := (a + b + c) / 3.0
    var ab := (a + b) * 0.5
    var bc := (b + c) * 0.5
    var ca := (c + a) * 0.5
    for point: Vector3 in [centroid, ab, bc, ca]:
        var terrain_y := sample_height(point.x, point.z)
        minimum = minf(minimum, point.y - terrain_y)
    return minimum

func _emit_draped_triangle(target: SurfaceTool, source_ring: PackedVector2Array, a2: Vector2, b2: Vector2, c2: Vector2, depth: int) -> void:
    var a := _draped_vertex(a2)
    var b := _draped_vertex(b2)
    var c := _draped_vertex(c2)
    var max_edge := maxf(a2.distance_to(b2), maxf(b2.distance_to(c2), c2.distance_to(a2)))
    var clearance := _leaf_clearance(a, b, c)
    var needs_split := max_edge > STREET_MAX_EDGE_M or clearance < STREET_MIN_CHECK_CLEARANCE_M
    if needs_split and depth < STREET_MAX_SUBDIVISION_DEPTH:
        var ab2 := (a2 + b2) * 0.5
        var bc2 := (b2 + c2) * 0.5
        var ca2 := (c2 + a2) * 0.5
        _emit_draped_triangle(target, source_ring, a2, ab2, ca2, depth + 1)
        _emit_draped_triangle(target, source_ring, ab2, b2, bc2, depth + 1)
        _emit_draped_triangle(target, source_ring, ca2, bc2, c2, depth + 1)
        _emit_draped_triangle(target, source_ring, ab2, bc2, ca2, depth + 1)
        return

    street_drape_max_subdivision_depth = maxi(street_drape_max_subdivision_depth, depth)
    street_drape_max_leaf_edge_m = maxf(street_drape_max_leaf_edge_m, max_edge)
    street_drape_min_check_clearance_m = minf(street_drape_min_check_clearance_m, clearance)
    for point2: Vector2 in [a2, b2, c2]:
        if not _point_in_or_on_polygon(point2, source_ring):
            street_drape_outside_source_vertices += 1
    for vertex: Vector3 in [a, b, c]:
        target.set_normal(Vector3.UP)
        target.add_vertex(vertex)
        street_drape_vertex_count += 1
    street_drape_triangle_count += 1

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
            var a2 := ring[indices[offset]]
            var b2 := ring[indices[offset + 1]]
            var c2 := ring[indices[offset + 2]]
            _emit_draped_triangle(target, ring, a2, b2, c2, 0)
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

    print("IXELLES_STREET_DRAPE: surfaces=%d triangles=%d vertices=%d outside=%d min_clearance=%.5f max_leaf_edge=%.3f depth=%d" % [street_surface_count, street_drape_triangle_count, street_drape_vertex_count, street_drape_outside_source_vertices, street_drape_min_check_clearance_m, street_drape_max_leaf_edge_m, street_drape_max_subdivision_depth])
