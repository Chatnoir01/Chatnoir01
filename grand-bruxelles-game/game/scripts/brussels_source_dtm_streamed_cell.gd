extends Node3D
class_name BrusselsSourceDtmStreamedCell

## Source-safe streamed runtime for a Brussels cell with authoritative UrbIS plan
## geometry and a provenance-locked 2 m DTM candidate sharing the Ixelles datum.
## Building footprints remain blocked until a separate runtime massing gate.

@export_file("*.json") var manifest_path := ""
@export_file("*.json") var runtime_cell_path := ""
@export_file("*.json") var runtime_network_path := ""
@export_file("*.json") var terrain_path := ""
@export_file("*.json") var shared_datum_path := ""
@export var build_collision := false
@export var terrain_vertex_rows_per_frame := 24
@export var terrain_index_rows_per_frame := 40
@export var street_surface_features_per_frame := 48
@export var surface_clearance_m := 0.035

const EXPECTED_TERRAIN_SCHEMA := "grand-bruxelles-ixelles-dtm-2m-runtime-candidate-v1"
const EXPECTED_DATUM_SCHEMA := "grand-bruxelles-ixelles-shared-vertical-datum-v1"
const EXPECTED_REFERENCE_M := 62.393423

var runtime_loaded := false
var cell_id := ""
var terrain_sample_count := 0
var terrain_triangle_count := 0
var street_surface_count := 0
var street_segment_count := 0
var source_building_count := 0
var blocked_unapproved_building_count := 0
var rendered_building_count := 0
var vertical_reference_absolute_m := 0.0
var first_relative_height_m := 0.0
var street_surface_chunks := 0
var terrain_vertex_chunks := 0
var terrain_index_chunks := 0
var terrain_sample_failures := 0
var street_surface_min_vertex_clearance_m := INF
var street_surface_max_vertex_clearance_m := -INF
var stream_total_ms := 0
var stream_phase_ms: Dictionary = {}
var streamed_collision_requested := false
var streamed_collision_enabled := false
var streamed_collision_enable_count := 0
var streamed_collision_disable_count := 0

var _manifest: Dictionary = {}
var _cell: Dictionary = {}
var _network: Dictionary = {}
var _terrain: Dictionary = {}
var _datum: Dictionary = {}
var _width := 0
var _height := 0
var _spacing := 0.0
var _bbox := Rect2()
var _heights_relative := PackedFloat32Array()
var _origin_e := 0.0
var _origin_n := 0.0
var _world_anchor_x := 0.0
var _world_anchor_z := 0.0
var _terrain_material: StandardMaterial3D
var _road_material: StandardMaterial3D
var _sidewalk_material: StandardMaterial3D
var _paved_material: StandardMaterial3D
var _other_material: StandardMaterial3D


func _ready() -> void:
    call_deferred("_build_streamed")


func _read_json(path: String) -> Dictionary:
    if path.is_empty() or not FileAccess.file_exists(path):
        push_error("BrusselsSourceDtmStreamedCell: missing runtime contract %s" % path)
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("BrusselsSourceDtmStreamedCell: invalid JSON %s" % path)
        return {}
    return parsed as Dictionary


func _load_contracts() -> bool:
    _manifest = _read_json(manifest_path)
    _cell = _read_json(runtime_cell_path)
    _network = _read_json(runtime_network_path)
    _terrain = _read_json(terrain_path)
    _datum = _read_json(shared_datum_path)
    if _manifest.is_empty() or _cell.is_empty() or _network.is_empty() or _terrain.is_empty() or _datum.is_empty():
        return false

    cell_id = str(_manifest.get("cell_id", ""))
    if cell_id.is_empty() or str(_cell.get("cell_id", "")) != cell_id or str(_network.get("cell_id", "")) != cell_id or str(_terrain.get("cell_id", "")) != cell_id:
        push_error("BrusselsSourceDtmStreamedCell: cell contract mismatch")
        return false
    if str(_manifest.get("crs", "")) != "EPSG:31370" or str(_terrain.get("schema", "")) != EXPECTED_TERRAIN_SCHEMA:
        push_error("BrusselsSourceDtmStreamedCell: unexpected terrain source contract")
        return false
    if bool(_terrain.get("runtime_approved", true)) or bool(_terrain.get("promote_runtime", true)):
        push_error("BrusselsSourceDtmStreamedCell: candidate terrain incorrectly marked approved")
        return false
    if str(_datum.get("schema", "")) != EXPECTED_DATUM_SCHEMA or str(_datum.get("crs", "")) != "EPSG:31370":
        push_error("BrusselsSourceDtmStreamedCell: shared datum contract mismatch")
        return false
    vertical_reference_absolute_m = float(_datum.get("reference_absolute_m", NAN))
    if not is_finite(vertical_reference_absolute_m) or absf(vertical_reference_absolute_m - EXPECTED_REFERENCE_M) > 0.000001:
        push_error("BrusselsSourceDtmStreamedCell: shared vertical reference drifted")
        return false
    var terrain_datum: Variant = _terrain.get("shared_vertical_datum", {})
    if not terrain_datum is Dictionary or absf(float(terrain_datum.get("reference_absolute_m", NAN)) - vertical_reference_absolute_m) > 0.000001:
        push_error("BrusselsSourceDtmStreamedCell: terrain does not use shared vertical datum")
        return false

    var bbox_raw: Variant = _terrain.get("bbox_epsg31370", [])
    var manifest_bbox: Variant = _manifest.get("bbox", [])
    if not bbox_raw is Array or bbox_raw.size() != 4 or not manifest_bbox is Array or manifest_bbox.size() != 4:
        return false
    for index: int in range(4):
        if absf(float(bbox_raw[index]) - float(manifest_bbox[index])) > 0.001:
            push_error("BrusselsSourceDtmStreamedCell: terrain/manifest bbox mismatch")
            return false
    _bbox = Rect2(float(bbox_raw[0]), float(bbox_raw[1]), float(bbox_raw[2]) - float(bbox_raw[0]), float(bbox_raw[3]) - float(bbox_raw[1]))
    _spacing = float(_terrain.get("spacing_m", 0.0))
    var shape: Variant = _terrain.get("shape", [])
    if not shape is Array or shape.size() != 2:
        return false
    _height = int(shape[0])
    _width = int(shape[1])
    terrain_sample_count = int(_terrain.get("sample_count", 0))
    if _width != 251 or _height != 251 or terrain_sample_count != 63001 or absf(_spacing - 2.0) > 0.0001:
        push_error("BrusselsSourceDtmStreamedCell: 2 m terrain topology drifted")
        return false

    var raw_heights: Variant = _terrain.get("heights_row_major_m", [])
    if not raw_heights is Array or raw_heights.size() != terrain_sample_count:
        return false
    _heights_relative.resize(terrain_sample_count)
    for index: int in range(terrain_sample_count):
        var absolute_height := float(raw_heights[index])
        if not is_finite(absolute_height):
            push_error("BrusselsSourceDtmStreamedCell: non-finite official DTM sample")
            return false
        _heights_relative[index] = absolute_height - vertical_reference_absolute_m
    first_relative_height_m = _heights_relative[0]

    var coords: Variant = _cell.get("coordinate_system", {})
    if not coords is Dictionary or not bool(coords.get("coordinates_are_current_game_world", false)):
        push_error("BrusselsSourceDtmStreamedCell: current-game-world coordinate contract missing")
        return false
    _origin_e = float(coords.get("lambert_origin_e", 0.0))
    _origin_n = float(coords.get("lambert_origin_n", 0.0))
    _world_anchor_x = float(coords.get("world_anchor_x", 0.0))
    _world_anchor_z = float(coords.get("world_anchor_z", 0.0))

    var runtime_manifest: Variant = _manifest.get("runtime", {})
    if not runtime_manifest is Dictionary:
        return false
    if str(runtime_manifest.get("geometry_format", "")) != "grand-bruxelles-urbis-cell-runtime-v1" or str(runtime_manifest.get("network_format", "")) != "grand-bruxelles-urbis-network-cell-runtime-v2":
        push_error("BrusselsSourceDtmStreamedCell: runtime plan format drifted")
        return false
    return true


func _make_material(color: Color, roughness: float) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    return material


func _make_materials() -> void:
    _terrain_material = _make_material(Color(0.17, 0.25, 0.13, 1.0), 0.98)
    _road_material = _make_material(Color(0.075, 0.078, 0.082, 1.0), 0.97)
    _sidewalk_material = _make_material(Color(0.45, 0.435, 0.405, 1.0), 0.94)
    _paved_material = _make_material(Color(0.39, 0.375, 0.345, 1.0), 0.95)
    _other_material = _make_material(Color(0.28, 0.285, 0.28, 1.0), 0.95)


func _surface_material(surface_type: String) -> StandardMaterial3D:
    if surface_type == "S":
        return _road_material
    if surface_type == "SW":
        return _sidewalk_material
    if surface_type == "P" or surface_type == "I":
        return _paved_material
    return _other_material


func _ring(raw: Variant) -> PackedVector2Array:
    var ring := PackedVector2Array()
    if not raw is Array:
        return ring
    for item: Variant in raw:
        if item is Array and item.size() >= 2:
            ring.append(Vector2(float(item[0]), float(item[1])))
    if ring.size() >= 2 and ring[0].is_equal_approx(ring[ring.size() - 1]):
        ring.remove_at(ring.size() - 1)
    return ring


func _expected_geometry_count(key: String) -> int:
    var runtime_manifest: Variant = _manifest.get("runtime", {})
    if not runtime_manifest is Dictionary:
        return -1
    var stats: Variant = runtime_manifest.get("geometry_stats", {})
    if not stats is Dictionary:
        return -1
    return int(stats.get(key, -1))


func _index(row: int, col: int) -> int:
    return row * _width + col


func lambert_to_game(e: float, n: float) -> Vector3:
    return Vector3(_world_anchor_x + (e - _origin_e), 0.0, _world_anchor_z - (n - _origin_n))


func _grid_game_position(row: int, col: int) -> Vector3:
    var e := _bbox.position.x + float(col) * _spacing
    var n := _bbox.position.y + float(row) * _spacing
    var position := lambert_to_game(e, n)
    position.y = _heights_relative[_index(row, col)]
    return position


func _normal(row: int, col: int) -> Vector3:
    var left := _heights_relative[_index(row, maxi(col - 1, 0))]
    var right := _heights_relative[_index(row, mini(col + 1, _width - 1))]
    var south := _heights_relative[_index(maxi(row - 1, 0), col)]
    var north := _heights_relative[_index(mini(row + 1, _height - 1), col)]
    var dhdx := (right - left) / (2.0 * _spacing)
    var dhdz := -(north - south) / (2.0 * _spacing)
    return Vector3(-dhdx, 1.0, -dhdz).normalized()


func sample_height(game_x: float, game_z: float) -> float:
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
    return lerpf(lerpf(_heights_relative[_index(r0, c0)], _heights_relative[_index(r0, c1)], tx), lerpf(_heights_relative[_index(r1, c0)], _heights_relative[_index(r1, c1)], tx), ty)


func _record_phase_peak(phase_name: String, elapsed_ms: int) -> void:
    stream_phase_ms[phase_name] = maxi(int(stream_phase_ms.get(phase_name, 0)), elapsed_ms)


func _build_streamed() -> void:
    var total_started := Time.get_ticks_msec()
    var phase_started := Time.get_ticks_msec()
    if not _load_contracts():
        return
    _make_materials()
    stream_phase_ms["contracts_materials"] = Time.get_ticks_msec() - phase_started
    await get_tree().process_frame

    var buildings: Variant = _cell.get("buildings", [])
    if buildings is Array:
        source_building_count = buildings.size()
        blocked_unapproved_building_count = source_building_count
        rendered_building_count = 0
    var expected_buildings := _expected_geometry_count("buildings")
    if expected_buildings < 0 or source_building_count != expected_buildings:
        push_error("BrusselsSourceDtmStreamedCell: building runtime count drifted for %s" % cell_id)
        return

    await _build_terrain_over_frames()
    await get_tree().process_frame
    await _build_street_surfaces_over_frames()

    var stats: Variant = _network.get("stats", {})
    if stats is Dictionary:
        street_segment_count = int(stats.get("street_segments", 0))
    var expected_surfaces := _expected_geometry_count("street_surfaces")
    runtime_loaded = terrain_triangle_count == 125000 and expected_surfaces >= 0 and street_surface_count == expected_surfaces and blocked_unapproved_building_count == expected_buildings and rendered_building_count == 0 and terrain_sample_failures == 0 and is_finite(street_surface_min_vertex_clearance_m) and street_surface_min_vertex_clearance_m >= surface_clearance_m - 0.0005
    stream_total_ms = Time.get_ticks_msec() - total_started
    if runtime_loaded:
        _apply_streamed_collision_request()
        print("BRUSSELS_SOURCE_DTM_CELL_READY: cell=%s triangles=%d surfaces=%d street_segments=%d blocked_buildings=%d first_relative=%.3f total_ms=%d max_phase_ms=%d" % [cell_id, terrain_triangle_count, street_surface_count, street_segment_count, blocked_unapproved_building_count, first_relative_height_m, stream_total_ms, get_max_stream_phase_ms()])
    else:
        push_error("BrusselsSourceDtmStreamedCell: runtime gate failed for %s terrain=%d surfaces=%d/%d buildings=%d/%d sample_failures=%d min_clearance=%.6f" % [cell_id, terrain_triangle_count, street_surface_count, expected_surfaces, blocked_unapproved_building_count, expected_buildings, terrain_sample_failures, street_surface_min_vertex_clearance_m])


func _build_terrain_over_frames() -> void:
    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    vertices.resize(terrain_sample_count)
    normals.resize(terrain_sample_count)
    var row_start := 0
    var vertex_chunk_rows := maxi(terrain_vertex_rows_per_frame, 1)
    while row_start < _height:
        var started := Time.get_ticks_msec()
        var row_end := mini(row_start + vertex_chunk_rows, _height)
        for row: int in range(row_start, row_end):
            for col: int in range(_width):
                var index := _index(row, col)
                vertices[index] = _grid_game_position(row, col)
                normals[index] = _normal(row, col)
        terrain_vertex_chunks += 1
        _record_phase_peak("terrain_vertices_chunk", Time.get_ticks_msec() - started)
        row_start = row_end
        if row_start < _height:
            await get_tree().process_frame

    var indices := PackedInt32Array()
    indices.resize((_width - 1) * (_height - 1) * 6)
    var index_chunk_rows := maxi(terrain_index_rows_per_frame, 1)
    row_start = 0
    while row_start < _height - 1:
        var started := Time.get_ticks_msec()
        var row_end := mini(row_start + index_chunk_rows, _height - 1)
        for row: int in range(row_start, row_end):
            var cursor := row * (_width - 1) * 6
            for col: int in range(_width - 1):
                var i0 := _index(row, col)
                var i1 := _index(row + 1, col)
                var i2 := _index(row, col + 1)
                var i3 := _index(row + 1, col + 1)
                indices[cursor] = i0
                indices[cursor + 1] = i1
                indices[cursor + 2] = i2
                indices[cursor + 3] = i2
                indices[cursor + 4] = i1
                indices[cursor + 5] = i3
                cursor += 6
        terrain_index_chunks += 1
        _record_phase_peak("terrain_indices_chunk", Time.get_ticks_msec() - started)
        row_start = row_end
        if row_start < _height - 1:
            await get_tree().process_frame

    terrain_triangle_count = indices.size() / 3
    var commit_started := Time.get_ticks_msec()
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    mesh.surface_set_material(0, _terrain_material)
    var instance := MeshInstance3D.new()
    instance.name = "OfficialBrusselsDTMMesh"
    instance.mesh = mesh
    add_child(instance)
    _record_phase_peak("terrain_mesh_commit", Time.get_ticks_msec() - commit_started)


func _build_street_surfaces_over_frames() -> void:
    var surfaces: Variant = _cell.get("street_surfaces", [])
    if not surfaces is Array:
        return
    var grouped: Dictionary = {}
    var chunk_size := maxi(street_surface_features_per_frame, 1)
    var start_index := 0
    while start_index < surfaces.size():
        var started := Time.get_ticks_msec()
        var end_index := mini(start_index + chunk_size, surfaces.size())
        for feature_index: int in range(start_index, end_index):
            var feature: Variant = surfaces[feature_index]
            if not feature is Dictionary:
                continue
            var ring := _ring(feature.get("polygon", []))
            if ring.size() < 3:
                continue
            var triangle_indices := Geometry2D.triangulate_polygon(ring)
            if triangle_indices.size() < 3:
                continue
            var key := str(feature.get("type", ""))
            if not grouped.has(key):
                var tool := SurfaceTool.new()
                tool.begin(Mesh.PRIMITIVE_TRIANGLES)
                tool.set_material(_surface_material(key))
                grouped[key] = tool
            var target: SurfaceTool = grouped[key]
            for raw_index: int in triangle_indices:
                var point := ring[raw_index]
                var terrain_y := sample_height(point.x, point.y)
                if not is_finite(terrain_y):
                    terrain_sample_failures += 1
                    continue
                var vertex_y := terrain_y + surface_clearance_m
                var clearance := vertex_y - terrain_y
                street_surface_min_vertex_clearance_m = minf(street_surface_min_vertex_clearance_m, clearance)
                street_surface_max_vertex_clearance_m = maxf(street_surface_max_vertex_clearance_m, clearance)
                target.set_normal(Vector3.UP)
                target.add_vertex(Vector3(point.x, vertex_y, point.y))
            street_surface_count += 1
        street_surface_chunks += 1
        _record_phase_peak("street_surface_chunk", Time.get_ticks_msec() - started)
        start_index = end_index
        if start_index < surfaces.size():
            await get_tree().process_frame

    var commit_started := Time.get_ticks_msec()
    var root := Node3D.new()
    root.name = "OfficialBrusselsStreetSurfaces"
    add_child(root)
    for key: Variant in grouped.keys():
        var mesh: ArrayMesh = (grouped[key] as SurfaceTool).commit()
        if mesh.get_surface_count() == 0:
            continue
        var instance := MeshInstance3D.new()
        instance.name = "StreetSurfaces_%s" % str(key)
        instance.mesh = mesh
        root.add_child(instance)
    _record_phase_peak("street_surface_commit", Time.get_ticks_msec() - commit_started)


func _heightmap_collision_data() -> PackedFloat32Array:
    var collision_heights := PackedFloat32Array()
    collision_heights.resize(_heights_relative.size())
    for target_row: int in range(_height):
        var source_row := _height - 1 - target_row
        var target_offset := target_row * _width
        var source_offset := source_row * _width
        for col: int in range(_width):
            collision_heights[target_offset + col] = _heights_relative[source_offset + col]
    return collision_heights


func _build_collision() -> void:
    if get_node_or_null("OfficialBrusselsDTMCollision") != null:
        return
    var shape := HeightMapShape3D.new()
    shape.map_width = _width
    shape.map_depth = _height
    shape.map_data = _heightmap_collision_data()
    var collision := CollisionShape3D.new()
    collision.name = "OfficialBrusselsDTMHeightMapCollision"
    collision.shape = shape
    collision.scale = Vector3(_spacing, 1.0, _spacing)
    var sw := lambert_to_game(_bbox.position.x, _bbox.position.y)
    var ne := lambert_to_game(_bbox.end.x, _bbox.end.y)
    collision.position = Vector3((sw.x + ne.x) * 0.5, 0.0, (sw.z + ne.z) * 0.5)
    var body := StaticBody3D.new()
    body.name = "OfficialBrusselsDTMCollision"
    body.add_child(collision)
    add_child(body)


func set_streamed_collision_enabled(enabled: bool) -> void:
    streamed_collision_requested = enabled
    if runtime_loaded:
        call_deferred("_apply_streamed_collision_request")


func is_streamed_collision_enabled() -> bool:
    return streamed_collision_enabled


func _apply_streamed_collision_request() -> void:
    if not runtime_loaded:
        return
    var existing := get_node_or_null("OfficialBrusselsDTMCollision") as StaticBody3D
    if streamed_collision_requested:
        if existing == null:
            var started := Time.get_ticks_msec()
            _build_collision()
            _record_phase_peak("streamed_collision_build", Time.get_ticks_msec() - started)
            streamed_collision_enable_count += 1
        streamed_collision_enabled = true
        return
    if existing != null:
        existing.queue_free()
        streamed_collision_disable_count += 1
    streamed_collision_enabled = false


func get_streamed_collision_metrics() -> Dictionary:
    return {
        "requested": streamed_collision_requested,
        "enabled": streamed_collision_enabled,
        "enable_count": streamed_collision_enable_count,
        "disable_count": streamed_collision_disable_count,
    }


func get_max_stream_phase_ms() -> int:
    var maximum := 0
    for phase_name: String in stream_phase_ms.keys():
        maximum = maxi(maximum, int(stream_phase_ms[phase_name]))
    return maximum
