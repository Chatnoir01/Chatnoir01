extends SceneTree

const BUILDINGS_PATH := "res://data/urbis/laeken_jette/buildings.game.json"
const PALAIS5_OUTLINE_PATH := "res://data/sources/laeken_jette/palais5_osm_outline.game.json"
const PALAIS5_EXPO_INSPIRE_ID := "https://databrussels.be/id/building/1635598"
const ROOF_Y_EPSILON := 0.001
const OVERLAP_AREA_EPSILON_M2 := 0.0001


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("LAEKEN_SOURCE_TOPOLOGY_FAIL: %s" % message)
    quit(1)


func _load_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed = JSON.parse_string(file.get_as_text())
    return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}


func _ring_to_points(ring: Array) -> PackedVector2Array:
    var points := PackedVector2Array()
    for raw in ring:
        if raw is Array and raw.size() >= 2:
            points.append(Vector2(float(raw[0]), float(raw[1])))
    if points.size() >= 2 and points[0].distance_to(points[points.size() - 1]) < 0.001:
        points.resize(points.size() - 1)
    return points


func _polygon_area(points: PackedVector2Array) -> float:
    if points.size() < 3:
        return 0.0
    var twice_area := 0.0
    for index in range(points.size()):
        var a := points[index]
        var b := points[(index + 1) % points.size()]
        twice_area += a.x * b.y - b.x * a.y
    return absf(twice_area) * 0.5


func _polygon_bounds(points: PackedVector2Array) -> Rect2:
    if points.is_empty():
        return Rect2()
    var min_point := points[0]
    var max_point := points[0]
    for point in points:
        min_point.x = minf(min_point.x, point.x)
        min_point.y = minf(min_point.y, point.y)
        max_point.x = maxf(max_point.x, point.x)
        max_point.y = maxf(max_point.y, point.y)
    return Rect2(min_point, max_point - min_point)


func _intersection_area(a: PackedVector2Array, b: PackedVector2Array) -> float:
    var total := 0.0
    for polygon in Geometry2D.intersect_polygons(a, b):
        if polygon is PackedVector2Array:
            total += _polygon_area(polygon)
    return total


func _load_expo_geometry() -> Dictionary:
    var buildings := _load_json(BUILDINGS_PATH)
    var features = buildings.get("features", [])
    if not (features is Array):
        return {}
    for feature in features:
        if not (feature is Dictionary):
            continue
        var properties = feature.get("properties", {})
        if not (properties is Dictionary) or str(properties.get("INSPIRE_ID", "")) != PALAIS5_EXPO_INSPIRE_ID:
            continue
        var geometry = feature.get("geometry", {})
        if not (geometry is Dictionary):
            return {}
        var coordinates = geometry.get("coordinates", [])
        var polygon: Array = []
        if str(geometry.get("type", "")) == "Polygon" and coordinates is Array and not coordinates.is_empty():
            polygon = coordinates
        elif str(geometry.get("type", "")) == "MultiPolygon" and coordinates is Array and coordinates.size() == 1 and coordinates[0] is Array:
            polygon = coordinates[0]
        if polygon.is_empty():
            return {}
        var holes: Array[PackedVector2Array] = []
        for ring_index in range(1, polygon.size()):
            var hole := _ring_to_points(polygon[ring_index])
            if hole.size() >= 3:
                holes.append(hole)
        return {"outer": _ring_to_points(polygon[0]), "holes": holes}
    return {}


func _load_palais5_outline() -> PackedVector2Array:
    var document := _load_json(PALAIS5_OUTLINE_PATH)
    var geometry = document.get("geometry", {})
    if not (geometry is Dictionary):
        return PackedVector2Array()
    var coordinates = geometry.get("coordinates", [])
    if str(geometry.get("type", "")) != "Polygon" or not (coordinates is Array) or coordinates.is_empty():
        return PackedVector2Array()
    return _ring_to_points(coordinates[0])


func _verify(mesh: Mesh) -> Dictionary:
    var expo := _load_expo_geometry()
    if expo.is_empty():
        return {"error": "Expo source aggregate missing"}
    var outer: PackedVector2Array = expo["outer"]
    var holes: Array[PackedVector2Array] = expo["holes"].duplicate()
    var palais5 := _load_palais5_outline()
    if outer.size() < 3 or holes.size() < 14 or palais5.size() < 3:
        return {"error": "invalid source geometry outer=%d holes=%d palais5=%d" % [outer.size(), holes.size(), palais5.size()]}
    holes.append(palais5)

    var hole_bounds: Array[Rect2] = []
    for hole in holes:
        hole_bounds.append(_polygon_bounds(hole))
    var expo_bounds := _polygon_bounds(outer)

    var arrays := mesh.surface_get_arrays(0)
    if arrays.is_empty():
        return {"error": "OfficialBuildings mesh arrays missing"}
    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    if vertices.size() < 3 or vertices.size() % 3 != 0:
        return {"error": "unexpected source triangle array size=%d" % vertices.size()}

    var expo_roof_triangles := 0
    var survivor_area_m2 := 0.0
    var forbidden_overlap_triangles := 0
    var max_overlap_m2 := 0.0

    for offset in range(0, vertices.size(), 3):
        var a := vertices[offset]
        var b := vertices[offset + 1]
        var c := vertices[offset + 2]
        if absf(a.y - b.y) > ROOF_Y_EPSILON or absf(a.y - c.y) > ROOF_Y_EPSILON:
            continue
        var triangle := PackedVector2Array([Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)])
        var triangle_bounds := _polygon_bounds(triangle)
        if not expo_bounds.intersects(triangle_bounds, true):
            continue
        var centroid := (triangle[0] + triangle[1] + triangle[2]) / 3.0
        if not Geometry2D.is_point_in_polygon(centroid, outer):
            continue
        expo_roof_triangles += 1
        var blocked := 0.0
        for index in range(holes.size()):
            if hole_bounds[index].intersects(triangle_bounds, true):
                blocked += _intersection_area(triangle, holes[index])
        if blocked > OVERLAP_AREA_EPSILON_M2:
            forbidden_overlap_triangles += 1
            max_overlap_m2 = maxf(max_overlap_m2, blocked)
        else:
            survivor_area_m2 += _polygon_area(triangle)

    if forbidden_overlap_triangles > 0:
        return {
            "error": "source roof geometry fills an official void/cutout: triangles=%d max_overlap=%.6fm2" % [forbidden_overlap_triangles, max_overlap_m2],
            "expo_roof_triangles": expo_roof_triangles,
            "survivor_area_m2": survivor_area_m2,
            "forbidden_overlap_triangles": forbidden_overlap_triangles,
            "max_overlap_m2": max_overlap_m2,
        }
    if expo_roof_triangles < 50 or survivor_area_m2 < 10000.0:
        return {"error": "Expo source aggregate missing/over-cut roofs=%d survivor=%.2fm2" % [expo_roof_triangles, survivor_area_m2]}
    return {
        "expo_roof_triangles": expo_roof_triangles,
        "survivor_area_m2": survivor_area_m2,
        "forbidden_overlap_triangles": forbidden_overlap_triangles,
        "max_overlap_m2": max_overlap_m2,
        "official_holes": holes.size() - 1,
    }


func _run() -> void:
    var packed := load("res://game/zones/laeken_jette/laeken_jette.tscn") as PackedScene
    if packed == null:
        _fail("Laeken/Jette scene failed to load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    await process_frame

    var source_mesh := scene.get_node_or_null("OfficialBuildings") as MeshInstance3D
    if source_mesh == null or source_mesh.mesh == null or source_mesh.mesh.get_surface_count() == 0:
        _fail("OfficialBuildings source mesh missing")
        return
    var proof := _verify(source_mesh.mesh)
    if proof.has("error"):
        _fail(str(proof["error"]))
        return
    print("LAEKEN_SOURCE_TOPOLOGY_OK: expo_roofs=%d survivor_area=%.2fm2 forbidden_overlap=%d official_holes=%d" % [
        int(proof["expo_roof_triangles"]),
        float(proof["survivor_area_m2"]),
        int(proof["forbidden_overlap_triangles"]),
        int(proof["official_holes"]),
    ])
    scene.queue_free()
    await process_frame
    quit(0)
