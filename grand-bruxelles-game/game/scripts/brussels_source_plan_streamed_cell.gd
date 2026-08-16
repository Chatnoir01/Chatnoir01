extends Node3D
class_name BrusselsSourcePlanStreamedCell

## Source-safe streamed renderer for Brussels cells with authoritative UrbIS
## plan geometry. Street surfaces always stay plan-backed. Optional strong-height
## contracts may add VISUAL-ONLY building massing; they never authorize gameplay
## collision or authoritative building heights.

@export_file("*.json") var manifest_path := ""
@export_file("*.json") var runtime_cell_path := ""
@export_file("*.json") var runtime_network_path := ""
@export_file("*.json") var strong_heights_path := ""
@export var build_collision := false
@export var street_surface_features_per_frame := 48
@export var building_features_per_frame := 48
@export var surface_y := 0.035
@export var building_base_y := 0.04

var runtime_loaded := false
var cell_id := ""
var street_surface_count := 0
var street_segment_count := 0
var source_building_count := 0
var blocked_unapproved_building_count := 0
var rendered_building_count := 0
var strong_height_contract_loaded := false
var stream_total_ms := 0
var stream_phase_ms: Dictionary = {}
var street_surface_chunks := 0
var building_massing_chunks := 0

var _manifest: Dictionary = {}
var _cell: Dictionary = {}
var _network: Dictionary = {}
var _strong_heights: Dictionary = {}
var _road_material: StandardMaterial3D
var _sidewalk_material: StandardMaterial3D
var _paved_material: StandardMaterial3D
var _other_material: StandardMaterial3D
var _building_material: StandardMaterial3D


func _ready() -> void:
    call_deferred("_build_streamed")


func _read_json(path: String) -> Dictionary:
    if path.is_empty() or not FileAccess.file_exists(path):
        push_error("BrusselsSourcePlanStreamedCell: missing runtime contract %s" % path)
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("BrusselsSourcePlanStreamedCell: invalid JSON %s" % path)
        return {}
    return parsed as Dictionary


func _load_contracts() -> bool:
    _manifest = _read_json(manifest_path)
    _cell = _read_json(runtime_cell_path)
    _network = _read_json(runtime_network_path)
    if _manifest.is_empty() or _cell.is_empty() or _network.is_empty():
        return false

    cell_id = str(_manifest.get("cell_id", ""))
    if cell_id.is_empty() or str(_cell.get("cell_id", "")) != cell_id or str(_network.get("cell_id", "")) != cell_id:
        push_error("BrusselsSourcePlanStreamedCell: cell contract mismatch")
        return false
    if str(_manifest.get("crs", "")) != "EPSG:31370":
        push_error("BrusselsSourcePlanStreamedCell: non-Lambert72 source contract")
        return false

    var coords: Variant = _cell.get("coordinate_system", {})
    if not coords is Dictionary or not bool(coords.get("coordinates_are_current_game_world", false)):
        push_error("BrusselsSourcePlanStreamedCell: current-game-world coordinate contract missing")
        return false

    var runtime_manifest: Variant = _manifest.get("runtime", {})
    if not runtime_manifest is Dictionary:
        return false
    if str(runtime_manifest.get("geometry_format", "")) != "grand-bruxelles-urbis-cell-runtime-v1":
        push_error("BrusselsSourcePlanStreamedCell: unexpected geometry runtime format")
        return false
    if str(runtime_manifest.get("network_format", "")) != "grand-bruxelles-urbis-network-cell-runtime-v2":
        push_error("BrusselsSourcePlanStreamedCell: unexpected network runtime format")
        return false
    return true


func _make_material(color: Color, roughness: float) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    return material


func _make_materials() -> void:
    _road_material = _make_material(Color(0.075, 0.078, 0.082, 1.0), 0.97)
    _sidewalk_material = _make_material(Color(0.45, 0.435, 0.405, 1.0), 0.94)
    _paved_material = _make_material(Color(0.39, 0.375, 0.345, 1.0), 0.95)
    _other_material = _make_material(Color(0.28, 0.285, 0.28, 1.0), 0.95)
    _building_material = _make_material(Color(0.60, 0.53, 0.45, 1.0), 0.90)


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


func _prepare_visual_buildings(buildings: Array) -> Array:
    if strong_heights_path.is_empty():
        return []
    _strong_heights = _read_json(strong_heights_path)
    if _strong_heights.is_empty():
        return []
    if str(_strong_heights.get("schema", "")) != "grand-bruxelles-ixelles-strong-height-candidates-v1" or str(_strong_heights.get("cell_id", "")) != cell_id:
        push_error("BrusselsSourcePlanStreamedCell: strong-height identity mismatch for %s" % cell_id)
        return []
    if bool(_strong_heights.get("runtime_approved", false)):
        push_error("BrusselsSourcePlanStreamedCell: visual candidate contract unexpectedly runtime-approved")
        return []
    var policy: Variant = _strong_heights.get("policy", {})
    if not policy is Dictionary or float(policy.get("max_abs_delta_m", INF)) != 2.0 or float(policy.get("min_semantic_match_score", -INF)) != 0.90 or float(policy.get("min_semantic_match_margin", -INF)) != 0.25 or str(policy.get("required_dsm_confidence", "")) != "high":
        push_error("BrusselsSourcePlanStreamedCell: strong-height policy drifted for %s" % cell_id)
        return []
    var records: Variant = _strong_heights.get("records", [])
    if not records is Array or records.size() != int(_strong_heights.get("eligible_count", -1)):
        push_error("BrusselsSourcePlanStreamedCell: strong-height record count drifted for %s" % cell_id)
        return []

    var footprints: Dictionary = {}
    for building: Variant in buildings:
        if building is Dictionary:
            var building_id := str(building.get("id", ""))
            if not building_id.is_empty():
                footprints[building_id] = building.get("footprint", [])

    var prepared: Array = []
    var seen: Dictionary = {}
    for record: Variant in records:
        if not record is Dictionary:
            return []
        var building_id := str(record.get("building_id", ""))
        var height := float(record.get("semantic_height_m", 0.0))
        if building_id.is_empty() or seen.has(building_id) or not footprints.has(building_id):
            push_error("BrusselsSourcePlanStreamedCell: unjoinable strong-height building %s" % building_id)
            return []
        if not bool(record.get("visual_runtime_eligible", false)) or bool(record.get("runtime_approved", false)) or float(record.get("abs_delta_m", INF)) > 2.0 or float(record.get("semantic_match_score", -INF)) < 0.90 or float(record.get("semantic_match_margin", -INF)) < 0.25 or height <= 0.0:
            push_error("BrusselsSourcePlanStreamedCell: unsafe strong-height record %s" % building_id)
            return []
        var footprint := _ring(footprints[building_id])
        if footprint.size() < 3:
            push_error("BrusselsSourcePlanStreamedCell: invalid source footprint %s" % building_id)
            return []
        seen[building_id] = true
        prepared.append({"id": building_id, "height": height, "footprint": footprint})
    strong_height_contract_loaded = true
    return prepared


func _add_building(tool: SurfaceTool, ring: PackedVector2Array, height: float) -> bool:
    var triangles := Geometry2D.triangulate_polygon(ring)
    if triangles.size() < 3:
        return false
    var top_y := building_base_y + height
    for raw_index: int in triangles:
        var point := ring[raw_index]
        tool.set_normal(Vector3.UP)
        tool.add_vertex(Vector3(point.x, top_y, point.y))
    for index: int in range(ring.size()):
        var a := ring[index]
        var b := ring[(index + 1) % ring.size()]
        var edge := b - a
        if edge.length_squared() <= 0.000001:
            continue
        var normal := Vector3(edge.y, 0.0, -edge.x).normalized()
        var a0 := Vector3(a.x, building_base_y, a.y)
        var b0 := Vector3(b.x, building_base_y, b.y)
        var a1 := Vector3(a.x, top_y, a.y)
        var b1 := Vector3(b.x, top_y, b.y)
        for vertex: Vector3 in [a0, b0, b1, a0, b1, a1]:
            tool.set_normal(normal)
            tool.add_vertex(vertex)
    return true


func _build_visual_buildings_over_frames(prepared: Array) -> void:
    if prepared.is_empty():
        return
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(_building_material)
    var chunk_size := maxi(building_features_per_frame, 1)
    var start_index := 0
    while start_index < prepared.size():
        var started := Time.get_ticks_msec()
        var end_index := mini(start_index + chunk_size, prepared.size())
        for feature_index: int in range(start_index, end_index):
            var building: Dictionary = prepared[feature_index]
            if _add_building(tool, building["footprint"] as PackedVector2Array, float(building["height"])):
                rendered_building_count += 1
        building_massing_chunks += 1
        stream_phase_ms["building_massing_chunk"] = maxi(int(stream_phase_ms.get("building_massing_chunk", 0)), Time.get_ticks_msec() - started)
        start_index = end_index
        if start_index < prepared.size():
            await get_tree().process_frame

    var commit_started := Time.get_ticks_msec()
    var mesh: ArrayMesh = tool.commit()
    if mesh.get_surface_count() > 0:
        var instance := MeshInstance3D.new()
        instance.name = "VisualCandidateBuildingMassing"
        instance.mesh = mesh
        instance.set_meta("visual_only", true)
        instance.set_meta("runtime_approved", false)
        add_child(instance)
    stream_phase_ms["building_massing_commit"] = Time.get_ticks_msec() - commit_started


func _build_streamed() -> void:
    var total_started := Time.get_ticks_msec()
    var phase_started := Time.get_ticks_msec()
    if not _load_contracts():
        return
    _make_materials()
    stream_phase_ms["contracts_materials"] = Time.get_ticks_msec() - phase_started

    var buildings: Variant = _cell.get("buildings", [])
    if not buildings is Array:
        return
    source_building_count = buildings.size()
    var prepared := _prepare_visual_buildings(buildings as Array)
    await _build_visual_buildings_over_frames(prepared)
    blocked_unapproved_building_count = source_building_count - rendered_building_count

    var expected_buildings := _expected_geometry_count("buildings")
    if expected_buildings < 0 or source_building_count != expected_buildings:
        push_error("BrusselsSourcePlanStreamedCell: building runtime count drifted for %s" % cell_id)
        return

    await _build_street_surfaces_over_frames()

    var stats: Variant = _network.get("stats", {})
    if stats is Dictionary:
        street_segment_count = int(stats.get("street_segments", 0))

    var expected_surfaces := _expected_geometry_count("street_surfaces")
    runtime_loaded = expected_surfaces >= 0 and street_surface_count == expected_surfaces and rendered_building_count + blocked_unapproved_building_count == expected_buildings
    stream_total_ms = Time.get_ticks_msec() - total_started
    if runtime_loaded:
        print("BRUSSELS_SOURCE_PLAN_CELL_READY: cell=%s surfaces=%d street_segments=%d visual_buildings=%d blocked_buildings=%d strong_heights=%s total_ms=%d max_phase_ms=%d surface_chunks=%d building_chunks=%d" % [cell_id, street_surface_count, street_segment_count, rendered_building_count, blocked_unapproved_building_count, str(strong_height_contract_loaded), stream_total_ms, get_max_stream_phase_ms(), street_surface_chunks, building_massing_chunks])
    else:
        push_error("BrusselsSourcePlanStreamedCell: runtime counts failed for %s surfaces=%d/%d buildings=%d+%d/%d" % [cell_id, street_surface_count, expected_surfaces, rendered_building_count, blocked_unapproved_building_count, expected_buildings])


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
                target.add_vertex(Vector3(point.x, surface_y, point.y))
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


func set_collision_streaming_enabled(_enabled: bool) -> void:
    # Visual candidate massing is never gameplay-authoritative collision.
    build_collision = false


func get_max_stream_phase_ms() -> int:
    var maximum := 0
    for phase_name: String in stream_phase_ms.keys():
        maximum = maxi(maximum, int(stream_phase_ms[phase_name]))
    return maximum
