extends "res://game/zones/ixelles/ixelles_microslice_draped.gd"

## Direct official-polygon ∩ DTM-triangle presentation tessellation.
## No intermediate triangulation diagonals are introduced inside a StreetSurface polygon.
## Every emitted triangle is contained in one exact official source polygon and one exact
## 2 m DTM render triangle, then receives the existing renderer-only 3.5 cm depth bias.

const BILINGUAL_SIGN_SCRIPT := preload("res://game/scripts/brussels_bilingual_street_sign.gd")
const IXELLES_STASSART_AXIS_ID := "https://databrussels.be/id/streetaxe/71374:2"
const IXELLES_STEPHANIE_AXIS_ID := "https://databrussels.be/id/streetaxe/71306:2"
const IXELLES_JUNCTION_EXPECTED := Vector2(735.808, 926.900)
const IXELLES_JUNCTION_TOLERANCE_M := 0.001

var street_drape_source_intersection_piece_count := 0
var street_drape_source_intersection_empty_count := 0
var street_drape_source_polygon_count := 0
var identity_cue_built := false
var identity_cue_plaque_count := 0
var identity_cue_anchor := Vector3.ZERO
var identity_cue_mount_surveyed := false

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

func _axis_contract(axis_id: String) -> Dictionary:
    var network: Dictionary = get_meta("ixelles_network_contract", {})
    var axes: Variant = network.get("street_axes", [])
    if not axes is Array:
        return {}
    for raw: Variant in axes:
        if raw is Dictionary and str(raw.get("id", "")) == axis_id:
            return raw
    return {}

func _axis_points(axis: Dictionary) -> PackedVector2Array:
    var result := PackedVector2Array()
    var points: Variant = axis.get("points", [])
    if not points is Array:
        return result
    for raw: Variant in points:
        if not raw is Array or raw.size() < 2:
            return PackedVector2Array()
        result.append(Vector2(float(raw[0]), float(raw[1])))
    return result

func _shared_axis_endpoint(a: PackedVector2Array, b: PackedVector2Array) -> Vector2:
    for pa: Vector2 in a:
        for pb: Vector2 in b:
            if pa.distance_to(pb) <= IXELLES_JUNCTION_TOLERANCE_M:
                return (pa + pb) * 0.5
    return Vector2(INF, INF)

func _build_identity_cue() -> void:
    var stassart := _axis_contract(IXELLES_STASSART_AXIS_ID)
    var stephanie := _axis_contract(IXELLES_STEPHANIE_AXIS_ID)
    if stassart.is_empty() or stephanie.is_empty():
        push_error("Ixelles identity cue: authoritative StreetAxis contract unavailable")
        return
    if str(stassart.get("street_fr", "")) != "Rue de Stassart" or str(stassart.get("street_nl", "")) != "de Stassartstraat":
        push_error("Ixelles identity cue: Rue de Stassart bilingual source name drifted")
        return
    if str(stephanie.get("street_fr", "")) != "Place Stéphanie" or str(stephanie.get("street_nl", "")) != "Stefaniaplein":
        push_error("Ixelles identity cue: Place Stephanie bilingual source name drifted")
        return

    var stassart_points := _axis_points(stassart)
    var stephanie_points := _axis_points(stephanie)
    if stassart_points.size() != 2 or stephanie_points.size() != 2:
        push_error("Ixelles identity cue: source StreetAxis geometry malformed")
        return
    var junction := _shared_axis_endpoint(stassart_points, stephanie_points)
    if not is_finite(junction.x) or junction.distance_to(IXELLES_JUNCTION_EXPECTED) > IXELLES_JUNCTION_TOLERANCE_M:
        push_error("Ixelles identity cue: shared authoritative junction endpoint drifted")
        return

    var ground := maxf(sample_height(junction.x, junction.y), _terrain_render_height(junction.x, junction.y)) + STREET_RENDER_BIAS_M
    if not is_finite(ground):
        push_error("Ixelles identity cue: DTM ground unavailable")
        return

    var root := Node3D.new()
    root.name = "IxellesBilingualJunctionCue"
    root.position = Vector3(junction.x, ground, junction.y)
    root.set_meta("source_axis_stassart", IXELLES_STASSART_AXIS_ID)
    root.set_meta("source_axis_stephanie", IXELLES_STEPHANIE_AXIS_ID)
    root.set_meta("source_shared_endpoint", junction)
    root.set_meta("claims_surveyed_mount", false)
    add_child(root)

    # Authored presentation-only support. The geographic anchor is source-derived;
    # pole dimensions/material and witness-facing yaw are not surveyed claims.
    var pole_mesh := CylinderMesh.new()
    pole_mesh.height = 2.45
    pole_mesh.top_radius = 0.035
    pole_mesh.bottom_radius = 0.035
    var pole_material := StandardMaterial3D.new()
    pole_material.albedo_color = Color(0.07, 0.08, 0.10, 1.0)
    pole_material.roughness = 0.82
    pole_mesh.material = pole_material
    var pole := MeshInstance3D.new()
    pole.name = "AuthoredPresentationPole"
    pole.mesh = pole_mesh
    pole.position.y = 1.225
    root.add_child(pole)

    var witness_direction := (stassart_points[0] - junction).normalized()
    var witness_target := Vector3(witness_direction.x, 0.0, witness_direction.y)

    var stassart_sign := BILINGUAL_SIGN_SCRIPT.new()
    stassart_sign.name = "RueDeStassartPlaque"
    stassart_sign.french_name = "RUE DE STASSART"
    stassart_sign.dutch_name = "DE STASSARTSTRAAT"
    stassart_sign.position.y = 2.24
    root.add_child(stassart_sign)
    stassart_sign.look_at(stassart_sign.global_position + witness_target, Vector3.UP)

    var stephanie_sign := BILINGUAL_SIGN_SCRIPT.new()
    stephanie_sign.name = "PlaceStephaniePlaque"
    stephanie_sign.french_name = "PLACE STÉPHANIE"
    stephanie_sign.dutch_name = "STEFANIAPLEIN"
    stephanie_sign.position.y = 1.84
    root.add_child(stephanie_sign)
    stephanie_sign.look_at(stephanie_sign.global_position + witness_target, Vector3.UP)

    identity_cue_anchor = root.global_position
    identity_cue_plaque_count = 2
    identity_cue_mount_surveyed = false
    identity_cue_built = true

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

    _build_identity_cue()
    print("IXELLES_STREET_DRAPE: surfaces=%d source_polygons=%d source_intersections=%d triangles=%d vertices=%d outside_source=%d unsupported=%d min_clearance=%.5f max_leaf_edge=%.3f max_sampler_render_lift=%.5f" % [street_surface_count, street_drape_source_polygon_count, street_drape_source_intersection_piece_count, street_drape_triangle_count, street_drape_vertex_count, street_drape_outside_source_vertices, street_drape_unsupported_triangle_count, street_drape_min_check_clearance_m, street_drape_max_leaf_edge_m, street_drape_max_sampler_render_lift_m])
