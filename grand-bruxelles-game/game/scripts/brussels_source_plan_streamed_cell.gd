extends Node3D
class_name BrusselsSourcePlanStreamedCell

## Source-safe streamed renderer for Brussels cells that have authoritative
## UrbIS plan geometry but do not yet have approved terrain/building heights.
## It renders only source-backed street-surface polygons. Buildings are counted
## and intentionally blocked until a separate strong-height contract exists.

@export_file("*.json") var manifest_path := ""
@export_file("*.json") var runtime_cell_path := ""
@export_file("*.json") var runtime_network_path := ""
@export var build_collision := false
@export var street_surface_features_per_frame := 48
@export var surface_y := 0.035

var runtime_loaded := false
var cell_id := ""
var street_surface_count := 0
var street_segment_count := 0
var source_building_count := 0
var blocked_unapproved_building_count := 0
var rendered_building_count := 0
var stream_total_ms := 0
var stream_phase_ms: Dictionary = {}
var street_surface_chunks := 0

var _manifest: Dictionary = {}
var _cell: Dictionary = {}
var _network: Dictionary = {}
var _road_material: StandardMaterial3D
var _sidewalk_material: StandardMaterial3D
var _paved_material: StandardMaterial3D
var _other_material: StandardMaterial3D


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


func _build_streamed() -> void:
    var total_started := Time.get_ticks_msec()
    var phase_started := Time.get_ticks_msec()
    if not _load_contracts():
        return
    _make_materials()
    stream_phase_ms["contracts_materials"] = Time.get_ticks_msec() - phase_started

    var buildings: Variant = _cell.get("buildings", [])
    if buildings is Array:
        source_building_count = buildings.size()
        # Deliberate hard gate: this renderer has no strong-height contract.
        blocked_unapproved_building_count = source_building_count
        rendered_building_count = 0

    var expected_buildings := _expected_geometry_count("buildings")
    if expected_buildings < 0 or source_building_count != expected_buildings:
        push_error("BrusselsSourcePlanStreamedCell: building runtime count drifted for %s" % cell_id)
        return

    await _build_street_surfaces_over_frames()

    var stats: Variant = _network.get("stats", {})
    if stats is Dictionary:
        street_segment_count = int(stats.get("street_segments", 0))

    var expected_surfaces := _expected_geometry_count("street_surfaces")
    runtime_loaded = expected_surfaces >= 0 and street_surface_count == expected_surfaces and blocked_unapproved_building_count == expected_buildings and rendered_building_count == 0
    stream_total_ms = Time.get_ticks_msec() - total_started
    if runtime_loaded:
        print("BRUSSELS_SOURCE_PLAN_CELL_READY: cell=%s surfaces=%d street_segments=%d blocked_buildings=%d total_ms=%d max_phase_ms=%d chunks=%d" % [cell_id, street_surface_count, street_segment_count, blocked_unapproved_building_count, stream_total_ms, get_max_stream_phase_ms(), street_surface_chunks])
    else:
        push_error("BrusselsSourcePlanStreamedCell: runtime counts failed for %s surfaces=%d/%d buildings=%d/%d" % [cell_id, street_surface_count, expected_surfaces, blocked_unapproved_building_count, expected_buildings])


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
                target.set_normal(Vector3.UP)
                target.add_vertex(Vector3(point.x, surface_y, point.y))
            street_surface_count += 1

        street_surface_chunks += 1
        stream_phase_ms["street_surface_chunk"] = maxi(int(stream_phase_ms.get("street_surface_chunk", 0)), Time.get_ticks_msec() - started)
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
    stream_phase_ms["street_surface_commit"] = Time.get_ticks_msec() - commit_started


func set_collision_streaming_enabled(_enabled: bool) -> void:
    # No authoritative terrain/vertical collision contract exists for these
    # plan-only cells yet. The shared gameplay ground remains authoritative.
    build_collision = false


func get_max_stream_phase_ms() -> int:
    var maximum := 0
    for phase_name: String in stream_phase_ms.keys():
        maximum = maxi(maximum, int(stream_phase_ms[phase_name]))
    return maximum
