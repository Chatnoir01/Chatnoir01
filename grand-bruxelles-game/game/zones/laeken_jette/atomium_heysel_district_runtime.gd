extends Node3D

## Source-bounded Atomium / Heysel district runtime.
##
## Geometry stays in the project UrbIS game-space X/Z convention. Vertical placement
## is owned by the exact official Atomium DTM instance supplied by the direct-spawn
## bootstrap. Building massing is rendered only when an explicit source height exists;
## unresolved 2D footprints are never promoted to invented 10.5 m boxes.

const COMPACT_ROOT := "res://data/urbis/laeken_jette/atomium_heysel_runtime"
const CANONICAL_ROOT := "res://data/urbis/laeken_jette"
const DTM_DATA_PATH := "res://data/terrain/laeken_jette/atomium_dtm.game.json"
const EXPECTED_CRS := "EPSG:31370"
const WEB_PLATFORM := "Web"

@export var build_collision := true

var terrain_provider: Node = null
var runtime_loaded := false
var compact_payload_used := false
var source_bbox_epsg31370 := Rect2()
var source_origin_e := 0.0
var source_origin_n := 0.0
var last_stats: Dictionary = {
    "buildings": 0,
    "rendered_buildings": 0,
    "unresolved_height_buildings": 0,
    "street_surfaces": 0,
    "street_axes": 0,
    "tram_network": 0,
    "train_network": 0,
}

var _road_material: StandardMaterial3D
var _building_material: StandardMaterial3D
var _building_footprint_material: StandardMaterial3D
var _rail_material: StandardMaterial3D
var _tram_material: StandardMaterial3D

func _ready() -> void:
    _make_materials()
    if terrain_provider == null or not terrain_provider.has_method("sample_height") or not terrain_provider.has_method("contains_game_point"):
        push_error("AtomiumHeyselDistrictRuntime: official DTM terrain provider unavailable")
        return
    if not _load_bounds_contract():
        push_error("AtomiumHeyselDistrictRuntime: DTM bounds contract unavailable")
        return
    if not _build_layers():
        push_error("AtomiumHeyselDistrictRuntime: no bounded district geometry built")
        return
    runtime_loaded = int(last_stats.get("street_surfaces", 0)) > 0 and int(last_stats.get("street_axes", 0)) > 0
    if runtime_loaded:
        set_meta("source_crs", EXPECTED_CRS)
        set_meta("source_bbox_epsg31370", [source_bbox_epsg31370.position.x, source_bbox_epsg31370.position.y, source_bbox_epsg31370.end.x, source_bbox_epsg31370.end.y])
        set_meta("compact_payload_used", compact_payload_used)
        set_meta("vertical_owner", "official_atomium_dtm")
        set_meta("invented_building_height_fallback", false)
        print("ATOMIUM_HEYSEL_DISTRICT_READY: compact=%s terrain=official_dtm stats=%s" % [str(compact_payload_used), JSON.stringify(last_stats)])

func _make_materials() -> void:
    _road_material = _material(Color(0.145, 0.15, 0.16, 1.0), 0.96)
    _building_material = _material(Color(0.60, 0.56, 0.51, 1.0), 0.92)
    _building_footprint_material = _material(Color(0.46, 0.42, 0.37, 1.0), 0.98)
    _rail_material = _material(Color(0.16, 0.17, 0.18, 1.0), 0.42, 0.54)
    _tram_material = _material(Color(0.27, 0.27, 0.27, 1.0), 0.55, 0.30)

func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    return material

func _load_bounds_contract() -> bool:
    var data := _read_json(DTM_DATA_PATH)
    if data.is_empty() or str(data.get("source_crs", "")) != EXPECTED_CRS:
        return false
    var bounds: Variant = data.get("bounds_epsg31370", {})
    if not bounds is Dictionary:
        return false
    var min_e := float(bounds.get("min_e", NAN))
    var min_n := float(bounds.get("min_n", NAN))
    var max_e := float(bounds.get("max_e", NAN))
    var max_n := float(bounds.get("max_n", NAN))
    source_origin_e = float(data.get("game_origin_e", NAN))
    source_origin_n = float(data.get("game_origin_n", NAN))
    if not is_finite(min_e) or not is_finite(min_n) or not is_finite(max_e) or not is_finite(max_n) or not is_finite(source_origin_e) or not is_finite(source_origin_n):
        return false
    if max_e <= min_e or max_n <= min_n:
        return false
    source_bbox_epsg31370 = Rect2(Vector2(min_e, min_n), Vector2(max_e - min_e, max_n - min_n))
    return true

func _build_layers() -> bool:
    var compact_available := _compact_layer_set_available()
    compact_payload_used = compact_available
    if OS.get_name() == WEB_PLATFORM and not compact_available:
        push_error("AtomiumHeyselDistrictRuntime: Web requires compact Heysel payload")
        return false
    var root := COMPACT_ROOT if compact_available else CANONICAL_ROOT
    var roads := _bounded_document(_read_json(root + "/street_surfaces.game.json"))
    var buildings := _bounded_document(_read_json(root + "/buildings.game.json"))
    var axes := _bounded_document(_read_json(root + "/street_axes.game.json"))
    var trams := _bounded_document(_read_json(root + "/tram_network.game.json"))
    var trains := _bounded_document(_read_json(root + "/train_network.game.json"))

    last_stats["street_surfaces"] = _feature_count(roads)
    last_stats["buildings"] = _feature_count(buildings)
    last_stats["street_axes"] = _feature_count(axes)
    last_stats["tram_network"] = _feature_count(trams)
    last_stats["train_network"] = _feature_count(trains)

    _build_draped_polygon_layer(roads, "AtomiumHeyselStreetSurfaces", _road_material, 0.035)
    _build_source_height_buildings(buildings)
    _build_draped_line_layer(axes, "AtomiumHeyselStreetAxes", _road_material, 0.34, 0.055)
    _build_draped_line_layer(trams, "AtomiumHeyselTramNetwork", _tram_material, 1.0, 0.075)
    _build_draped_line_layer(trains, "AtomiumHeyselTrainNetwork", _rail_material, 1.45, 0.095)
    return int(last_stats["street_surfaces"]) > 0 and int(last_stats["street_axes"]) > 0

func _compact_layer_set_available() -> bool:
    return FileAccess.file_exists(COMPACT_ROOT + "/buildings.game.json") and FileAccess.file_exists(COMPACT_ROOT + "/street_surfaces.game.json") and FileAccess.file_exists(COMPACT_ROOT + "/street_axes.game.json")

func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed as Dictionary if parsed is Dictionary else {}

func _feature_count(document: Dictionary) -> int:
    var features: Variant = document.get("features", [])
    return features.size() if features is Array else 0

func _bounded_document(document: Dictionary) -> Dictionary:
    if document.is_empty():
        return {}
    var features: Variant = document.get("features", [])
    if not features is Array:
        return {}
    var kept: Array = []
    for raw: Variant in features:
        if raw is Dictionary and _feature_intersects_dtm(raw as Dictionary):
            kept.append(raw)
    var result := document.duplicate(false)
    result["features"] = kept
    return result

func _feature_intersects_dtm(feature: Dictionary) -> bool:
    var geometry: Variant = feature.get("geometry", {})
    if not geometry is Dictionary:
        return false
    for point: Vector2 in _geometry_points(geometry as Dictionary):
        if source_bbox_epsg31370.has_point(_to_epsg31370(point)):
            return true
    return false

func _geometry_points(geometry: Dictionary) -> PackedVector2Array:
    var result := PackedVector2Array()
    _collect_points(geometry.get("coordinates", []), result)
    return result

func _collect_points(raw: Variant, result: PackedVector2Array) -> void:
    if not raw is Array:
        return
    var values := raw as Array
    if values.size() >= 2 and (values[0] is int or values[0] is float) and (values[1] is int or values[1] is float):
        result.append(Vector2(float(values[0]), float(values[1])))
        return
    for child: Variant in values:
        _collect_points(child, result)

func _to_epsg31370(game_xz: Vector2) -> Vector2:
    return Vector2(source_origin_e + game_xz.x, source_origin_n - game_xz.y)

func _terrain_y(point: Vector2, offset: float = 0.0) -> float:
    if terrain_provider == null or not bool(terrain_provider.call("contains_game_point", point.x, point.y)):
        return NAN
    return float(terrain_provider.call("sample_height", point.x, point.y)) + offset

func _outer_rings(geometry: Dictionary) -> Array:
    var result: Array = []
    var kind := str(geometry.get("type", ""))
    var coords: Variant = geometry.get("coordinates", [])
    if kind == "Polygon" and coords is Array and not coords.is_empty():
        result.append(coords[0])
    elif kind == "MultiPolygon" and coords is Array:
        for polygon: Variant in coords:
            if polygon is Array and not polygon.is_empty():
                result.append(polygon[0])
    return result

func _line_strings(geometry: Dictionary) -> Array:
    var result: Array = []
    var kind := str(geometry.get("type", ""))
    var coords: Variant = geometry.get("coordinates", [])
    if kind == "LineString" and coords is Array:
        result.append(coords)
    elif kind == "MultiLineString" and coords is Array:
        for line: Variant in coords:
            if line is Array:
                result.append(line)
    return result

func _ring_points(ring: Array) -> PackedVector2Array:
    var points := PackedVector2Array()
    for raw: Variant in ring:
        if raw is Array and raw.size() >= 2:
            points.append(Vector2(float(raw[0]), float(raw[1])))
    if points.size() >= 2 and points[0].distance_to(points[points.size() - 1]) < 0.001:
        points.resize(points.size() - 1)
    return points

func _source_height(properties: Dictionary) -> float:
    for key: String in ["height", "Height", "HEIGHT", "roof_height", "RoofHeight", "ROOFHEIGHT", "measured_height", "MEASURED_HEIGHT"]:
        if not properties.has(key):
            continue
        var value := float(properties[key])
        if value >= 2.5 and value <= 220.0:
            return value
    return NAN

func _append_draped_surface(st: SurfaceTool, points: PackedVector2Array, offset: float) -> bool:
    var heights := PackedFloat32Array()
    heights.resize(points.size())
    for i: int in range(points.size()):
        var y := _terrain_y(points[i], offset)
        if not is_finite(y):
            return false
        heights[i] = y
    var indices := Geometry2D.triangulate_polygon(points)
    if indices.is_empty():
        return false
    for index: int in indices:
        var point := points[index]
        st.set_normal(Vector3.UP)
        st.add_vertex(Vector3(point.x, heights[index], point.y))
    return true

func _append_source_height_building(st: SurfaceTool, points: PackedVector2Array, height: float) -> bool:
    var base_heights := PackedFloat32Array()
    base_heights.resize(points.size())
    for i: int in range(points.size()):
        var y := _terrain_y(points[i], 0.025)
        if not is_finite(y):
            return false
        base_heights[i] = y

    var roof_indices := Geometry2D.triangulate_polygon(points)
    if roof_indices.is_empty():
        return false
    for index: int in roof_indices:
        var point := points[index]
        st.set_normal(Vector3.UP)
        st.add_vertex(Vector3(point.x, base_heights[index] + height, point.y))

    for i: int in range(points.size()):
        var j := (i + 1) % points.size()
        var a := points[i]
        var b := points[j]
        var edge := b - a
        if edge.length_squared() < 0.0001:
            continue
        var normal := Vector3(edge.y, 0.0, -edge.x).normalized()
        var a0 := Vector3(a.x, base_heights[i], a.y)
        var a1 := Vector3(a.x, base_heights[i] + height, a.y)
        var b0 := Vector3(b.x, base_heights[j], b.y)
        var b1 := Vector3(b.x, base_heights[j] + height, b.y)
        for vertex: Vector3 in [a0, b0, b1, a0, b1, a1]:
            st.set_normal(normal)
            st.add_vertex(vertex)
    return true

func _build_draped_polygon_layer(document: Dictionary, node_name: String, material: Material, offset: float) -> void:
    var features: Variant = document.get("features", [])
    if not features is Array or features.is_empty():
        return
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for raw: Variant in features:
        if not raw is Dictionary:
            continue
        var geometry: Variant = (raw as Dictionary).get("geometry", {})
        if not geometry is Dictionary:
            continue
        for ring: Variant in _outer_rings(geometry as Dictionary):
            if ring is Array:
                var points := _ring_points(ring as Array)
                if points.size() >= 3:
                    _append_draped_surface(st, points, offset)
    _commit_mesh(st, node_name, material, false)

func _build_source_height_buildings(document: Dictionary) -> void:
    var features: Variant = document.get("features", [])
    if not features is Array or features.is_empty():
        return
    var massing := SurfaceTool.new()
    massing.begin(Mesh.PRIMITIVE_TRIANGLES)
    var footprints := SurfaceTool.new()
    footprints.begin(Mesh.PRIMITIVE_TRIANGLES)
    var rendered := 0
    var unresolved := 0
    for raw: Variant in features:
        if not raw is Dictionary:
            continue
        var feature := raw as Dictionary
        var geometry: Variant = feature.get("geometry", {})
        var properties: Variant = feature.get("properties", {})
        if not geometry is Dictionary or not properties is Dictionary:
            continue
        var height := _source_height(properties as Dictionary)
        var built_feature := false
        for ring: Variant in _outer_rings(geometry as Dictionary):
            if not ring is Array:
                continue
            var points := _ring_points(ring as Array)
            if points.size() < 3:
                continue
            if is_finite(height):
                built_feature = _append_source_height_building(massing, points, height) or built_feature
            else:
                _append_draped_surface(footprints, points, 0.045)
        if is_finite(height) and built_feature:
            rendered += 1
        elif not is_finite(height):
            unresolved += 1
    last_stats["rendered_buildings"] = rendered
    last_stats["unresolved_height_buildings"] = unresolved
    _commit_mesh(massing, "AtomiumHeyselSourceHeightBuildings", _building_material, build_collision)
    _commit_mesh(footprints, "AtomiumHeyselUnresolvedBuildingFootprints", _building_footprint_material, false)

func _build_draped_line_layer(document: Dictionary, node_name: String, material: Material, width: float, offset: float) -> void:
    var features: Variant = document.get("features", [])
    if not features is Array or features.is_empty():
        return
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for raw: Variant in features:
        if not raw is Dictionary:
            continue
        var geometry: Variant = (raw as Dictionary).get("geometry", {})
        if not geometry is Dictionary:
            continue
        for raw_line: Variant in _line_strings(geometry as Dictionary):
            if raw_line is Array:
                _append_draped_line_ribbon(st, raw_line as Array, width, offset)
    _commit_mesh(st, node_name, material, false)

func _append_draped_line_ribbon(st: SurfaceTool, line: Array, width: float, offset: float) -> void:
    if line.size() < 2:
        return
    for i: int in range(line.size() - 1):
        var raw_a: Variant = line[i]
        var raw_b: Variant = line[i + 1]
        if not raw_a is Array or not raw_b is Array or raw_a.size() < 2 or raw_b.size() < 2:
            continue
        var a := Vector2(float(raw_a[0]), float(raw_a[1]))
        var b := Vector2(float(raw_b[0]), float(raw_b[1]))
        var delta := b - a
        if delta.length_squared() < 0.0001:
            continue
        var side := Vector2(-delta.y, delta.x).normalized() * width * 0.5
        var corners: Array[Vector2] = [a + side, a - side, b - side, b + side]
        var vertices: Array[Vector3] = []
        for corner: Vector2 in corners:
            var y := _terrain_y(corner, offset)
            if not is_finite(y):
                vertices.clear()
                break
            vertices.append(Vector3(corner.x, y, corner.y))
        if vertices.size() != 4:
            continue
        for index: int in [0, 1, 2, 0, 2, 3]:
            st.set_normal(Vector3.UP)
            st.add_vertex(vertices[index])

func _commit_mesh(st: SurfaceTool, node_name: String, material: Material, collision: bool) -> void:
    var mesh := st.commit()
    if mesh == null or mesh.get_surface_count() == 0:
        return
    mesh.surface_set_material(0, material)
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    add_child(instance)
    if collision:
        instance.create_trimesh_collision()
