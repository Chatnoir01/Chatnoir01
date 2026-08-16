extends Node3D

## Source-bounded current-site basin footprint from the official 2024 UrbIS
## orthophoto witness. This is deliberately a terrain-following presentation
## overlay: it does NOT claim water elevation, rim height, jets, plumbing,
## material photometry or identity/equivalence with the 2006 reference fountain.

@export_file("*.json") var data_path: String = "res://data/environment/laeken_jette/atomium_current_basin_footprint.game.json"

const RADIAL_SEGMENTS := 64
const RADIAL_RINGS := 6

var footprint_built := false
var source_crs := ""
var center_epsg := Vector2.ZERO
var radius_m := 0.0
var radius_uncertainty_m := 0.0
var triangle_count := 0
var historical_axis_offset_m := 0.0
var presentation_only_surface := false
var water_level_resolved := true
var jet_geometry_resolved := true
var historical_photo_match_alignment_resolved := true
var _surface_offset_m := 0.035

func build_on_terrain(terrain: Node) -> bool:
    if terrain == null or not bool(terrain.get("terrain_loaded")) or not terrain.has_method("sample_height"):
        return false
    if not _load_contract():
        return false

    var origin_e: float = float(terrain.get("origin_e"))
    var origin_n: float = float(terrain.get("origin_n"))
    var center_game := Vector2(center_epsg.x - origin_e, -(center_epsg.y - origin_n))
    var vertices := PackedVector3Array()
    var center_vertex := _terrain_vertex(terrain, center_game)
    var previous_ring: Array[Vector3] = []
    for ring_index: int in range(1, RADIAL_RINGS + 1):
        var ring_radius := radius_m * float(ring_index) / float(RADIAL_RINGS)
        var current_ring: Array[Vector3] = []
        for segment: int in range(RADIAL_SEGMENTS):
            var angle := TAU * float(segment) / float(RADIAL_SEGMENTS)
            var point := center_game + Vector2(cos(angle), sin(angle)) * ring_radius
            current_ring.append(_terrain_vertex(terrain, point))
        if ring_index == 1:
            for segment: int in range(RADIAL_SEGMENTS):
                var next := (segment + 1) % RADIAL_SEGMENTS
                vertices.append(center_vertex)
                vertices.append(current_ring[segment])
                vertices.append(current_ring[next])
        else:
            for segment: int in range(RADIAL_SEGMENTS):
                var next := (segment + 1) % RADIAL_SEGMENTS
                vertices.append(previous_ring[segment])
                vertices.append(current_ring[segment])
                vertices.append(current_ring[next])
                vertices.append(previous_ring[segment])
                vertices.append(current_ring[next])
                vertices.append(previous_ring[next])
        previous_ring = current_ring

    triangle_count = vertices.size() / 3
    if triangle_count != RADIAL_SEGMENTS * (1 + 2 * (RADIAL_RINGS - 1)):
        return false
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.22, 0.39, 0.46, 0.78)
    material.roughness = 0.52
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    mesh.surface_set_material(0, material)
    var instance := MeshInstance3D.new()
    instance.name = "OfficialCurrentAtomiumBasinFootprint"
    instance.mesh = mesh
    add_child(instance)
    footprint_built = true
    print("ATOMIUM_CURRENT_BASIN_FOOTPRINT_READY: center=(%.3f,%.3f) radius=%.3f uncertainty=%.3f triangles=%d radial_segments=%d rings=%d historical_axis_offset=%.3f" % [center_epsg.x, center_epsg.y, radius_m, radius_uncertainty_m, triangle_count, RADIAL_SEGMENTS, RADIAL_RINGS, historical_axis_offset_m])
    return true

func _terrain_vertex(terrain: Node, point: Vector2) -> Vector3:
    return Vector3(point.x, float(terrain.call("sample_height", point.x, point.y)) + _surface_offset_m, point.y)

func _load_contract() -> bool:
    if not FileAccess.file_exists(data_path):
        return false
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        return false
    var data := parsed as Dictionary
    if int(data.get("schema", 0)) != 1 or str(data.get("format", "")) != "grand-bruxelles-atomium-current-basin-footprint-v1":
        return false
    var source := data.get("source", {}) as Dictionary
    var geometry := data.get("geometry", {}) as Dictionary
    var policy := data.get("runtime_policy", {}) as Dictionary
    var blocker := data.get("historical_alignment_blocker", {}) as Dictionary
    source_crs = str(source.get("crs", ""))
    if source_crs != "EPSG:31370" or int(source.get("capture_year", 0)) != 2024:
        return false
    var center_raw: Variant = geometry.get("center_epsg31370", [])
    if not center_raw is Array or center_raw.size() != 2:
        return false
    center_epsg = Vector2(float(center_raw[0]), float(center_raw[1]))
    radius_m = float(geometry.get("radius_m", 0.0))
    radius_uncertainty_m = float(geometry.get("radius_uncertainty_m", 0.0))
    if radius_m < 20.0 or radius_m > 35.0 or radius_uncertainty_m <= 0.0:
        return false
    presentation_only_surface = bool(policy.get("presentation_only_surface", false))
    water_level_resolved = bool(policy.get("water_level_resolved", true))
    jet_geometry_resolved = bool(policy.get("jet_geometry_resolved", true))
    historical_photo_match_alignment_resolved = bool(policy.get("historical_photo_match_alignment_resolved", true))
    _surface_offset_m = float(policy.get("surface_offset_m", 0.035))
    historical_axis_offset_m = float(blocker.get("basin_center_lateral_offset_from_camera_target_axis_m", 0.0))
    if not presentation_only_surface or water_level_resolved or jet_geometry_resolved or historical_photo_match_alignment_resolved:
        return false
    return historical_axis_offset_m >= 80.0
