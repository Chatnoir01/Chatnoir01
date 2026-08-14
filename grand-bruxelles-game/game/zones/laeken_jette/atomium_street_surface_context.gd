extends Node3D

## Source-bounded public-realm overlay for the Atomium hero tile.
## Geometry comes from the exact UrbIS StreetSurfaces extraction. The neutral
## material is presentation-only: it does not claim paving/asphalt composition.

@export_file("*.json") var data_path: String = "res://data/urbis/laeken_jette/atomium_street_surfaces.game.json"
@export var surface_offset_m: float = 0.045

const EXPECTED_SOURCE_CRS := "EPSG:31370"
const EXPECTED_SOURCE_LAYER := "urbisvector:StreetSurfaces"
const EXPECTED_WORKSPACE_BLOB := "773befce25bcf78357805571f7f2f8accf983e6a"

var context_loaded: bool = false
var source_feature_count: int = 0
var rendered_feature_count: int = 0
var triangle_count: int = 0
var skipped_outside_dtm_triangles: int = 0
var presentation_material_only: bool = true
var collision_authored: bool = false


func build_on_terrain(terrain: Node) -> bool:
    if terrain == null or not bool(terrain.get("terrain_loaded")):
        push_error("AtomiumStreetSurfaceContext: validated DTM unavailable")
        return false
    if not FileAccess.file_exists(data_path):
        push_error("AtomiumStreetSurfaceContext: extracted UrbIS data unavailable")
        return false
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("AtomiumStreetSurfaceContext: invalid JSON")
        return false
    var data: Dictionary = parsed as Dictionary
    if int(data.get("schema", 0)) != 1:
        push_error("AtomiumStreetSurfaceContext: unsupported schema")
        return false
    if str(data.get("source_crs", "")) != EXPECTED_SOURCE_CRS or str(data.get("source_layer", "")) != EXPECTED_SOURCE_LAYER:
        push_error("AtomiumStreetSurfaceContext: source contract drifted")
        return false
    if str(data.get("workspace_source_blob_sha", "")) != EXPECTED_WORKSPACE_BLOB:
        push_error("AtomiumStreetSurfaceContext: workspace source blob drifted")
        return false
    var raw_features: Variant = data.get("features", [])
    if not raw_features is Array:
        return false
    source_feature_count = raw_features.size()
    if source_feature_count != int(data.get("feature_count", -1)) or source_feature_count <= 0:
        push_error("AtomiumStreetSurfaceContext: feature-count contract drifted")
        return false

    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    for raw_feature: Variant in raw_features:
        if not raw_feature is Dictionary:
            continue
        var feature: Dictionary = raw_feature as Dictionary
        var properties: Variant = feature.get("properties", {})
        if properties is Dictionary and int((properties as Dictionary).get("LVL", 0)) != 0:
            continue
        var geometry: Variant = feature.get("geometry", {})
        if not geometry is Dictionary:
            continue
        var rings: Array[PackedVector2Array] = _polygon_rings(geometry as Dictionary)
        var feature_rendered := false
        for polygon: PackedVector2Array in rings:
            if polygon.size() < 3:
                continue
            var triangulated: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
            for i: int in range(0, triangulated.size(), 3):
                if i + 2 >= triangulated.size():
                    break
                var p0: Vector2 = polygon[triangulated[i]]
                var p1: Vector2 = polygon[triangulated[i + 1]]
                var p2: Vector2 = polygon[triangulated[i + 2]]
                if not _triangle_inside_terrain(terrain, p0, p1, p2):
                    skipped_outside_dtm_triangles += 1
                    continue
                var v0 := Vector3(p0.x, float(terrain.call("sample_height", p0.x, p0.y)) + surface_offset_m, p0.y)
                var v1 := Vector3(p1.x, float(terrain.call("sample_height", p1.x, p1.y)) + surface_offset_m, p1.y)
                var v2 := Vector3(p2.x, float(terrain.call("sample_height", p2.x, p2.y)) + surface_offset_m, p2.y)
                var normal := (v1 - v0).cross(v2 - v0).normalized()
                if normal.y < 0.0:
                    var swap := v1
                    v1 = v2
                    v2 = swap
                    normal = -normal
                vertices.append_array(PackedVector3Array([v0, v1, v2]))
                normals.append_array(PackedVector3Array([normal, normal, normal]))
                triangle_count += 1
                feature_rendered = true
        if feature_rendered:
            rendered_feature_count += 1

    if triangle_count <= 0 or rendered_feature_count <= 0:
        push_error("AtomiumStreetSurfaceContext: no source geometry survived DTM clipping")
        return false

    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.24, 0.25, 0.24, 1.0)
    material.roughness = 0.97
    material.metallic = 0.0
    mesh.surface_set_material(0, material)
    var instance := MeshInstance3D.new()
    instance.name = "OfficialAtomiumStreetSurfaceContext"
    instance.mesh = mesh
    add_child(instance)

    context_loaded = true
    print("ATOMIUM_STREETSURFACE_CONTEXT_READY: source=%d rendered=%d triangles=%d clipped=%d" % [source_feature_count, rendered_feature_count, triangle_count, skipped_outside_dtm_triangles])
    return true


func _polygon_rings(geometry: Dictionary) -> Array[PackedVector2Array]:
    var result: Array[PackedVector2Array] = []
    var geometry_type := str(geometry.get("type", ""))
    var coordinates: Variant = geometry.get("coordinates", [])
    if not coordinates is Array:
        return result
    if geometry_type == "Polygon":
        if coordinates.size() > 0:
            var ring := _ring_from_variant(coordinates[0])
            if ring.size() >= 3:
                result.append(ring)
    elif geometry_type == "MultiPolygon":
        for raw_polygon: Variant in coordinates:
            if raw_polygon is Array and raw_polygon.size() > 0:
                var ring := _ring_from_variant(raw_polygon[0])
                if ring.size() >= 3:
                    result.append(ring)
    return result


func _ring_from_variant(raw_ring: Variant) -> PackedVector2Array:
    var ring := PackedVector2Array()
    if not raw_ring is Array:
        return ring
    for raw_point: Variant in raw_ring:
        if raw_point is Array and raw_point.size() >= 2:
            ring.append(Vector2(float(raw_point[0]), float(raw_point[1])))
    if ring.size() >= 2 and ring[0].distance_to(ring[ring.size() - 1]) < 0.001:
        ring.remove_at(ring.size() - 1)
    return ring


func _triangle_inside_terrain(terrain: Node, a: Vector2, b: Vector2, c: Vector2) -> bool:
    return bool(terrain.call("contains_game_point", a.x, a.y)) and bool(terrain.call("contains_game_point", b.x, b.y)) and bool(terrain.call("contains_game_point", c.x, c.y))
