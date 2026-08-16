extends SceneTree

const SURFACES_PATH := "res://data/urbis/laeken_jette/street_surfaces.game.json"
const MANIFEST_PATH := "res://data/urbis/laeken_jette/manifest.json"
const ATOMIUM_GAME_XZ := Vector2(224.92615906274295, -6553.143077999353)
const RADII_M := [30.0, 60.0, 100.0, 160.0]

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ATOMIUM_STREET_SURFACE_PROBE_FAIL: %s" % message)
    quit(1)

func _load_dictionary(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    return parsed as Dictionary

func _ring_points(raw_ring: Variant) -> PackedVector2Array:
    var points := PackedVector2Array()
    if not raw_ring is Array:
        return points
    for raw_point: Variant in raw_ring as Array:
        if raw_point is Array and raw_point.size() >= 2:
            points.append(Vector2(float(raw_point[0]), float(raw_point[1])))
    if points.size() >= 2 and points[0].distance_to(points[points.size() - 1]) < 0.001:
        points.resize(points.size() - 1)
    return points

func _outer_rings(geometry: Dictionary) -> Array[PackedVector2Array]:
    var result: Array[PackedVector2Array] = []
    var geometry_type := str(geometry.get("type", ""))
    var coordinates: Variant = geometry.get("coordinates", [])
    if not coordinates is Array:
        return result
    if geometry_type == "Polygon":
        if not coordinates.is_empty():
            var ring := _ring_points(coordinates[0])
            if ring.size() >= 3:
                result.append(ring)
    elif geometry_type == "MultiPolygon":
        for raw_polygon: Variant in coordinates as Array:
            if raw_polygon is Array and not raw_polygon.is_empty():
                var ring := _ring_points(raw_polygon[0])
                if ring.size() >= 3:
                    result.append(ring)
    return result

func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
    var ab := b - a
    var length_squared := ab.length_squared()
    if length_squared <= 0.000001:
        return point.distance_to(a)
    var t := clampf((point - a).dot(ab) / length_squared, 0.0, 1.0)
    return point.distance_to(a + ab * t)

func _distance_to_ring(point: Vector2, ring: PackedVector2Array) -> float:
    if ring.size() < 3:
        return INF
    if Geometry2D.is_point_in_polygon(point, ring):
        return 0.0
    var nearest := INF
    for index: int in range(ring.size()):
        nearest = minf(nearest, _distance_to_segment(point, ring[index], ring[(index + 1) % ring.size()]))
    return nearest

func _run() -> void:
    var manifest := _load_dictionary(MANIFEST_PATH)
    if manifest.is_empty():
        _fail("Laeken/Jette manifest missing or invalid")
        return
    if str(manifest.get("crs", "")) != "EPSG:31370":
        _fail("manifest CRS drifted")
        return

    var layers: Dictionary = manifest.get("layers", {}) as Dictionary
    var surface_layer: Dictionary = layers.get("street_surfaces", {}) as Dictionary
    if int(surface_layer.get("feature_count", 0)) != 959:
        _fail("street-surface manifest count drifted")
        return

    var document := _load_dictionary(SURFACES_PATH)
    if document.is_empty():
        _fail("street-surface game dataset missing or invalid")
        return
    var features: Variant = document.get("features", [])
    if not features is Array or features.size() != 959:
        _fail("street-surface feature count does not match manifest")
        return

    var feature_distances: Array[float] = []
    var polygon_count := 0
    var nearest := INF
    for raw_feature: Variant in features as Array:
        if not raw_feature is Dictionary:
            continue
        var geometry: Variant = (raw_feature as Dictionary).get("geometry", {})
        if not geometry is Dictionary:
            continue
        var feature_nearest := INF
        for ring: PackedVector2Array in _outer_rings(geometry as Dictionary):
            polygon_count += 1
            feature_nearest = minf(feature_nearest, _distance_to_ring(ATOMIUM_GAME_XZ, ring))
        if is_finite(feature_nearest):
            feature_distances.append(feature_nearest)
            nearest = minf(nearest, feature_nearest)

    if polygon_count <= 0 or feature_distances.is_empty() or not is_finite(nearest):
        _fail("no usable official street-surface polygons")
        return

    var counts: Array[int] = []
    for radius: float in RADII_M:
        var count := 0
        for distance: float in feature_distances:
            if distance <= radius:
                count += 1
        counts.append(count)

    if nearest > RADII_M[RADII_M.size() - 1]:
        _fail("nearest official StreetSurface is %.2f m away; immediate Atomium context is not defensible" % nearest)
        return

    print("ATOMIUM_STREET_SURFACE_PROBE_METRICS: nearest=%.3fm polygons=%d r30=%d r60=%d r100=%d r160=%d" % [nearest, polygon_count, counts[0], counts[1], counts[2], counts[3]])
    print("ATOMIUM_STREET_SURFACE_PROBE_OK: source=INSPIRE_STREET_SURFACE features=%d crs=EPSG:31370" % features.size())
    quit(0)
