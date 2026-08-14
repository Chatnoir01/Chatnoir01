extends Node3D

## Source-bounded presentation overlay for official Paradigm INSPIRE LandCover
## feature LandCover.1038 (GB / Green Block). Geometry follows the already
## accepted Atomium DTM. Colour/roughness are authored presentation values;
## no grass, tree, paving, photometry, height or collision is inferred.

@export_file("*.json") var data_path: String = "res://data/environment/laeken_jette/atomium_landcover_context.game.json"
@export var surface_offset_m: float = 0.025

var context_built := false
var source_feature_id := ""
var source_code := ""
var source_area_m2 := 0.0
var triangle_count := 0
var source_crs := ""
var material_photometry_resolved := false
var vegetation_geometry_resolved := false

var _polygons: Array = []

func build_on_terrain(terrain: Node) -> bool:
    if terrain == null or not bool(terrain.get("terrain_loaded")):
        return false
    if not _load_source_contract():
        return false
    var width: int = int(terrain.get("width"))
    var height: int = int(terrain.get("height"))
    var first_e: float = float(terrain.get("first_e"))
    var first_n: float = float(terrain.get("first_n"))
    var step_e: float = float(terrain.get("step_e"))
    var step_n: float = float(terrain.get("step_n"))
    var origin_e: float = float(terrain.get("origin_e"))
    var origin_n: float = float(terrain.get("origin_n"))
    var heights: PackedFloat32Array = terrain.get("heights")
    var valid_mask: PackedByteArray = terrain.get("valid_mask")
    if width < 2 or height < 2 or heights.size() != width * height or valid_mask.size() != heights.size():
        return false

    var vertices := PackedVector3Array()
    for row: int in range(height - 1):
        for col: int in range(width - 1):
            var i0 := row * width + col
            var i1 := (row + 1) * width + col
            var i2 := row * width + col + 1
            var i3 := (row + 1) * width + col + 1
            if valid_mask[i0] != 0 and valid_mask[i1] != 0 and valid_mask[i2] != 0:
                _append_if_inside(vertices, [i0, i1, i2], width, first_e, first_n, step_e, step_n, origin_e, origin_n, heights)
            if valid_mask[i2] != 0 and valid_mask[i1] != 0 and valid_mask[i3] != 0:
                _append_if_inside(vertices, [i2, i1, i3], width, first_e, first_n, step_e, step_n, origin_e, origin_n, heights)
    triangle_count = vertices.size() / 3
    if triangle_count <= 0:
        return false

    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    var material := StandardMaterial3D.new()
    # Presentation-only differentiation from the generic DTM base. Not a
    # measured grass colour or photometric claim.
    material.albedo_color = Color(0.27, 0.40, 0.16, 1.0)
    material.roughness = 1.0
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    mesh.surface_set_material(0, material)
    var instance := MeshInstance3D.new()
    instance.name = "OfficialAtomiumGBLandCover"
    instance.mesh = mesh
    add_child(instance)
    context_built = true
    print("ATOMIUM_LANDCOVER_CONTEXT_READY: feature=%s code=%s triangles=%d area=%.2f" % [source_feature_id, source_code, triangle_count, source_area_m2])
    return true

func _append_if_inside(vertices: PackedVector3Array, ids: Array, width: int, first_e: float, first_n: float, step_e: float, step_n: float, origin_e: float, origin_n: float, heights: PackedFloat32Array) -> void:
    var source_points: Array[Vector2] = []
    for raw_id: Variant in ids:
        var idx: int = int(raw_id)
        var row: int = idx / width
        var col: int = idx % width
        source_points.append(Vector2(first_e + float(col) * step_e, first_n + float(row) * step_n))
    var centroid := (source_points[0] + source_points[1] + source_points[2]) / 3.0
    if not _point_in_source_geometry(centroid):
        return
    for k: int in range(3):
        var idx: int = int(ids[k])
        var source := source_points[k]
        vertices.append(Vector3(source.x - origin_e, heights[idx] + surface_offset_m, -(source.y - origin_n)))

func _load_source_contract() -> bool:
    if not FileAccess.file_exists(data_path):
        return false
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        return false
    var data := parsed as Dictionary
    if int(data.get("schema", 0)) != 1 or str(data.get("format", "")) != "grand-bruxelles-atomium-landcover-source-gate-v1":
        return false
    var source := data.get("source", {}) as Dictionary
    var classification := data.get("classification", {}) as Dictionary
    var geometry := data.get("geometry", {}) as Dictionary
    var policy := data.get("runtime_policy", {}) as Dictionary
    source_crs = str(source.get("crs", ""))
    source_feature_id = str(source.get("feature_id", ""))
    source_code = str(classification.get("source_code", ""))
    source_area_m2 = float(geometry.get("area_m2", 0.0))
    material_photometry_resolved = bool(policy.get("material_photometry_resolved", true))
    vegetation_geometry_resolved = bool(policy.get("vegetation_geometry_resolved", true))
    if source_crs != "EPSG:31370" or source_feature_id != "LandCover.1038" or source_code != "GB":
        return false
    if source_area_m2 < 50000.0 or material_photometry_resolved or vegetation_geometry_resolved:
        return false
    if str(geometry.get("type", "")) != "MultiPolygon":
        return false
    _polygons = geometry.get("coordinates", []) as Array
    return not _polygons.is_empty()

func _point_in_source_geometry(point: Vector2) -> bool:
    for polygon_raw: Variant in _polygons:
        if not polygon_raw is Array:
            continue
        var polygon := polygon_raw as Array
        if polygon.is_empty() or not polygon[0] is Array:
            continue
        if not _point_in_ring(point, polygon[0] as Array):
            continue
        var inside_hole := false
        for hole_index: int in range(1, polygon.size()):
            if polygon[hole_index] is Array and _point_in_ring(point, polygon[hole_index] as Array):
                inside_hole = true
                break
        if not inside_hole:
            return true
    return false

func _point_in_ring(point: Vector2, ring: Array) -> bool:
    if ring.size() < 3:
        return false
    var inside := false
    var j := ring.size() - 1
    for i: int in range(ring.size()):
        var a_raw: Variant = ring[i]
        var b_raw: Variant = ring[j]
        if a_raw is Array and b_raw is Array and a_raw.size() >= 2 and b_raw.size() >= 2:
            var a := Vector2(float(a_raw[0]), float(a_raw[1]))
            var b := Vector2(float(b_raw[0]), float(b_raw[1]))
            if ((a.y > point.y) != (b.y > point.y)):
                var cross_x := (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x
                if point.x < cross_x:
                    inside = not inside
        j = i
    return inside
