extends Node3D

## Source-bounded Atomium / Heysel district runtime.
##
## The runtime prefers a compact committed slice for Web. On desktop/editor it may
## fall back to the canonical Laeken-Jette UrbIS phase-1 payloads, but it clips every
## feature to the exact official Atomium DTM tile before building anything. This keeps
## the district source-backed while avoiding a second invented coordinate system.

const COMPACT_ROOT := "res://data/urbis/laeken_jette/atomium_heysel_runtime"
const CANONICAL_ROOT := "res://data/urbis/laeken_jette"
const DTM_DATA_PATH := "res://data/terrain/laeken_jette/atomium_dtm.game.json"
const EXPECTED_CRS := "EPSG:31370"
const EXPECTED_FORMAT := "grand-bruxelles-urbis-game-v1"
const WEB_PLATFORM := "Web"

@export var building_default_height_m := 10.5
@export var build_collision := true

var runtime_loaded := false
var compact_payload_used := false
var source_bbox_epsg31370 := Rect2()
var source_origin_e := 0.0
var source_origin_n := 0.0
var last_stats: Dictionary = {
    "buildings": 0,
    "street_surfaces": 0,
    "street_axes": 0,
    "tram_network": 0,
    "train_network": 0,
}

var _road_material: StandardMaterial3D
var _building_material: StandardMaterial3D
var _rail_material: StandardMaterial3D
var _tram_material: StandardMaterial3D

func _ready() -> void:
    _make_materials()
    if not _load_bounds_contract():
        push_error("AtomiumHeyselDistrictRuntime: DTM bounds contract unavailable")
        return
    if not _build_layers():
        push_error("AtomiumHeyselDistrictRuntime: no bounded district geometry built")
        return
    runtime_loaded = int(last_stats.get("buildings", 0)) > 0 and int(last_stats.get("street_surfaces", 0)) > 0
    if runtime_loaded:
        set_meta("source_crs", EXPECTED_CRS)
        set_meta("source_bbox_epsg31370", [source_bbox_epsg31370.position.x, source_bbox_epsg31370.position.y, source_bbox_epsg31370.end.x, source_bbox_epsg31370.end.y])
        set_meta("compact_payload_used", compact_payload_used)
        print("ATOMIUM_HEYSEL_DISTRICT_READY: compact=%s stats=%s" % [str(compact_payload_used), JSON.stringify(last_stats)])

func _make_materials() -> void:
    _road_material = _material(Color(0.145, 0.15, 0.16, 1.0), 0.96)
    _building_material = _material(Color(0.60, 0.56, 0.51, 1.0), 0.92)
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
    var roads := _read_json(root + "/street_surfaces.game.json")
    var buildings := _read_json(root + "/buildings.game.json")
    var axes := _read_json(root + "/street_axes.game.json")
    var trams := _read_json(root + "/tram_network.game.json")
    var trains := _read_json(root + "/train_network.game.json")

    roads = _bounded_document(roads)
    buildings = _bounded_document(buildings)
    axes = _bounded_document(axes)
    trams = _bounded_document(trams)
    trains = _bounded_document(trains)

    last_stats["street_surfaces"] = _feature_count(roads)
    last_stats["buildings"] = _feature_count(buildings)
    last_stats["street_axes"] = _feature_count(axes)
    last_stats["tram_network"] = _feature_count(trams)
    last_stats["train_network"] = _feature_count(trains)

    _build_polygon_layer(roads, "AtomiumHeyselStreetSurfaces", _road_material, 0.02, false)
    _build_polygon_layer(buildings, "AtomiumHeyselBuildings", _building_material, 0.0, true)
    _build_line_layer(axes, "AtomiumHeyselStreetAxes", _road_material, 0.34, 0.045)
    _build_line_layer(trams, "AtomiumHeyselTramNetwork", _tram_material, 1.0, 0.055)
    _build_line_layer(trains, "AtomiumHeyselTrainNetwork", _rail_material, 1.45, 0.07)
    return int(last_stats["buildings"]) > 0 and int(last_stats["street_surfaces"]) > 0

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
    var points := _geometry_points(geometry as Dictionary)
    for point: Vector2 in points:
        var epsg := _to_epsg31370(point)
        if source_bbox_epsg31370.has_point(epsg):
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

func _append_flat(st: SurfaceTool, points: PackedVector2Array, y: float) -> void:
    for index: int in Geometry2D.triangulate_polygon(points):
        var point := points[index]
        st.set_normal(Vector3.UP)
        st.add_vertex(Vector3(point.x, y, point.y))

func _append_walls(st: SurfaceTool, points: PackedVector2Array, bottom_y: float, top_y: float) -> void:
    for i: int in range(points.size()):
        var a := points[i]
        var b := points[(i + 1) % points.size()]
        var edge := b - a
        if edge.length_squared() < 0.0001:
            continue
        var normal := Vector3(edge.y, 0.0, -edge.x).normalized()
        var a0 := Vector3(a.x, bottom_y, a.y)
        var a1 := Vector3(a.x, top_y, a.y)
        var b0 := Vector3(b.x, bottom_y, b.y)
        var b1 := Vector3(b.x, top_y, b.y)
        for vertex: Vector3 in [a0, b0, b1, a0, b1, a1]:
            st.set_normal(normal)
            st.add_vertex(vertex)

func _building_height(properties: Dictionary) -> float:
    for key: String in ["height", "Height", "HEIGHT", "roof_height", "RoofHeight", "ROOFHEIGHT"]:
        if properties.has(key):
            var value := float(properties[key])
            if value >= 2.5 and value <= 220.0:
                return value
    for key: String in ["floors", "Floors", "FLOORS", "levels", "Levels", "LEVELS"]:
        if properties.has(key):
            var levels := float(properties[key])
            if levels >= 1.0 and levels <= 60.0:
                return levels * 3.15
    return building_default_height_m

func _build_polygon_layer(document: Dictionary, node_name: String, material: Material, y: float, extrude_buildings: bool) -> void:
    var features: Variant = document.get("features", [])
    if not features is Array or features.is_empty():
        return
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for raw: Variant in features:
        if not raw is Dictionary:
            continue
        var feature := raw as Dictionary
        var geometry: Variant = feature.get("geometry", {})
        if not geometry is Dictionary:
            continue
        var properties: Variant = feature.get("properties", {})
        var height := _building_height(properties as Dictionary) if extrude_buildings and properties is Dictionary else building_default_height_m
        for ring: Variant in _outer_rings(geometry as Dictionary):
            if not ring is Array:
                continue
            var points := _ring_points(ring as Array)
            if points.size() < 3:
                continue
            if extrude_buildings:
                _append_flat(st, points, y + height)
                _append_walls(st, points, y, y + height)
            else:
                _append_flat(st, points, y)
    _commit_mesh(st, node_name, material, extrude_buildings and build_collision)

func _build_line_layer(document: Dictionary, node_name: String, material: Material, width: float, y: float) -> void:
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
                _append_line_ribbon(st, raw_line as Array, width, y)
    _commit_mesh(st, node_name, material, false)

func _append_line_ribbon(st: SurfaceTool, line: Array, width: float, y: float) -> void:
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
        var p0 := Vector3(a.x + side.x, y, a.y + side.y)
        var p1 := Vector3(a.x - side.x, y, a.y - side.y)
        var p2 := Vector3(b.x - side.x, y, b.y - side.y)
        var p3 := Vector3(b.x + side.x, y, b.y + side.y)
        for vertex: Vector3 in [p0, p1, p2, p0, p2, p3]:
            st.set_normal(Vector3.UP)
            st.add_vertex(vertex)

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
