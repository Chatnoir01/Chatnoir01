extends Node3D

## Source-bounded current-site basin footprint from the official 2024 UrbIS
## orthophoto witness. This is deliberately a terrain-following presentation
## overlay: it does NOT claim water elevation, rim height, jets, plumbing,
## material photometry or identity/equivalence with the 2006 reference fountain.

@export_file("*.json") var data_path: String = "res://data/environment/laeken_jette/atomium_current_basin_footprint.game.json"

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
    if terrain == null or not bool(terrain.get("terrain_loaded")):
        return false
    if not _load_contract():
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
    # Deliberately authored presentation cue only. This colour is not a measured
    # water/stone material and cannot be used as photometric source evidence.
    material.albedo_color = Color(0.22, 0.39, 0.46, 0.88)
    material.roughness = 0.48
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    mesh.surface_set_material(0, material)

    var instance := MeshInstance3D.new()
    instance.name = "OfficialCurrentAtomiumBasinFootprint"
    instance.mesh = mesh
    add_child(instance)
    footprint_built = true
    print("ATOMIUM_CURRENT_BASIN_FOOTPRINT_READY: center=(%.3f,%.3f) radius=%.3f uncertainty=%.3f triangles=%d historical_axis_offset=%.3f" % [center_epsg.x, center_epsg.y, radius_m, radius_uncertainty_m, triangle_count, historical_axis_offset_m])
    return true

func _append_if_inside(vertices: PackedVector3Array, ids: Array, width: int, first_e: float, first_n: float, step_e: float, step_n: float, origin_e: float, origin_n: float, heights: PackedFloat32Array) -> void:
    var source_points: Array[Vector2] = []
    for raw_id: Variant in ids:
        var idx := int(raw_id)
        var row: int = idx / width
        var col: int = idx % width
        source_points.append(Vector2(first_e + float(col) * step_e, first_n + float(row) * step_n))
    var centroid := (source_points[0] + source_points[1] + source_points[2]) / 3.0
    if centroid.distance_to(center_epsg) > radius_m:
        return
    for k: int in range(3):
        var idx := int(ids[k])
        var source := source_points[k]
        vertices.append(Vector3(source.x - origin_e, heights[idx] + _surface_offset_m, -(source.y - origin_n)))

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
    if historical_axis_offset_m < 80.0:
        return false
    return true
