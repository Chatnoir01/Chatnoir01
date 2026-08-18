extends SceneTree

const SURFACES_PATH := "res://data/urbis/laeken_jette/street_surfaces.game.json"
const MANIFEST_PATH := "res://data/urbis/laeken_jette/manifest.json"
const LANDCOVER_PATH := "res://data/environment/laeken_jette/atomium_landcover_context.game.json"

const ATOMIUM_ANCHOR := Vector2(224.92615906274295, -6553.143077999353)
const PLAYER_SPAWN := Vector2(344.92615906274295, -6553.143077999353)
const RADII_M := [30.0, 60.0, 100.0, 160.0]
const ARRIVAL_CORRIDOR_HALF_WIDTH_M := 30.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ATOMIUM_STREET_SURFACE_ARRIVAL_PROBE_FAIL: %s" % message)
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

func _segment_to_ring_distance(a: Vector2, b: Vector2, ring: PackedVector2Array) -> float:
    if ring.size() < 3:
        return INF
    if Geometry2D.is_point_in_polygon(a, ring) or Geometry2D.is_point_in_polygon(b, ring):
        return 0.0
    var nearest := INF
    for index: int in range(ring.size()):
        var c := ring[index]
        var d := ring[(index + 1) % ring.size()]
        if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
            return 0.0
        nearest = minf(nearest, _distance_to_segment(c, a, b))
        nearest = minf(nearest, _distance_to_segment(d, a, b))
        nearest = minf(nearest, _distance_to_segment(a, c, d))
        nearest = minf(nearest, _distance_to_segment(b, c, d))
    return nearest

func _ring_area(ring: PackedVector2Array) -> float:
    if ring.size() < 3:
        return 0.0
    var twice_area := 0.0
    for index: int in range(ring.size()):
        var a := ring[index]
        var b := ring[(index + 1) % ring.size()]
        twice_area += a.x * b.y - b.x * a.y
    return absf(twice_area) * 0.5

func _run() -> void:
    var manifest := _load_dictionary(MANIFEST_PATH)
    if manifest.is_empty():
        _fail("Laeken/Jette manifest missing or invalid")
        return
    if str(manifest.get("source_crs", "")) != "EPSG:31370":
        _fail("manifest source_crs drifted")
        return
    if str(manifest.get("source", "")) != "Paradigm / Brussels-Capital Region UrbIS vector WFS":
        _fail("UrbIS source identity drifted")
        return

    var layers: Dictionary = manifest.get("layers", {}) as Dictionary
    var surface_layer: Dictionary = layers.get("street_surfaces", {}) as Dictionary
    var expected_features := int(surface_layer.get("features", 0))
    if expected_features != 3572:
        _fail("street-surface manifest count drifted: %d" % expected_features)
        return
    if str(surface_layer.get("type_name", "")) != "urbisvector:StreetSurfaces":
        _fail("street-surface source class drifted")
        return

    var landcover := _load_dictionary(LANDCOVER_PATH)
    if landcover.is_empty():
        _fail("production Atomium LandCover contract missing")
        return
    var lc_source: Dictionary = landcover.get("source", {}) as Dictionary
    var lc_geometry: Dictionary = landcover.get("geometry", {}) as Dictionary
    var lc_policy: Dictionary = landcover.get("runtime_policy", {}) as Dictionary
    if str(lc_source.get("feature_id", "")) != "LandCover.1038":
        _fail("production LandCover feature drifted")
        return
    if float(lc_geometry.get("area_m2", 0.0)) < 50000.0:
        _fail("production LandCover area unexpectedly small")
        return
    if bool(lc_policy.get("material_photometry_resolved", true)) or bool(lc_policy.get("vegetation_geometry_resolved", true)):
        _fail("LandCover provisional semantics were incorrectly promoted")
        return

    var document := _load_dictionary(SURFACES_PATH)
    if document.is_empty():
        _fail("street-surface game dataset missing or invalid")
        return
    var features: Variant = document.get("features", [])
    if not features is Array or features.size() != expected_features:
        _fail("street-surface feature count does not match manifest")
        return

    var anchor_distances: Array[float] = []
    var spawn_distances: Array[float] = []
    var arrival_corridor_count := 0
    var arrival_corridor_area_m2 := 0.0
    var nearest_anchor := INF
    var nearest_spawn := INF
    var polygon_count := 0

    for raw_feature: Variant in features as Array:
        if not raw_feature is Dictionary:
            continue
        var geometry: Variant = (raw_feature as Dictionary).get("geometry", {})
        if not geometry is Dictionary:
            continue
        var feature_anchor := INF
        var feature_spawn := INF
        var feature_corridor := INF
        var feature_area := 0.0
        for ring: PackedVector2Array in _outer_rings(geometry as Dictionary):
            polygon_count += 1
            feature_anchor = minf(feature_anchor, _distance_to_ring(ATOMIUM_ANCHOR, ring))
            feature_spawn = minf(feature_spawn, _distance_to_ring(PLAYER_SPAWN, ring))
            feature_corridor = minf(feature_corridor, _segment_to_ring_distance(PLAYER_SPAWN, ATOMIUM_ANCHOR, ring))
            feature_area += _ring_area(ring)
        if is_finite(feature_anchor):
            anchor_distances.append(feature_anchor)
            nearest_anchor = minf(nearest_anchor, feature_anchor)
        if is_finite(feature_spawn):
            spawn_distances.append(feature_spawn)
            nearest_spawn = minf(nearest_spawn, feature_spawn)
        if feature_corridor <= ARRIVAL_CORRIDOR_HALF_WIDTH_M:
            arrival_corridor_count += 1
            arrival_corridor_area_m2 += feature_area

    if polygon_count <= 0 or anchor_distances.is_empty() or spawn_distances.is_empty():
        _fail("no usable official StreetSurface polygons")
        return

    var anchor_counts: Array[int] = []
    var spawn_counts: Array[int] = []
    for radius: float in RADII_M:
        var anchor_count := 0
        var spawn_count := 0
        for distance: float in anchor_distances:
            if distance <= radius:
                anchor_count += 1
        for distance: float in spawn_distances:
            if distance <= radius:
                spawn_count += 1
        anchor_counts.append(anchor_count)
        spawn_counts.append(spawn_count)

    if nearest_anchor > 160.0:
        _fail("nearest official StreetSurface is %.2f m from Atomium anchor" % nearest_anchor)
        return
    if arrival_corridor_count <= 0:
        _fail("no official StreetSurface intersects the legitimate player arrival corridor")
        return

    print("ATOMIUM_STREET_SURFACE_ARRIVAL_PROBE_METRICS: nearest_anchor=%.3fm nearest_spawn=%.3fm polygons=%d anchor_r30=%d anchor_r60=%d anchor_r100=%d anchor_r160=%d spawn_r30=%d spawn_r60=%d spawn_r100=%d spawn_r160=%d corridor_width=%.1fm corridor_features=%d corridor_area=%.2fm2 landcover=LandCover.1038" % [nearest_anchor, nearest_spawn, polygon_count, anchor_counts[0], anchor_counts[1], anchor_counts[2], anchor_counts[3], spawn_counts[0], spawn_counts[1], spawn_counts[2], spawn_counts[3], ARRIVAL_CORRIDOR_HALF_WIDTH_M * 2.0, arrival_corridor_count, arrival_corridor_area_m2])
    print("ATOMIUM_STREET_SURFACE_ARRIVAL_PROBE_OK: source=urbisvector:StreetSurfaces features=%d source_crs=EPSG:31370 existing_landcover_area=%.2f" % [features.size(), float(lc_geometry.get("area_m2", 0.0))])
    quit(0)
