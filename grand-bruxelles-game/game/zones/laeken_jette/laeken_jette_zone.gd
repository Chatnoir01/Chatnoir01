extends Node3D

## Laeken + Jette isolated zone builder.
## Phase 1 consumes only the clipped official UrbIS Bockstael/Heysel/Atomium slice.
## It intentionally does not touch main.tscn or the global player/vehicle systems.
## Polygon topology is preserved: UrbIS interior rings stay empty, and the sourced
## Palais 5 outline replaces only its matching volume inside the monolithic Expo feature.

const DATA_ROOT := "res://data/urbis/laeken_jette"
const PALAIS5_OUTLINE_PATH := "res://data/sources/laeken_jette/palais5_osm_outline.game.json"
const PALAIS5_EXPO_INSPIRE_ID := "https://databrussels.be/id/building/1635598"
const ATOMIUM_GAME_XZ := Vector2(224.92615906274295, -6553.143077999353)
const ATOMIUM_TOTAL_HEIGHT_M := 102.0
const ATOMIUM_SPHERE_DIAMETER_M := 18.0
const ATOMIUM_TUBE_DIAMETER_M := 3.3

@export var load_urbis_geometry := true
@export var build_atomium_hero := true
@export var building_default_height_m := 10.5
@export var rail_width_m := 1.45
@export var tram_width_m := 1.0
@export var ground_y := 0.0

var last_stats: Dictionary = {
    "buildings": 0,
    "street_surfaces": 0,
    "street_axes": 0,
    "tram_network": 0,
    "train_network": 0,
    "official_polygon_holes": 0,
    "palais5_source_cutouts": 0,
}

var _road_material: StandardMaterial3D
var _building_material: StandardMaterial3D
var _rail_material: StandardMaterial3D
var _tram_material: StandardMaterial3D
var _ground_material: StandardMaterial3D
var _atomium_material: StandardMaterial3D
var _atomium_dark_material: StandardMaterial3D
var _palais5_cutout := PackedVector2Array()


func _ready() -> void:
    _make_materials()
    _build_ground_reference()
    if load_urbis_geometry:
        _load_palais5_cutout()
        _build_urbis_slice()
    if build_atomium_hero:
        _build_atomium()
    print("LAEKEN_JETTE_ZONE_READY: %s" % JSON.stringify(last_stats))


func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    return material


func _make_materials() -> void:
    _road_material = _material(Color(0.145, 0.155, 0.165, 1.0), 0.96)
    _building_material = _material(Color(0.62, 0.57, 0.50, 1.0), 0.92)
    _rail_material = _material(Color(0.18, 0.19, 0.20, 1.0), 0.46, 0.48)
    _tram_material = _material(Color(0.27, 0.27, 0.26, 1.0), 0.58, 0.30)
    _ground_material = _material(Color(0.20, 0.24, 0.18, 1.0), 0.98)
    _atomium_material = _material(Color(0.68, 0.72, 0.74, 1.0), 0.22, 0.82)
    _atomium_dark_material = _material(Color(0.16, 0.18, 0.19, 1.0), 0.36, 0.66)


func _build_ground_reference() -> void:
    var mesh := PlaneMesh.new()
    mesh.size = Vector2(1800.0, 3100.0)
    mesh.material = _ground_material
    var instance := MeshInstance3D.new()
    instance.name = "Phase1ReferenceGround"
    instance.mesh = mesh
    instance.position = Vector3(631.70577208066, ground_y - 0.04, -5661.37585073803)
    add_child(instance)

    var body := StaticBody3D.new()
    body.name = "Phase1ReferenceGroundCollision"
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(1800.0, 0.2, 3100.0)
    shape.shape = box
    body.position = instance.position + Vector3(0.0, -0.1, 0.0)
    body.add_child(shape)
    add_child(body)


func _load_collection(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        push_warning("Laeken/Jette source layer missing: %s" % path)
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_warning("Unable to open Laeken/Jette source layer: %s" % path)
        return {}
    var parsed = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        push_warning("Invalid GeoJSON/JSON document: %s" % path)
        return {}
    return parsed as Dictionary


func _build_urbis_slice() -> void:
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

    _build_polygon_layer(roads, "OfficialStreetSurfaces", _road_material, ground_y + 0.02, false)
    _build_buildings(buildings)
    _build_line_layer(trams, "OfficialTramNetwork", _tram_material, tram_width_m, ground_y + 0.055)
    _build_line_layer(trains, "OfficialTrainNetwork", _rail_material, rail_width_m, ground_y + 0.07)


func _feature_count(document: Dictionary) -> int:
    var features = document.get("features", [])
    return features.size() if features is Array else 0


func _polygon_ring_sets(geometry: Dictionary) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    var kind := str(geometry.get("type", ""))
    var coords = geometry.get("coordinates", [])
    var polygons: Array = []
    if kind == "Polygon" and coords is Array:
        polygons.append(coords)
    elif kind == "MultiPolygon" and coords is Array:
        polygons = coords
    for polygon in polygons:
        if not (polygon is Array) or polygon.is_empty():
            continue
        var outer := _ring_to_points(polygon[0])
        if outer.size() < 3:
            continue
        var holes: Array[PackedVector2Array] = []
        for ring_index in range(1, polygon.size()):
            var hole := _ring_to_points(polygon[ring_index])
            if hole.size() >= 3:
                holes.append(hole)
        result.append({"outer": outer, "holes": holes})
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


func _ring_to_points(ring: Array) -> PackedVector2Array:
    var points := PackedVector2Array()
    for raw in ring:
        if raw is Array and raw.size() >= 2:
            points.append(Vector2(float(raw[0]), float(raw[1])))
    if points.size() >= 2 and points[0].distance_to(points[points.size() - 1]) < 0.001:
        points.resize(points.size() - 1)
    return points


func _polygon_centroid(points: PackedVector2Array) -> Vector2:
    if points.is_empty():
        return Vector2.ZERO
    var total := Vector2.ZERO
    for point in points:
        total += point
    return total / float(points.size())


func _point_in_surface(point: Vector2, outer: PackedVector2Array, holes: Array[PackedVector2Array]) -> bool:
    if not Geometry2D.is_point_in_polygon(point, outer):
        return false
    for hole in holes:
        if Geometry2D.is_point_in_polygon(point, hole):
            return false
    return true


func _append_flat_polygon(st: SurfaceTool, points: PackedVector2Array, y: float) -> int:
    var triangles := Geometry2D.triangulate_polygon(points)
    for index in triangles:
        var p := points[int(index)]
        st.set_normal(Vector3.UP)
        st.add_vertex(Vector3(p.x, y, p.y))
    return triangles.size() / 3


func _append_flat_polygon_with_holes(st: SurfaceTool, outer: PackedVector2Array, holes: Array[PackedVector2Array], y: float) -> int:
    if holes.is_empty():
        return _append_flat_polygon(st, outer, y)
    var vertices := PackedVector2Array()
    vertices.append_array(outer)
    for hole in holes:
        vertices.append_array(hole)
    var triangles := Geometry2D.triangulate_delaunay(vertices)
    var accepted := 0
    for offset in range(0, triangles.size(), 3):
        if offset + 2 >= triangles.size():
            break
        var a := vertices[int(triangles[offset])]
        var b := vertices[int(triangles[offset + 1])]
        var c := vertices[int(triangles[offset + 2])]
        var centroid := (a + b + c) / 3.0
        if not _point_in_surface(centroid, outer, holes):
            continue
        if not _point_in_surface((a + b) * 0.5, outer, holes):
            continue
        if not _point_in_surface((b + c) * 0.5, outer, holes):
            continue
        if not _point_in_surface((c + a) * 0.5, outer, holes):
            continue
        for point in [a, b, c]:
            st.set_normal(Vector3.UP)
            st.add_vertex(Vector3(point.x, y, point.y))
        accepted += 1
    return accepted


func _append_walls(st: SurfaceTool, points: PackedVector2Array, bottom_y: float, top_y: float, reverse_normal: bool = false) -> void:
    for i in range(points.size()):
        var a := points[i]
        var b := points[(i + 1) % points.size()]
        var edge := b - a
        if edge.length_squared() < 0.0001:
            continue
        var normal := Vector3(edge.y, 0.0, -edge.x).normalized()
        if reverse_normal:
            normal = -normal
        var a0 := Vector3(a.x, bottom_y, a.y)
        var a1 := Vector3(a.x, top_y, a.y)
        var b0 := Vector3(b.x, bottom_y, b.y)
        var b1 := Vector3(b.x, top_y, b.y)
        for vertex in [a0, b0, b1, a0, b1, a1]:
            st.set_normal(normal)
            st.add_vertex(vertex)


func _load_palais5_cutout() -> void:
    _palais5_cutout = PackedVector2Array()
    var document := _load_collection(PALAIS5_OUTLINE_PATH)
    var geometry = document.get("geometry", {})
    if not (geometry is Dictionary):
        return
    var sets := _polygon_ring_sets(geometry)
    if sets.size() == 1:
        _palais5_cutout = sets[0]["outer"]


func _build_polygon_layer(document: Dictionary, node_name: String, material: Material, y: float, vertical_walls: bool) -> void:
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
        for polygon_set in _polygon_ring_sets(geometry):
            var outer: PackedVector2Array = polygon_set["outer"]
            var holes: Array[PackedVector2Array] = polygon_set["holes"]
            last_stats["official_polygon_holes"] = int(last_stats["official_polygon_holes"]) + holes.size()
            _append_flat_polygon_with_holes(st, outer, holes, y)
            if vertical_walls:
                _append_walls(st, outer, ground_y, y)
                for hole in holes:
                    _append_walls(st, hole, ground_y, y, true)
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
            var candidate := float(properties[key])
            if candidate >= 2.5 and candidate <= 220.0:
                return candidate
    for key in ["floors", "Floors", "FLOORS", "levels", "Levels", "LEVELS"]:
        if properties.has(key):
            var levels := float(properties[key])
            if levels >= 1.0 and levels <= 60.0:
                return levels * 3.15
    return building_default_height_m


func _build_buildings(document: Dictionary) -> void:
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
        var properties = feature.get("properties", {})
        if not (properties is Dictionary):
            properties = {}
        var height := _building_height(properties)
        var inspire_id := str(properties.get("INSPIRE_ID", ""))
        for polygon_set in _polygon_ring_sets(geometry):
            var outer: PackedVector2Array = polygon_set["outer"]
            var holes: Array[PackedVector2Array] = polygon_set["holes"].duplicate()
            last_stats["official_polygon_holes"] = int(last_stats["official_polygon_holes"]) + holes.size()
            if inspire_id == PALAIS5_EXPO_INSPIRE_ID and _palais5_cutout.size() >= 3:
                if Geometry2D.is_point_in_polygon(_polygon_centroid(_palais5_cutout), outer):
                    holes.append(_palais5_cutout)
                    last_stats["palais5_source_cutouts"] = int(last_stats["palais5_source_cutouts"]) + 1
            _append_flat_polygon_with_holes(st, outer, holes, ground_y + height)
            _append_walls(st, outer, ground_y, ground_y + height)
            for hole in holes:
                _append_walls(st, hole, ground_y, ground_y + height, true)
    var mesh := st.commit()
    if mesh == null or mesh.get_surface_count() == 0:
        return
    mesh.surface_set_material(0, _building_material)
    var instance := MeshInstance3D.new()
    instance.name = "OfficialBuildings"
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
    var mesh := st.commit()
    if mesh == null or mesh.get_surface_count() == 0:
        return
    mesh.surface_set_material(0, material)
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    add_child(instance)


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


func _build_atomium() -> void:
    var root := Node3D.new()
    root.name = "AtomiumHero"
    root.position = Vector3(ATOMIUM_GAME_XZ.x, ground_y, ATOMIUM_GAME_XZ.y)
    add_child(root)

    var sphere_centres: Array[Vector3] = [
        Vector3(0.0, 9.0, 0.0),
        Vector3(-34.293, 37.0, 19.799),
        Vector3(0.0, 37.0, -39.598),
        Vector3(34.293, 37.0, 19.799),
        Vector3(-34.293, 65.0, -19.799),
        Vector3(0.0, 65.0, 39.598),
        Vector3(34.293, 65.0, -19.799),
        Vector3(0.0, 93.0, 0.0),
        Vector3(0.0, 51.0, 0.0),
    ]

    for i in range(8):
        _add_atomium_sphere(root, "Sphere_%02d" % i, sphere_centres[i])
    _add_atomium_sphere(root, "Sphere_Centre", sphere_centres[8])

    var cube_edges: Array[Vector2i] = [
        Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3),
        Vector2i(1, 4), Vector2i(1, 5),
        Vector2i(2, 4), Vector2i(2, 6),
        Vector2i(3, 5), Vector2i(3, 6),
        Vector2i(4, 7), Vector2i(5, 7), Vector2i(6, 7),
    ]
    for edge in cube_edges:
        _add_atomium_tube(root, sphere_centres[edge.x], sphere_centres[edge.y], ATOMIUM_TUBE_DIAMETER_M)
    for i in range(8):
        _add_atomium_tube(root, sphere_centres[i], sphere_centres[8], ATOMIUM_TUBE_DIAMETER_M)

    for i in [1, 2, 3]:
        var centre := sphere_centres[i]
        _add_atomium_tube(root, Vector3(centre.x - 8.0, 0.0, centre.z - 5.0), centre, 2.4, _atomium_dark_material)
        _add_atomium_tube(root, Vector3(centre.x + 8.0, 0.0, centre.z + 5.0), centre, 2.4, _atomium_dark_material)

    var base := CylinderMesh.new()
    base.top_radius = 13.0
    base.bottom_radius = 13.0
    base.height = 2.4
    base.radial_segments = 48
    base.material = _atomium_dark_material
    var base_instance := MeshInstance3D.new()
    base_instance.name = "BasePavilion26m"
    base_instance.mesh = base
    base_instance.position = Vector3(0.0, 1.2, 0.0)
    root.add_child(base_instance)


func _add_atomium_sphere(parent: Node3D, node_name: String, position: Vector3) -> void:
    var sphere := SphereMesh.new()
    sphere.radius = ATOMIUM_SPHERE_DIAMETER_M * 0.5
    sphere.height = ATOMIUM_SPHERE_DIAMETER_M
    sphere.radial_segments = 24
    sphere.rings = 12
    sphere.material = _atomium_material
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = sphere
    instance.position = position
    parent.add_child(instance)


func _add_atomium_tube(parent: Node3D, a: Vector3, b: Vector3, diameter: float, material: Material = null) -> void:
    var delta := b - a
    var length := delta.length()
    if length < 0.01:
        return
    var cylinder := CylinderMesh.new()
    cylinder.top_radius = diameter * 0.5
    cylinder.bottom_radius = diameter * 0.5
    cylinder.height = length
    cylinder.radial_segments = 16
    cylinder.material = material if material != null else _atomium_material
    var instance := MeshInstance3D.new()
    instance.name = "Tube"
    instance.mesh = cylinder
    instance.position = (a + b) * 0.5
    instance.quaternion = Quaternion(Vector3.UP, delta.normalized())
    parent.add_child(instance)
