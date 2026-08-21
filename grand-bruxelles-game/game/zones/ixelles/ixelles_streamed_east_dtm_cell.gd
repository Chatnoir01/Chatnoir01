extends "res://game/zones/ixelles/ixelles_streamed_north_dtm_cell.gd"
class_name IxellesStreamedEastDtmCell

## Third bounded physical Ixelles streamed cell.
## Reuses the proven DTM mesh/collision implementation from the north cell while
## replacing every source identity with the independently locked east-cell contract.

const EAST_CELL_ID := "bxl-e149500-n169000-s500"
const EAST_TERRAIN_PATH := "res://data/terrain/ixelles/bxl-e149500-n169000-s500_dtm_2m.game.json"
const EAST_DTM_SHA256 := "bd9d2b4e1898f358c26013277c4d6700e2cbcf43aa44d68430b87183ba47d3ad"
const EAST_DTM_SCHEMA := "grand-bruxelles-ixelles-dtm-2m-runtime-candidate-v1"
const EAST_SAMPLE_COUNT := 63001
const EAST_GRID_SIZE := 251
const EAST_SPACING_M := 2.0
const EAST_TRIANGLES := 125000


func _init() -> void:
    super()
    manifest_path = "res://data/urbis/remaining_brussels/cells/bxl-e149500-n169000-s500/manifest.json"
    runtime_cell_path = "res://data/urbis/remaining_brussels/cells/bxl-e149500-n169000-s500/runtime/cell.game.json"
    runtime_network_path = "res://data/urbis/remaining_brussels/cells/bxl-e149500-n169000-s500/runtime/network.game.json"
    strong_heights_path = "res://data/terrain/ixelles/bxl-e149500-n169000-s500_strong_heights.game.json"
    build_collision = false


func _load_dtm_contract() -> bool:
    var terrain := _read_json(EAST_TERRAIN_PATH)
    if terrain.is_empty():
        push_error("IxellesStreamedEastDtmCell: DTM contract unavailable")
        return false
    if str(terrain.get("schema", "")) != EAST_DTM_SCHEMA or str(terrain.get("cell_id", "")) != EAST_CELL_ID:
        push_error("IxellesStreamedEastDtmCell: DTM identity drifted")
        return false
    if str(terrain.get("absolute_float64_sha256", "")) != EAST_DTM_SHA256:
        push_error("IxellesStreamedEastDtmCell: DTM payload fingerprint drifted")
        return false
    if bool(terrain.get("runtime_approved", true)) or bool(terrain.get("promote_runtime", true)):
        push_error("IxellesStreamedEastDtmCell: source candidate approval flags drifted")
        return false
    var source: Variant = terrain.get("source", {})
    if not source is Dictionary or str(source.get("crs", "")) != "EPSG:31370":
        push_error("IxellesStreamedEastDtmCell: official DTM CRS drifted")
        return false
    var datum: Variant = terrain.get("shared_vertical_datum", {})
    if not datum is Dictionary or not _shared_datum_valid(datum as Dictionary):
        push_error("IxellesStreamedEastDtmCell: shared vertical datum drifted")
        return false
    vertical_reference_absolute_m = float((datum as Dictionary).get("reference_absolute_m", INF))

    var bbox_raw: Variant = terrain.get("bbox_epsg31370", [])
    if not bbox_raw is Array or bbox_raw.size() != 4:
        push_error("IxellesStreamedEastDtmCell: DTM bbox missing")
        return false
    if absf(float(bbox_raw[0]) - 149500.0) > 0.001 or absf(float(bbox_raw[1]) - 169000.0) > 0.001 or absf(float(bbox_raw[2]) - 150000.0) > 0.001 or absf(float(bbox_raw[3]) - 169500.0) > 0.001:
        push_error("IxellesStreamedEastDtmCell: DTM bbox drifted")
        return false
    _terrain_bbox = Rect2(float(bbox_raw[0]), float(bbox_raw[1]), float(bbox_raw[2]) - float(bbox_raw[0]), float(bbox_raw[3]) - float(bbox_raw[1]))

    var shape: Variant = terrain.get("shape", [])
    if not shape is Array or shape.size() != 2:
        push_error("IxellesStreamedEastDtmCell: DTM shape missing")
        return false
    _terrain_height = int(shape[0])
    _terrain_width = int(shape[1])
    _terrain_spacing = float(terrain.get("spacing_m", 0.0))
    terrain_sample_count = int(terrain.get("sample_count", 0))
    if _terrain_width != EAST_GRID_SIZE or _terrain_height != EAST_GRID_SIZE or absf(_terrain_spacing - EAST_SPACING_M) > 0.0001 or terrain_sample_count != EAST_SAMPLE_COUNT:
        push_error("IxellesStreamedEastDtmCell: DTM topology drifted")
        return false

    var heights: Variant = terrain.get("heights_row_major_m", [])
    if not heights is Array or heights.size() != terrain_sample_count:
        push_error("IxellesStreamedEastDtmCell: DTM sample payload drifted")
        return false
    _terrain_heights.resize(terrain_sample_count)
    for i: int in range(terrain_sample_count):
        var absolute_height := float(heights[i])
        if not is_finite(absolute_height):
            push_error("IxellesStreamedEastDtmCell: non-finite DTM sample")
            return false
        _terrain_heights[i] = absolute_height - vertical_reference_absolute_m

    var coords: Variant = _cell.get("coordinate_system", {})
    if not coords is Dictionary or not bool(coords.get("coordinates_are_current_game_world", false)):
        push_error("IxellesStreamedEastDtmCell: game-world coordinate contract missing")
        return false
    _origin_e = float(coords.get("lambert_origin_e", 0.0))
    _origin_n = float(coords.get("lambert_origin_n", 0.0))
    _world_anchor_x = float(coords.get("world_anchor_x", 0.0))
    _world_anchor_z = float(coords.get("world_anchor_z", 0.0))
    _terrain_contract_loaded = true
    return true


func _build_streamed() -> void:
    var total_started := Time.get_ticks_msec()
    var phase_started := Time.get_ticks_msec()
    if not _load_contracts():
        return
    if cell_id != EAST_CELL_ID:
        push_error("IxellesStreamedEastDtmCell: runtime cell identity drifted")
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
        push_error("IxellesStreamedEastDtmCell: building runtime count drifted")
        return
    await _build_street_surfaces_over_frames()
    var stats: Variant = _network.get("stats", {})
    if stats is Dictionary:
        street_segment_count = int(stats.get("street_segments", 0))
    var expected_surfaces := _expected_geometry_count("street_surfaces")
    runtime_loaded = _terrain_contract_loaded and terrain_triangle_count == EAST_TRIANGLES and expected_surfaces >= 0 and street_surface_count == expected_surfaces and rendered_building_count + blocked_unapproved_building_count == expected_buildings
    stream_total_ms = Time.get_ticks_msec() - total_started
    if runtime_loaded:
        print("IXELLES_STREAMED_EAST_DTM_READY: cell=%s triangles=%d surfaces=%d streets=%d visual_buildings=%d blocked_buildings=%d collision_enabled=%s total_ms=%d" % [cell_id, terrain_triangle_count, street_surface_count, street_segment_count, rendered_building_count, blocked_unapproved_building_count, str(_stream_collision_enabled), stream_total_ms])
    else:
        push_error("IxellesStreamedEastDtmCell: runtime counts failed")
