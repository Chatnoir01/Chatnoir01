extends "res://game/scripts/brussels_source_plan_streamed_cell.gd"
class_name IxellesStreamedNorthDtmCell

## Second bounded physical Ixelles streamed cell.
## UrbIS StreetSurfaces and visual-only building massing stay source-plan backed;
## only the provenance-locked official DTM is gameplay-authoritative collision.

const EXPECTED_CELL_ID := "bxl-e149000-n169500-s500"
const TERRAIN_PATH := "res://data/terrain/ixelles/bxl-e149000-n169500-s500_dtm_2m.game.json"
const EXPECTED_DTM_SCHEMA := "grand-bruxelles-ixelles-dtm-2m-runtime-candidate-v1"
const EXPECTED_SHARED_DATUM_SCHEMA := "grand-bruxelles-ixelles-shared-vertical-datum-v1"
const EXPECTED_REFERENCE_M := 62.393423
const EXPECTED_SAMPLE_COUNT := 63001
const EXPECTED_GRID_SIZE := 251
const EXPECTED_SPACING_M := 2.0
const EXPECTED_TRIANGLES := 125000

var terrain_sample_count := 0
var terrain_triangle_count := 0
var vertical_reference_absolute_m := 0.0
var _terrain_width := 0
var _terrain_height := 0
var _terrain_spacing := 0.0
var _terrain_bbox := Rect2()
var _terrain_heights := PackedFloat32Array()
var _origin_e := 0.0
var _origin_n := 0.0
var _world_anchor_x := 0.0
var _world_anchor_z := 0.0
var _terrain_material: StandardMaterial3D
var _stream_collision_enabled := false
var _terrain_contract_loaded := false


func _init() -> void:
    manifest_path = "res://data/urbis/remaining_brussels/cells/bxl-e149000-n169500-s500/manifest.json"
    runtime_cell_path = "res://data/urbis/remaining_brussels/cells/bxl-e149000-n169500-s500/runtime/cell.game.json"
    runtime_network_path = "res://data/urbis/remaining_brussels/cells/bxl-e149000-n169500-s500/runtime/network.game.json"
    strong_heights_path = "res://data/terrain/ixelles/bxl-e149000-n169500-s500_strong_heights.game.json"
    build_collision = false


func _load_dtm_contract() -> bool:
    var terrain := _read_json(TERRAIN_PATH)
    if terrain.is_empty():
        push_error("IxellesStreamedNorthDtmCell: DTM contract unavailable")
        return false
    if str(terrain.get("schema", "")) != EXPECTED_DTM_SCHEMA or str(terrain.get("cell_id", "")) != EXPECTED_CELL_ID:
        push_error("IxellesStreamedNorthDtmCell: DTM identity drifted")
        return false
    if bool(terrain.get("runtime_approved", true)) or bool(terrain.get("promote_runtime", true)):
        push_error("IxellesStreamedNorthDtmCell: source candidate approval flags drifted")
        return false
    var source: Variant = terrain.get("source", {})
    if not source is Dictionary or str(source.get("crs", "")) != "EPSG:31370":
        push_error("IxellesStreamedNorthDtmCell: official DTM CRS drifted")
        return false
    var datum: Variant = terrain.get("shared_vertical_datum", {})
    if not datum is Dictionary:
        push_error("IxellesStreamedNorthDtmCell: shared vertical datum missing")
        return false
    if str(datum.get("schema", "")) != EXPECTED_SHARED_DATUM_SCHEMA:
        push_error("IxellesStreamedNorthDtmCell: shared datum schema drifted")
        return false
    vertical_reference_absolute_m = float(datum.get("reference_absolute_m", INF))
    if not is_finite(vertical_reference_absolute_m) or absf(vertical_reference_absolute_m - EXPECTED_REFERENCE_M) > 0.000001:
        push_error("IxellesStreamedNorthDtmCell: shared vertical datum drifted")
        return false

    var bbox_raw: Variant = terrain.get("bbox_epsg31370", [])
    if not bbox_raw is Array or bbox_raw.size() != 4:
        push_error("IxellesStreamedNorthDtmCell: DTM bbox missing")
        return false
    if absf(float(bbox_raw[0]) - 149000.0) > 0.001 or absf(float(bbox_raw[1]) - 169500.0) > 0.001 or absf(float(bbox_raw[2]) - 149500.0) > 0.001 or absf(float(bbox_raw[3]) - 170000.0) > 0.001:
        push_error("IxellesStreamedNorthDtmCell: DTM bbox drifted")
        return false
    _terrain_bbox = Rect2(float(bbox_raw[0]), float(bbox_raw[1]), float(bbox_raw[2]) - float(bbox_raw[0]), float(bbox_raw[3]) - float(bbox_raw[1]))

    var shape: Variant = terrain.get("shape", [])
    if not shape is Array or shape.size() != 2:
        push_error("IxellesStreamedNorthDtmCell: DTM shape missing")
        return false
    _terrain_height = int(shape[0])
    _terrain_width = int(shape[1])
    _terrain_spacing = float(terrain.get("spacing_m", 0.0))
    terrain_sample_count = int(terrain.get("sample_count", 0))
    if _terrain_width != EXPECTED_GRID_SIZE or _terrain_height != EXPECTED_GRID_SIZE or absf(_terrain_spacing - EXPECTED_SPACING_M) > 0.0001 or terrain_sample_count != EXPECTED_SAMPLE_COUNT:
        push_error("IxellesStreamedNorthDtmCell: DTM topology drifted")
        return false

    var heights: Variant = terrain.get("heights_row_major_m", [])
    if not heights is Array or heights.size() != terrain_sample_count:
        push_error("IxellesStreamedNorthDtmCell: DTM sample payload drifted")
        return false
    _terrain_heights.resize(terrain_sample_count)
    for i: int in range(terrain_sample_count):
        var absolute_height := float(heights[i])
        if not is_finite(absolute_height):
            push_error("IxellesStreamedNorthDtmCell: non-finite DTM sample")
            return false
        _terrain_heights[i] = absolute_height - vertical_reference_absolute_m

    var coords: Variant = _cell.get("coordinate_system", {})
    if not coords is Dictionary or not bool(coords.get("coordinates_are_current_game_world", false)):
        push_error("IxellesStreamedNorthDtmCell: game-world coordinate contract missing")
        return false
    _origin_e = float(coords.get("lambert_origin_e", 0.0))
    _origin_n = float(coords.get("lambert_origin_n", 0.0))
    _world_anchor_x = float(coords.get("world_anchor_x", 0.0))
    _world_anchor_z = float(coords.get("world_anchor_z", 0.0))
    _terrain_contract_loaded = true
    return true


func _terrain_index(row: int, col: int) -> int:
    return row * _terrain_width + col


func _lambert_to_game(e: float, n: float) -> Vector3:
    return Vector3(_world_anchor_x + (e - _origin_e), 0.0, _world_anchor_z - (n - _origin_n))


func sample_dtm_height(game_x: float, game_z: float) -> float:
    var e := _origin_e + (game_x - _world_anchor_x)
    var n := _origin_n - (game_z - _world_anchor_z)
    var col_f := (e - _terrain_bbox.position.x) / _terrain_spacing
    var row_f := (n - _terrain_bbox.position.y) / _terrain_spacing
    if col_f < 0.0 or row_f < 0.0 or col_f > float(_terrain_width - 1) or row_f > float(_terrain_height - 1):
        return 0.0
    var c0 := clampi(int(floor(col_f)), 0, _terrain_width - 1)
    var r0 := clampi(int(floor(row_f)), 0, _terrain_height - 1)
    var c1 := mini(c0 + 1, _terrain_width - 1)
    var r1 := mini(r0 + 1, _terrain_height - 1)
    var tx := col_f - float(c0)
    var ty := row_f - float(r0)
    return lerpf(lerpf(_terrain_heights[_terrain_index(r0, c0)], _terrain_heights[_terrain_index(r0, c1)], tx), lerpf(_terrain_heights[_terrain_index(r1, c0)], _terrain_heights[_terrain_index(r1, c1)], tx), ty)


func _grid_game_position(row: int, col: int) -> Vector3:
    var e := _terrain_bbox.position.x + float(col) * _terrain_spacing
    var n := _terrain_bbox.position.y + float(row) * _terrain_spacing
    var point := _lambert_to_game(e, n)
    point.y = _terrain_heights[_terrain_index(row, col)]
    return point


func _terrain_normal(row: int, col: int) -> Vector3:
    var left := _terrain_heights[_terrain_index(row, maxi(col - 1, 0))]
    var right := _terrain_heights[_terrain_index(row, mini(col + 1, _terrain_width - 1))]
    var south := _terrain_heights[_terrain_index(maxi(row - 1, 0), col)]
    var north := _terrain_heights[_terrain_index(mini(row + 1, _terrain_height - 1), col)]
    var dhdx := (right - left) / (2.0 * _terrain_spacing)
    var dhdz := -(north - south) / (2.0 * _terrain_spacing)
    return Vector3(-dhdx, 1.0, -dhdz).normalized()


func _build_dtm_mesh() -> void:
    _terrain_material = _make_material(Color(0.17, 0.25, 0.13, 1.0), 0.98)
    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    vertices.resize(terrain_sample_count)
    normals.resize(terrain_sample_count)
    for row: int in range(_terrain_height):
        for col: int in range(_terrain_width):
            var index := _terrain_index(row, col)
            vertices[index] = _grid_game_position(row, col)
            normals[index] = _terrain_normal(row, col)
    var indices := PackedInt32Array()
    indices.resize((_terrain_width - 1) * (_terrain_height - 1) * 6)
    var cursor := 0
    for row: int in range(_terrain_height - 1):
        for col: int in range(_terrain_width - 1):
            var i0 := _terrain_index(row, col)
            var i1 := _terrain_index(row + 1, col)
            var i2 := _terrain_index(row, col + 1)
            var i3 := _terrain_index(row + 1, col + 1)
            indices[cursor] = i0
            indices[cursor + 1] = i1
            indices[cursor + 2] = i2
            indices[cursor + 3] = i2
            indices[cursor + 4] = i1
            indices[cursor + 5] = i3
            cursor += 6
    terrain_triangle_count = indices.size() / 3
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    mesh.surface_set_material(0, _terrain_material)
    var instance := MeshInstance3D.new()
    instance.name = "OfficialIxellesDTMMesh"
    instance.mesh = mesh
    add_child(instance)


func _heightmap_collision_data() -> PackedFloat32Array:
    var result := PackedFloat32Array()
    result.resize(_terrain_heights.size())
    for target_row: int in range(_terrain_height):
        var source_row := _terrain_height - 1 - target_row
        var target_offset := target_row * _terrain_width
        var source_offset := source_row * _terrain_width
        for col: int in range(_terrain_width):
            result[target_offset + col] = _terrain_heights[source_offset + col]
    return result


func _build_dtm_collision() -> void:
    var shape := HeightMapShape3D.new()
    shape.map_width = _terrain_width
    shape.map_depth = _terrain_height
    shape.map_data = _heightmap_collision_data()
    var collision := CollisionShape3D.new()
    collision.name = "OfficialIxellesDTMHeightMapCollision"
    collision.shape = shape
    collision.scale = Vector3(_terrain_spacing, 1.0, _terrain_spacing)
    var sw := _lambert_to_game(_terrain_bbox.position.x, _terrain_bbox.position.y)
    var ne := _lambert_to_game(_terrain_bbox.end.x, _terrain_bbox.end.y)
    collision.position = Vector3((sw.x + ne.x) * 0.5, 0.0, (sw.z + ne.z) * 0.5)
    collision.disabled = not _stream_collision_enabled
    var body := StaticBody3D.new()
    body.name = "OfficialIxellesDTMCollision"
    body.set_meta("authoritative_source", "official_urbis_dtm_2021")
    body.set_meta("collision_scope", "terrain_only")
    body.add_child(collision)
    add_child(body)


func _add_building(tool: SurfaceTool, ring: PackedVector2Array, height: float, tone: Color) -> bool:
    var triangles := Geometry2D.triangulate_polygon(ring)
    if triangles.size() < 3:
        return false
    var centroid := Vector2.ZERO
    for point: Vector2 in ring:
        centroid += point
    centroid /= float(ring.size())
    var base_y := sample_dtm_height(centroid.x, centroid.y) + building_base_y
    var top_y := base_y + height
    for raw_index: int in triangles:
        var point := ring[raw_index]
        tool.set_color(tone)
        tool.set_normal(Vector3.UP)
        tool.add_vertex(Vector3(point.x, top_y, point.y))
    for index: int in range(ring.size()):
        var a := ring[index]
        var b := ring[(index + 1) % ring.size()]
        var edge := b - a
        if edge.length_squared() <= 0.000001:
            continue
        var normal := Vector3(edge.y, 0.0, -edge.x).normalized()
        var a0 := Vector3(a.x, base_y, a.y)
        var b0 := Vector3(b.x, base_y, b.y)
        var a1 := Vector3(a.x, top_y, a.y)
        var b1 := Vector3(b.x, top_y, b.y)
        for vertex: Vector3 in [a0, b0, b1, a0, b1, a1]:
            tool.set_color(tone)
            tool.set_normal(normal)
            tool.add_vertex(vertex)
    return true


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
                var grouped_tool := SurfaceTool.new()
                grouped_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
                grouped_tool.set_material(_surface_material(key))
                grouped[key] = grouped_tool
            var target: SurfaceTool = grouped[key]
            for raw_index: int in triangle_indices:
                var point := ring[raw_index]
                target.set_normal(Vector3.UP)
                target.add_vertex(Vector3(point.x, sample_dtm_height(point.x, point.y) + surface_y, point.y))
            street_surface_count += 1
        street_surface_chunks += 1
        stream_phase_ms["street_surface_chunk"] = maxi(int(stream_phase_ms.get("street_surface_chunk", 0)), Time.get_ticks_msec() - started)
        start_index = end_index
        if start_index < surfaces.size():
            await get_tree().process_frame

    var commit_started := Time.get_ticks_msec()
    var root_node := Node3D.new()
    root_node.name = "OfficialBrusselsStreetSurfaces"
    add_child(root_node)
    for key: Variant in grouped.keys():
        var mesh: ArrayMesh = (grouped[key] as SurfaceTool).commit()
        if mesh.get_surface_count() == 0:
            continue
        var instance := MeshInstance3D.new()
        instance.name = "StreetSurfaces_%s" % str(key)
        instance.mesh = mesh
        root_node.add_child(instance)
    stream_phase_ms["street_surface_commit"] = Time.get_ticks_msec() - commit_started


func _build_streamed() -> void:
    var total_started := Time.get_ticks_msec()
    var phase_started := Time.get_ticks_msec()
    if not _load_contracts():
        return
    if cell_id != EXPECTED_CELL_ID:
        push_error("IxellesStreamedNorthDtmCell: runtime cell identity drifted")
        return
    if not _load_dtm_contract():
        return
    _make_materials()
    _build_dtm_mesh()
    _build_dtm_collision()
    stream_phase_ms["contracts_materials_dtm"] = Time.get_ticks_msec() - phase_started

    var buildings: Variant = _cell.get("buildings", [])
    if not buildings is Array:
        return
    source_building_count = buildings.size()
    var prepared := _prepare_visual_buildings(buildings as Array)
    await _build_visual_buildings_over_frames(prepared)
    blocked_unapproved_building_count = source_building_count - rendered_building_count
    var expected_buildings := _expected_geometry_count("buildings")
    if expected_buildings < 0 or source_building_count != expected_buildings:
        push_error("IxellesStreamedNorthDtmCell: building runtime count drifted")
        return
    await _build_street_surfaces_over_frames()
    var stats: Variant = _network.get("stats", {})
    if stats is Dictionary:
        street_segment_count = int(stats.get("street_segments", 0))
    var expected_surfaces := _expected_geometry_count("street_surfaces")
    runtime_loaded = _terrain_contract_loaded and terrain_triangle_count == EXPECTED_TRIANGLES and expected_surfaces >= 0 and street_surface_count == expected_surfaces and rendered_building_count + blocked_unapproved_building_count == expected_buildings
    stream_total_ms = Time.get_ticks_msec() - total_started
    if runtime_loaded:
        print("IXELLES_STREAMED_NORTH_DTM_READY: cell=%s triangles=%d surfaces=%d streets=%d visual_buildings=%d blocked_buildings=%d collision_enabled=%s total_ms=%d" % [cell_id, terrain_triangle_count, street_surface_count, street_segment_count, rendered_building_count, blocked_unapproved_building_count, str(_stream_collision_enabled), stream_total_ms])
    else:
        push_error("IxellesStreamedNorthDtmCell: runtime counts failed")


func set_streamed_collision_enabled(enabled: bool) -> void:
    _stream_collision_enabled = enabled
    build_collision = false
    var collision := get_node_or_null("OfficialIxellesDTMCollision/OfficialIxellesDTMHeightMapCollision") as CollisionShape3D
    if collision != null:
        collision.set_deferred("disabled", not enabled)


func is_streamed_collision_enabled() -> bool:
    return _stream_collision_enabled and get_node_or_null("OfficialIxellesDTMCollision") != null
