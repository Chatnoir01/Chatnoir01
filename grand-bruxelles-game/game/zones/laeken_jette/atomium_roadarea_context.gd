extends Node3D

## Terrain-following presentation overlay for exact Paradigm INSPIRE
## TN.RoadTransportNetwork.RoadArea polygons that intersect the accepted
## Atomium direct-player witness. Geometry is source-bounded in EPSG:31370.
## Colour/roughness are authored presentation values only; no asphalt type,
## photometry, curb, markings, height, collision or traffic semantics are inferred.

@export_file("*.json") var data_path: String = "res://data/environment/laeken_jette/atomium_roadarea_context.game.json"
@export var surface_offset_m: float = 0.050

var context_built := false
var source_crs := ""
var source_layer := ""
var source_response_sha256 := ""
var source_feature_count := 0
var selected_feature_count := 0
var source_coverage_fraction := 0.0
var triangle_count := 0
var material_photometry_resolved := false
var collision_resolved := false
var geometry_exact_from_wfs := false

var _polygons: Array = []

func build_on_terrain(terrain: Node) -> bool:
    if terrain == null or not bool(terrain.get("terrain_loaded")) or not terrain.has_method("sample_height"):
        return false
    if not _load_source_contract():
        return false
    var origin_e: float = float(terrain.get("origin_e"))
    var origin_n: float = float(terrain.get("origin_n"))
    var vertices := PackedVector3Array()

    for polygon_raw: Variant in _polygons:
        if not polygon_raw is Array:
            return false
        var polygon := polygon_raw as Array
        # The five selected source polygons have no interior rings. If that ever
        # changes upstream, fail rather than silently filling a source hole.
        if polygon.size() != 1 or not polygon[0] is Array:
            push_error("AtomiumRoadAreaContext: polygon holes/multipart ring layout changed upstream")
            return false
        var ring := polygon[0] as Array
        if ring.size() < 4:
            return false
        var local_points := PackedVector2Array()
        var source_points: Array[Vector2] = []
        var end_index := ring.size()
        var first_raw: Variant = ring[0]
        var last_raw: Variant = ring[ring.size() - 1]
        if first_raw is Array and last_raw is Array and first_raw.size() >= 2 and last_raw.size() >= 2:
            var first_source := Vector2(float(first_raw[0]), float(first_raw[1]))
            var last_source := Vector2(float(last_raw[0]), float(last_raw[1]))
            if first_source.distance_squared_to(last_source) < 0.000001:
                end_index -= 1
        for i: int in range(end_index):
            var raw: Variant = ring[i]
            if not raw is Array or raw.size() < 2:
                return false
            var source := Vector2(float(raw[0]), float(raw[1]))
            source_points.append(source)
            local_points.append(Vector2(source.x - origin_e, -(source.y - origin_n)))
        if local_points.size() < 3:
            return false
        var indices := Geometry2D.triangulate_polygon(local_points)
        if indices.size() < 3 or indices.size() % 3 != 0:
            push_error("AtomiumRoadAreaContext: source ring triangulation failed")
            return false
        for raw_index: int in indices:
            var idx := int(raw_index)
            var local := local_points[idx]
            var y := float(terrain.call("sample_height", local.x, local.y)) + surface_offset_m
            vertices.append(Vector3(local.x, y, local.y))

    triangle_count = vertices.size() / 3
    if triangle_count <= 0:
        return false

    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.29, 0.30, 0.30, 1.0)
    material.roughness = 0.92
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    mesh.surface_set_material(0, material)
    var instance := MeshInstance3D.new()
    instance.name = "OfficialAtomiumRoadArea"
    instance.mesh = mesh
    add_child(instance)
    context_built = true
    print("ATOMIUM_ROADAREA_CONTEXT_READY: selected=%d triangles=%d coverage=%.4f" % [selected_feature_count, triangle_count, source_coverage_fraction])
    return true

func _load_source_contract() -> bool:
    if not FileAccess.file_exists(data_path):
        return false
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        return false
    var data := parsed as Dictionary
    if int(data.get("schema", 0)) != 1 or str(data.get("format", "")) != "grand-bruxelles-atomium-roadarea-context-v1":
        return false
    var source := data.get("source", {}) as Dictionary
    var witness := data.get("accepted_player_witness", {}) as Dictionary
    var selection := data.get("selection", {}) as Dictionary
    var policy := data.get("runtime_policy", {}) as Dictionary
    source_crs = str(source.get("crs", ""))
    source_layer = str(source.get("layer", ""))
    source_response_sha256 = str(source.get("response_sha256", ""))
    source_feature_count = int(selection.get("source_feature_count", 0))
    source_coverage_fraction = float(witness.get("ground_wedge_coverage_fraction", 0.0))
    material_photometry_resolved = bool(policy.get("material_photometry_resolved", true))
    collision_resolved = bool(policy.get("collision_resolved", true))
    geometry_exact_from_wfs = bool(policy.get("geometry_exact_from_wfs", false))
    if source_crs != "EPSG:31370" or source_layer != "TN.RoadTransportNetwork.RoadArea":
        return false
    if source_response_sha256.length() != 64 or source_feature_count != 24 or source_coverage_fraction < 0.20:
        return false
    if material_photometry_resolved or collision_resolved or not geometry_exact_from_wfs:
        return false
    var features_raw: Variant = data.get("features", [])
    if not features_raw is Array:
        return false
    var features := features_raw as Array
    selected_feature_count = features.size()
    if selected_feature_count != 5:
        return false
    _polygons.clear()
    for feature_raw: Variant in features:
        if not feature_raw is Dictionary:
            return false
        var geometry := (feature_raw as Dictionary).get("geometry", {}) as Dictionary
        if str(geometry.get("type", "")) != "MultiPolygon":
            return false
        var coordinates: Variant = geometry.get("coordinates", [])
        if not coordinates is Array:
            return false
        for polygon_raw: Variant in coordinates as Array:
            _polygons.append(polygon_raw)
    return not _polygons.is_empty()
