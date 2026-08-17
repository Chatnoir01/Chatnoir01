extends Node3D

## Jette phase 2: exact UrbIS road/building/rail network around Miroir,
## Jette station and Parc Roi Baudouin. This scene is intentionally standalone.

const DATA_ROOT := "res://data/urbis/laeken_jette/jette_phase2"
const OSM_ENVIRONMENT_RUNTIME := preload("res://game/scripts/brussels_osm_environment_runtime.gd")
const OSM_ENVIRONMENT_DATA := "res://data/osm/zones/jette/environment.game.json"
const JETTE_STATION_XZ := Vector2(-687.700268506218, -4952.774160383269)
const MIROIR_XZ := Vector2(-977.468223091797, -4051.878040528856)
const ROI_BAUDOUIN_XZ := Vector2(-1357.8384465064446, -5020.906404124573)

@export var building_default_height_m := 10.5
@export var station_height_m := 9.0
@export var ground_y := 0.0

var last_stats: Dictionary = {
    "buildings": 0,
    "street_surfaces": 0,
    "street_axes": 0,
    "tram_network": 0,
    "train_network": 0,
}
var station_feature_distance_m := INF

var _ground_material: StandardMaterial3D
var _road_material: StandardMaterial3D
var _building_material: StandardMaterial3D
var _station_brick: StandardMaterial3D
var _station_stone: StandardMaterial3D
var _rail_material: StandardMaterial3D
var _tram_material: StandardMaterial3D


func _ready() -> void:
    _make_materials()
    _build_ground_reference()
    _build_official_geometry()
    _build_osm_environment()
    print("JETTE_PHASE2_ZONE_READY: %s station_feature_distance=%.2f" % [JSON.stringify(last_stats), station_feature_distance_m])


func _build_osm_environment() -> void:
    var runtime := OSM_ENVIRONMENT_RUNTIME.new()
    runtime.name = "BrusselsOsmEnvironment"
    runtime.data_path = OSM_ENVIRONMENT_DATA
    add_child(runtime)


func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    return material


func _make_materials() -> void:
    _ground_material = _material(Color(0.19, 0.23, 0.18, 1.0), 0.98)
    _road_material = _material(Color(0.145, 0.15, 0.16, 1.0), 0.96)
    _building_material = _material(Color(0.60, 0.56, 0.51, 1.0), 0.92)
    # Jette station reference photography and heritage inventory show the
    # characteristic red-brick body with pale stone bands/details.
    _station_brick = _material(Color(0.58, 0.22, 0.11, 1.0), 0.91)
    _station_stone = _material(Color(0.72, 0.70, 0.64, 1.0), 0.90)
    _rail_material = _material(Color(0.16, 0.17, 0.18, 1.0), 0.42, 0.54)
    _tram_material = _material(Color(0.27, 0.27, 0.27, 1.0), 0.55, 0.30)


func _build_ground_reference() -> void:
    # EPSG:31370 bbox 144900,173000 -> 147700,175300 converted with the
    # project origin. Geometry on top still comes from UrbIS, not this plane.
    var mesh := PlaneMesh.new()
    mesh.size = Vector2(2800.0, 2300.0)
    mesh.material = _ground_material
    var instance := MeshInstance3D.new()
    instance.name = "JettePhase2ReferenceGround"
    instance.mesh = mesh
    instance.position = Vector3(-1568.29422791934, ground_y - 0.04, -4611.37585073803)
    add_child(instance)

    var body := StaticBody3D.new()
    body.name = "JettePhase2ReferenceGroundCollision"
    var collision := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(2800.0, 0.2, 2300.0)
    collision.shape = box
    body.position = instance.position + Vector3(0.0, -0.1, 0.0)
    body.add_child(collision)
    add_child(body)


func _load_collection(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        push_warning("Jette phase 2 layer missing: %s" % path)
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_warning("Unable to open Jette phase 2 layer: %s" % path)
        return {}
    var parsed = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        push_warning("Invalid Jette phase 2 JSON: %s" % path)
        return {}
    return parsed as Dictionary


func _build_official_geometry() -> void:
    var roads := _load_collection(DATA_ROOT + "/street_surfaces.game.json")
    var buildings := _load_collection(DATA_ROOT + "/buildings.game.json")
    var axes := _load_collection(DATA_ROOT + "/street_axes.game.json")
    var trams := _load_collection(DATA_ROOT + "/tram_network.game.json")
    var trains := _load_collection(DATA_ROOT + "/train_network.game.json")

    last_stats["street_surfaces"] = _feature_count(roads)
    last_stats["buildings"] = _feature_count(buildings)
    last_stats["street_axes"] = _feature_count(axes)
    last_stats["tram_network"] = _feature_count(trams)
    last_stats["train_network"] = _feature_count(trains)

    _build_polygon_layer(roads, "JetteOfficialStreetSurfaces", _road_material, ground_y + 0.02)
    _build_buildings(buildings)
    _build_line_layer(trams, "JetteOfficialTramNetwork", _tram_material, 1.0, ground_y + 0.055)
    _build_line_layer(trains, "JetteOfficialTrainNetwork", _rail_material, 1.45, ground_y + 0.07)


func _feature_count(document: Dictionary) -> int:
    var features = document.get("features", [])
    return features.size() if features is Array else 0


func _outer_rings(geometry: Dictionary) -> Array:
    var result: Array = []
    var kind := String(geometry.get("type", ""))
    var coords = geometry.get("coordinates", [])
    if kind == "Polygon" and coords is Array and not coords.is_empty():
        result.append(coords[0])
    elif kind == "MultiPolygon" and coords is Array:
        for polygon in coords:
            if polygon is Array and not polygon.is_empty():
                result.append(polygon[0])
    return result


func _line_strings(geometry: Dictionary) -> Array:
    var result: Array = []
    var kind := String(geometry.get("type", ""))
    var coords = geometry.get("coordinates", [])
    if kind == "LineString" and coords is Array:
        result.append(coords)
    elif kind == "MultiLineString" and coords is Array:
        for line in coords:
            if line is Array:
                result.append(line)
    return result


func _ring_points(ring: Array) -> PackedVector2Array:
    var points := PackedVector2Array()
    for raw in ring:
        if raw is Array and raw.size() >= 2:
            points.append(Vector2(float(raw[0]), float(raw[1])))
    if points.size() >= 2 and points[0].distance_to(points[points.size() - 1]) < 0.001:
        points.resize(points.size() - 1)
    return points


func _centroid(points: PackedVector2Array) -> Vector2:
    var sum := Vector2.ZERO
    if points.is_empty():
        return sum
    for point in points:
        sum += point
    return sum / float(points.size())


func _append_flat(st: SurfaceTool, points: PackedVector2Array, y: float) -> void:
    var triangles := Geometry2D.triangulate_polygon(points)
    for index in triangles:
        var point := points[int(index)]
        st.set_normal(Vector3.UP)
        st.add_vertex(Vector3(point.x, y, point.y))


func _append_walls(st: SurfaceTool, points: PackedVector2Array, bottom_y: float, top_y: float) -> void:
    for i in range(points.size()):
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
        for vertex in [a0, b0, b1, a0, b1, a1]:
            st.set_normal(normal)
            st.add_vertex(vertex)


func _build_polygon_layer(document: Dictionary, node_name: String, material: Material, y: float) -> void:
    var features = document.get("features", [])
    if not (features is Array) or features.is_empty():
        return
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for feature in features:
        if not (feature is Dictionary):
            continue
        var geometry = feature.get("geometry", {})
        if not (geometry is Dictionary):
            continue
        for ring in _outer_rings(geometry):
            var points := _ring_points(ring)
            if points.size() >= 3:
                _append_flat(st, points, y)
    var mesh := st.commit()
    if mesh == null or mesh.get_surface_count() == 0:
        return
    mesh.surface_set_material(0, material)
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    add_child(instance)


func _building_height(properties: Dictionary) -> float:
    for key in ["height", "Height", "HEIGHT", "roof_height", "RoofHeight", "ROOFHEIGHT"]:
        if properties.has(key):
            var value := float(properties[key])
            if value >= 2.5 and value <= 220.0:
                return value
    for key in ["floors", "Floors", "FLOORS", "levels", "Levels", "LEVELS"]:
        if properties.has(key):
            var levels := float(properties[key])
            if levels >= 1.0 and levels <= 60.0:
                return levels * 3.15
    return building_default_height_m


func _find_station_feature_index(features: Array) -> int:
    var best_index := -1
    var best_distance := INF
    for index in range(features.size()):
        var feature = features[index]
        if not (feature is Dictionary):
            continue
        var geometry = feature.get("geometry", {})
        if not (geometry is Dictionary):
            continue
        var rings := _outer_rings(geometry)
        if rings.is_empty():
            continue
        var points := _ring_points(rings[0])
        if points.size() < 3:
            continue
        var distance := _centroid(points).distance_to(JETTE_STATION_XZ)
        if distance < best_distance:
            best_distance = distance
            best_index = index
    station_feature_distance_m = best_distance
    return best_index


func _build_buildings(document: Dictionary) -> void:
    var features = document.get("features", [])
    if not (features is Array) or features.is_empty():
        return
    var station_index := _find_station_feature_index(features)
    var generic_st := SurfaceTool.new()
    var station_st := SurfaceTool.new()
    generic_st.begin(Mesh.PRIMITIVE_TRIANGLES)
    station_st.begin(Mesh.PRIMITIVE_TRIANGLES)

    for index in range(features.size()):
        var feature = features[index]
        if not (feature is Dictionary):
            continue
        var geometry = feature.get("geometry", {})
        if not (geometry is Dictionary):
            continue
        var properties = feature.get("properties", {})
        if not (properties is Dictionary):
            properties = {}
        var height := station_height_m if index == station_index else _building_height(properties)
        var target := station_st if index == station_index else generic_st
        for ring in _outer_rings(geometry):
            var points := _ring_points(ring)
            if points.size() < 3:
                continue
            _append_flat(target, points, ground_y + height)
            _append_walls(target, points, ground_y, ground_y + height)

    _commit_mesh(generic_st, "JetteOfficialBuildings", _building_material)
    _commit_mesh(station_st, "JetteStationOfficialFootprintHero", _station_brick)

    # A thin pale stone datum follows the exact selected station footprint by
    # reusing it at low height; this is a source-informed facade cue, not a new footprint.
    if station_index >= 0:
        var feature = features[station_index]
        var geometry = feature.get("geometry", {})
        var band_st := SurfaceTool.new()
        band_st.begin(Mesh.PRIMITIVE_TRIANGLES)
        if geometry is Dictionary:
            for ring in _outer_rings(geometry):
                var points := _ring_points(ring)
                if points.size() >= 3:
                    _append_walls(band_st, points, 2.55, 2.85)
        _commit_mesh(band_st, "JetteStationStoneBand", _station_stone)


func _commit_mesh(st: SurfaceTool, node_name: String, material: Material) -> void:
    var mesh := st.commit()
    if mesh == null or mesh.get_surface_count() == 0:
        return
    mesh.surface_set_material(0, material)
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    add_child(instance)


func _build_line_layer(document: Dictionary, node_name: String, material: Material, width: float, y: float) -> void:
    var features = document.get("features", [])
    if not (features is Array) or features.is_empty():
        return
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for feature in features:
        if not (feature is Dictionary):
            continue
        var geometry = feature.get("geometry", {})
        if not (geometry is Dictionary):
            continue
        for line in _line_strings(geometry):
            _append_line_ribbon(st, line, width, y)
    _commit_mesh(st, node_name, material)


func _append_line_ribbon(st: SurfaceTool, line: Array, width: float, y: float) -> void:
    if line.size() < 2:
        return
    for i in range(line.size() - 1):
        var raw_a = line[i]
        var raw_b = line[i + 1]
        if not (raw_a is Array and raw_b is Array and raw_a.size() >= 2 and raw_b.size() >= 2):
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
        for vertex in [p0, p1, p2, p0, p2, p3]:
            st.set_normal(Vector3.UP)
            st.add_vertex(vertex)
