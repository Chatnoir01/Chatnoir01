extends Node3D

## Source-bounded immediate ground context for the Atomium.
## Geometry comes only from the committed UrbIS StreetSurfaces layer and is
## draped over the already accepted Atomium DTM. The gray material is authored
## presentation only: no asphalt, paving recipe, colour or photometry is inferred.

@export_file("*.json") var surfaces_path := "res://data/urbis/laeken_jette/street_surfaces.game.json"
@export_file("*.json") var manifest_path := "res://data/urbis/laeken_jette/manifest.json"
@export var context_radius_m := 100.0
@export var surface_offset_m := 0.045

var context_built := false
var source_crs := ""
var source_total_feature_count := 0
var source_feature_count := 0
var source_polygon_count := 0
var triangle_count := 0
var max_vertex_radius_m := 0.0
var material_photometry_resolved := false
var paving_material_resolved := false

var _anchor_xz := Vector2.ZERO
var _surfaces: Array[Dictionary] = []

func build_on_terrain(terrain: Node) -> bool:
    if context_built:
        return true
    if terrain == null or not bool(terrain.get("terrain_loaded")):
        push_error("AtomiumStreetSurfaceContext: official DTM unavailable")
        return false

    var anchor: Vector3 = terrain.get("atomium_game_position")
    _anchor_xz = Vector2(anchor.x, anchor.z)
    if not _load_source_contract():
        return false

    var width := int(terrain.get("width"))
    var height := int(terrain.get("height"))
    var first_e := float(terrain.get("first_e"))
    var first_n := float(terrain.get("first_n"))
    var step_e := float(terrain.get("step_e"))
    var step_n := float(terrain.get("step_n"))
    var origin_e := float(terrain.get("origin_e"))
    var origin_n := float(terrain.get("origin_n"))
    var heights: PackedFloat32Array = terrain.get("heights")
    var valid_mask: PackedByteArray = terrain.get("valid_mask")
    if width < 2 or height < 2 or heights.size() != width * height or valid_mask.size() != heights.size():
        push_error("AtomiumStreetSurfaceContext: DTM grid contract invalid")
        return false

    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    for row: int in range(height - 1):
        for col: int in range(width - 1):
            var i0 := row * width + col
            var i1 := (row + 1) * width + col
            var i2 := row * width + col + 1
            var i3 := (row + 1) * width + col + 1
            if valid_mask[i0] != 0 and valid_mask[i1] != 0 and valid_mask[i2] != 0:
                _append_if_official(vertices, normals, [i0, i1, i2], width, first_e, first_n, step_e, step_n, origin_e, origin_n, heights)
            if valid_mask[i2] != 0 and valid_mask[i1] != 0 and valid_mask[i3] != 0:
                _append_if_official(vertices, normals, [i2, i1, i3], width, first_e, first_n, step_e, step_n, origin_e, origin_n, heights)

    triangle_count = vertices.size() / 3
    if triangle_count <= 0:
        push_error("AtomiumStreetSurfaceContext: official surfaces produced no DTM triangles")
        return false

    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

    var material := StandardMaterial3D.new()
    # Neutral authored presentation only. UrbIS resolves geometry/class, not a
    # measured paving recipe or calibrated material response.
    material.albedo_color = Color(0.34, 0.35, 0.36, 1.0)
    material.roughness = 0.96
    material.metallic = 0.0
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.set_meta("atomium_ground_source", "urbisvector:StreetSurfaces")
    material.set_meta("atomium_ground_material_photometry_resolved", false)
    material.set_meta("atomium_ground_paving_material_resolved", false)
    mesh.surface_set_material(0, material)

    var instance := MeshInstance3D.new()
    instance.name = "OfficialAtomiumStreetSurfaces"
    instance.mesh = mesh
    add_child(instance)

    context_built = true
    print("ATOMIUM_STREET_SURFACE_CONTEXT_READY: selected_features=%d polygons=%d triangles=%d radius=%.1f max_vertex_radius=%.3f material_resolved=false" % [source_feature_count, source_polygon_count, triangle_count, context_radius_m, max_vertex_radius_m])
    return true

func _append_if_official(vertices: PackedVector3Array, normals: PackedVector3Array, ids: Array, width: int, first_e: float, first_n: float, step_e: float, step_n: float, origin_e: float, origin_n: float, heights: PackedFloat32Array) -> void:
    var points: Array[Vector2] = []
    for raw_id: Variant in ids:
        var idx := int(raw_id)
        var row := idx / width
        var col := idx % width
        var source_e := first_e + float(col) * step_e
        var source_n := first_n + float(row) * step_n
        points.append(Vector2(source_e - origin_e, -(source_n - origin_n)))

    var centroid := (points[0] + points[1] + points[2]) / 3.0
    if centroid.distance_to(_anchor_xz) > context_radius_m:
        return
    if not _triangle_inside_same_surface(points):
        return

    for index: int in range(3):
        var radius := points[index].distance_to(_anchor_xz)
        if radius > context_radius_m + 1.5:
            return

    for index: int in range(3):
        var idx := int(ids[index])
        max_vertex_radius_m = maxf(max_vertex_radius_m, points[index].distance_to(_anchor_xz))
        vertices.append(Vector3(points[index].x, heights[idx] + surface_offset_m, points[index].y))
        normals.append(Vector3.UP)

func _triangle_inside_same_surface(points: Array[Vector2]) -> bool:
    var centroid := (points[0] + points[1] + points[2]) / 3.0
    for surface: Dictionary in _surfaces:
        if not _point_in_surface(centroid, surface):
            continue
        if _point_in_surface(points[0], surface) and _point_in_surface(points[1], surface) and _point_in_surface(points[2], surface):
            return true
    return false

func _load_source_contract() -> bool:
    var manifest := _load_dictionary(manifest_path)
    if manifest.is_empty():
        push_error("AtomiumStreetSurfaceContext: UrbIS manifest unavailable")
        return false
    source_crs = str(manifest.get("source_crs", ""))
    if source_crs != "EPSG:31370" or str(manifest.get("source", "")) != "Paradigm / Brussels-Capital Region UrbIS vector WFS":
        push_error("AtomiumStreetSurfaceContext: UrbIS source contract drifted")
        return false
    var layers: Dictionary = manifest.get("layers", {}) as Dictionary
    var layer: Dictionary = layers.get("street_surfaces", {}) as Dictionary
    if str(layer.get("type_name", "")) != "urbisvector:StreetSurfaces":
        push_error("AtomiumStreetSurfaceContext: StreetSurfaces source class drifted")
        return false
    source_total_feature_count = int(layer.get("features", 0))
    if source_total_feature_count <= 0:
        return false

    var document := _load_dictionary(surfaces_path)
    var features: Variant = document.get("features", [])
    if not features is Array or features.size() != source_total_feature_count:
        push_error("AtomiumStreetSurfaceContext: committed game layer does not match manifest")
        return false

    _surfaces.clear()
    source_feature_count = 0
    source_polygon_count = 0
    for raw_feature: Variant in features as Array:
        if not raw_feature is Dictionary:
            continue
        var geometry: Variant = (raw_feature as Dictionary).get("geometry", {})
        if not geometry is Dictionary:
            continue
        var selected_in_feature := false
        for surface: Dictionary in _polygon_sets(geometry as Dictionary):
            var outer: PackedVector2Array = surface.get("outer", PackedVector2Array())
            if outer.size() < 3 or _distance_to_ring(_anchor_xz, outer) > context_radius_m + 2.0:
                continue
            _surfaces.append(surface)
            source_polygon_count += 1
            selected_in_feature = true
        if selected_in_feature:
            source_feature_count += 1

    if source_feature_count <= 0 or source_polygon_count <= 0:
        push_error("AtomiumStreetSurfaceContext: no official StreetSurfaces near Atomium")
        return false
    return true

func _load_dictionary(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    return parsed as Dictionary

func _polygon_sets(geometry: Dictionary) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    var geometry_type := str(geometry.get("type", ""))
    var coordinates: Variant = geometry.get("coordinates", [])
    if not coordinates is Array:
        return result
    var polygons: Array = []
    if geometry_type == "Polygon":
        polygons.append(coordinates)
    elif geometry_type == "MultiPolygon":
        polygons = coordinates as Array
    for raw_polygon: Variant in polygons:
        if not raw_polygon is Array or raw_polygon.is_empty():
            continue
        var outer := _ring_points(raw_polygon[0])
        if outer.size() < 3:
            continue
        var holes: Array[PackedVector2Array] = []
        for hole_index: int in range(1, raw_polygon.size()):
            var hole := _ring_points(raw_polygon[hole_index])
            if hole.size() >= 3:
                holes.append(hole)
        result.append({"outer": outer, "holes": holes})
    return result

func _ring_points(raw_ring: Variant) -> PackedVector2Array:
    var points := PackedVector2Array()
    if not raw_ring is Array:
        return points
    for raw_point: Variant in raw_ring as Array:
        if raw_point is Array and raw_point.size() >= 2:
            points.append(Vector2(float(raw_point[0]), float(raw_point[1])))
    if points.size() >= 2 and points[0].distance_to(points[points.size() - 1]) < 0.001:
        points.resize(points.size() - 1)
    return points

func _point_in_surface(point: Vector2, surface: Dictionary) -> bool:
    var outer: PackedVector2Array = surface.get("outer", PackedVector2Array())
    if outer.size() < 3 or not Geometry2D.is_point_in_polygon(point, outer):
        return false
    var holes: Array = surface.get("holes", []) as Array
    for raw_hole: Variant in holes:
        if raw_hole is PackedVector2Array and Geometry2D.is_point_in_polygon(point, raw_hole as PackedVector2Array):
            return false
    return true

func _distance_to_ring(point: Vector2, ring: PackedVector2Array) -> float:
    if ring.size() < 3:
        return INF
    if Geometry2D.is_point_in_polygon(point, ring):
        return 0.0
    var nearest := INF
    for index: int in range(ring.size()):
        nearest = minf(nearest, _distance_to_segment(point, ring[index], ring[(index + 1) % ring.size()]))
    return nearest

func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
    var ab := b - a
    var length_squared := ab.length_squared()
    if length_squared <= 0.000001:
        return point.distance_to(a)
    var t := clampf((point - a).dot(ab) / length_squared, 0.0, 1.0)
    return point.distance_to(a + ab * t)
