extends SceneTree

const BUILDINGS_PATH := "res://data/urbis/laeken_jette/buildings.game.json"
const PALAIS5_PATH := "res://data/sources/laeken_jette/palais5_osm_outline.game.json"

func _initialize() -> void:
    call_deferred("_run")

func _load_json(path: String) -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed = JSON.parse_string(file.get_as_text())
    return parsed as Dictionary if parsed is Dictionary else {}

func _rings(geometry: Dictionary) -> Array:
    var out: Array = []
    var kind := String(geometry.get("type", ""))
    var coords = geometry.get("coordinates", [])
    if kind == "Polygon" and coords is Array and not coords.is_empty():
        out.append(coords[0])
    elif kind == "MultiPolygon" and coords is Array:
        for polygon in coords:
            if polygon is Array and not polygon.is_empty():
                out.append(polygon[0])
    return out

func _points(ring: Array) -> PackedVector2Array:
    var out := PackedVector2Array()
    for raw in ring:
        if raw is Array and raw.size() >= 2:
            out.append(Vector2(float(raw[0]), float(raw[1])))
    if out.size() >= 2 and out[0].distance_to(out[out.size() - 1]) < 0.001:
        out.resize(out.size() - 1)
    return out

func _bbox(points: PackedVector2Array) -> Rect2:
    if points.is_empty():
        return Rect2()
    var min_x := points[0].x
    var max_x := points[0].x
    var min_y := points[0].y
    var max_y := points[0].y
    for point in points:
        min_x = minf(min_x, point.x)
        max_x = maxf(max_x, point.x)
        min_y = minf(min_y, point.y)
        max_y = maxf(max_y, point.y)
    return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))

func _inside_share(subject: PackedVector2Array, polygon: PackedVector2Array) -> float:
    if subject.is_empty() or polygon.size() < 3:
        return 0.0
    var inside := 0
    for point in subject:
        if Geometry2D.is_point_in_polygon(point, polygon):
            inside += 1
    return float(inside) / float(subject.size())

func _run() -> void:
    var buildings := _load_json(BUILDINGS_PATH)
    var palais := _load_json(PALAIS5_PATH)
    if buildings.is_empty() or palais.is_empty():
        push_error("LAEKEN_PALAIS5_OVERLAP_INSPECT_FAIL: source JSON missing")
        quit(1)
        return
    var source_rings := _rings(palais.get("geometry", {}))
    if source_rings.is_empty():
        push_error("LAEKEN_PALAIS5_OVERLAP_INSPECT_FAIL: Palais 5 ring missing")
        quit(1)
        return
    var source := _points(source_rings[0])
    var source_bbox := _bbox(source)
    var centroid := source_bbox.get_center()
    var matches: Array[Dictionary] = []
    var features = buildings.get("features", [])
    for feature_index in range(features.size()):
        var feature = features[feature_index]
        if not feature is Dictionary:
            continue
        var properties = feature.get("properties", {})
        var geometry = feature.get("geometry", {})
        if not geometry is Dictionary:
            continue
        var ring_index := 0
        for raw_ring in _rings(geometry):
            var candidate := _points(raw_ring)
            if candidate.size() < 3:
                ring_index += 1
                continue
            var box := _bbox(candidate)
            var source_inside := _inside_share(source, candidate)
            var candidate_inside := _inside_share(candidate, source)
            var centroid_inside := Geometry2D.is_point_in_polygon(centroid, candidate)
            if source_inside >= 0.05 or candidate_inside >= 0.05 or centroid_inside or box.intersects(source_bbox):
                matches.append({
                    "feature_index": feature_index,
                    "ring_index": ring_index,
                    "source_inside_share": snappedf(source_inside, 0.000001),
                    "candidate_inside_share": snappedf(candidate_inside, 0.000001),
                    "centroid_inside": centroid_inside,
                    "bbox": [box.position.x, box.position.y, box.end.x, box.end.y],
                    "bbox_size": [box.size.x, box.size.y],
                    "properties": properties,
                })
            ring_index += 1
    print("LAEKEN_PALAIS5_OVERLAP_INSPECT_OK: source_bbox=%s source_vertices=%d matches=%s" % [source_bbox, source.size(), JSON.stringify(matches)])
    quit(0)
