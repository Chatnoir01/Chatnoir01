extends Node

## Rebuild the Laeken building mesh with official remote-sensing-derived heights.
## Horizontal footprints are unchanged UrbIS WFS geometry. Per-building height and
## ground elevation come from the committed DSM-DTM analysis. Buildings without
## enough valid DSM/DTM samples keep the explicit 10.5 m fallback. A tiny, audited
## override set can correct landmark-overlap contamination without mutating the raw
## DSM-derived dataset.

const BUILDINGS_PATH := "res://data/urbis/laeken_jette/buildings.game.json"
const HEIGHTS_PATH := "res://data/urbis/laeken_jette/building_heights_dsm.game.json"
const OVERRIDES_PATH := "res://data/urbis/laeken_jette/building_height_landmark_overrides.game.json"
const FALLBACK_HEIGHT_M := 10.5
const VALID_QUALITIES := ["high", "medium", "low"]

var height_mesh_ready: bool = false
var derived_buildings: int = 0
var fallback_buildings: int = 0
var high_quality: int = 0
var medium_quality: int = 0
var low_quality: int = 0
var landmark_corrected_buildings: int = 0
var derived_min_height_m: float = INF
var derived_max_height_m: float = -INF
var roof_min_y: float = INF
var roof_max_y: float = -INF
var atomium_absolute_elevation_m: float = 0.0
var _height_overrides: Dictionary = {}


func _ready() -> void:
    call_deferred("_build_height_mesh")


func _load_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed = JSON.parse_string(file.get_as_text())
    return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}


func _outer_rings(geometry: Dictionary) -> Array:
    var result: Array = []
    var kind := str(geometry.get("type", ""))
    var coords = geometry.get("coordinates", [])
    if kind == "Polygon" and coords is Array and not coords.is_empty():
        result.append(coords[0])
    elif kind == "MultiPolygon" and coords is Array:
        for polygon in coords:
            if polygon is Array and not polygon.is_empty():
                result.append(polygon[0])
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
    var sum := Vector2.ZERO
    for point in points:
        sum += point
    return sum / float(points.size())


func _resolve_record(record: Dictionary, properties: Dictionary, terrain: Node, points: PackedVector2Array) -> Dictionary:
    var source_quality := str(record.get("quality", ""))
    var inspire_id := str(properties.get("INSPIRE_ID", ""))
    if _height_overrides.has(inspire_id):
        var override = _height_overrides[inspire_id]
        if override is Dictionary:
            var corrected_height := float(override.get("height_m", -1.0))
            if corrected_height >= 2.0 and corrected_height <= 120.0:
                var ground_abs = record.get("ground_median_abs_m", null)
                var corrected_base_y: float
                if ground_abs != null:
                    corrected_base_y = float(ground_abs) - atomium_absolute_elevation_m
                else:
                    var corrected_centroid := _polygon_centroid(points)
                    corrected_base_y = float(terrain.call("sample_height", corrected_centroid.x, corrected_centroid.y))
                return {
                    "derived": true,
                    "quality": "landmark_corrected",
                    "source_quality": source_quality,
                    "height": corrected_height,
                    "base_y": corrected_base_y,
                    "landmark_corrected": true,
                    "override_method": str(override.get("method", "")),
                }

    var raw_height = record.get("height_m", null)
    if source_quality in VALID_QUALITIES and raw_height != null:
        var height := float(raw_height)
        if height >= 2.0 and height <= 120.0:
            var ground_abs = record.get("ground_median_abs_m", null)
            var base_y: float
            if ground_abs != null:
                base_y = float(ground_abs) - atomium_absolute_elevation_m
            else:
                var centroid := _polygon_centroid(points)
                base_y = float(terrain.call("sample_height", centroid.x, centroid.y))
            return {
                "derived": true,
                "quality": source_quality,
                "source_quality": source_quality,
                "height": height,
                "base_y": base_y,
                "landmark_corrected": false,
            }

    var fallback_centroid := _polygon_centroid(points)
    var fallback_base := float(terrain.call("sample_height", fallback_centroid.x, fallback_centroid.y))
    return {
        "derived": false,
        "quality": "fallback",
        "source_quality": source_quality,
        "height": FALLBACK_HEIGHT_M,
        "base_y": fallback_base,
        "landmark_corrected": false,
    }


func _append_flat_polygon(st: SurfaceTool, points: PackedVector2Array, y: float) -> void:
    var triangles := Geometry2D.triangulate_polygon(points)
    for index in triangles:
        var p := points[int(index)]
        st.set_normal(Vector3.UP)
        st.add_vertex(Vector3(p.x, y, p.y))


func _append_walls(st: SurfaceTool, points: PackedVector2Array, bottom_y: float, top_y: float) -> void:
    for index in range(points.size()):
        var a := points[index]
        var b := points[(index + 1) % points.size()]
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


func _build_height_mesh() -> void:
    var terrain = get_parent().get_node_or_null("LaekenTerrain")
    if terrain == null or not bool(terrain.get("terrain_loaded")):
        push_warning("LaekenBuildingHeightPass: official terrain unavailable")
        return

    atomium_absolute_elevation_m = float(terrain.get("atomium_absolute_elevation_m"))
    var buildings := _load_json(BUILDINGS_PATH)
    var heights_document := _load_json(HEIGHTS_PATH)
    var overrides_document := _load_json(OVERRIDES_PATH)
    var override_value = overrides_document.get("overrides", {})
    _height_overrides = override_value as Dictionary if override_value is Dictionary else {}

    var features = buildings.get("features", [])
    var records = heights_document.get("records", [])
    if not (features is Array) or features.is_empty():
        push_warning("LaekenBuildingHeightPass: building geometry unavailable")
        return
    if not (records is Array) or records.size() != features.size():
        push_warning("LaekenBuildingHeightPass: height records missing or misaligned; preserving original building mesh")
        return

    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)

    for feature_index in range(features.size()):
        var feature = features[feature_index]
        if not (feature is Dictionary):
            continue
        var geometry = feature.get("geometry", {})
        if not (geometry is Dictionary):
            continue
        var properties = feature.get("properties", {})
        if not (properties is Dictionary):
            properties = {}
        var record = records[feature_index]
        if not (record is Dictionary):
            record = {}

        var valid_rings: Array[PackedVector2Array] = []
        for ring in _outer_rings(geometry):
            var points := _ring_to_points(ring)
            if points.size() >= 3:
                valid_rings.append(points)
        if valid_rings.is_empty():
            continue

        var resolved := _resolve_record(record, properties, terrain, valid_rings[0])
        var height := float(resolved["height"])
        var base_y := float(resolved["base_y"])
        var roof_y := base_y + height
        for points in valid_rings:
            _append_flat_polygon(surface, points, roof_y)
            _append_walls(surface, points, base_y, roof_y)

        roof_min_y = minf(roof_min_y, roof_y)
        roof_max_y = maxf(roof_max_y, roof_y)
        if bool(resolved["derived"]):
            derived_buildings += 1
            derived_min_height_m = minf(derived_min_height_m, height)
            derived_max_height_m = maxf(derived_max_height_m, height)
            if bool(resolved.get("landmark_corrected", false)):
                landmark_corrected_buildings += 1
            match str(resolved.get("source_quality", resolved["quality"])):
                "high": high_quality += 1
                "medium": medium_quality += 1
                "low": low_quality += 1
        else:
            fallback_buildings += 1

    var mesh := surface.commit()
    if mesh == null or mesh.get_surface_count() == 0:
        push_warning("LaekenBuildingHeightPass: derived mesh is empty")
        return

    var original := get_parent().get_node_or_null("OfficialBuildings") as MeshInstance3D
    if original != null:
        var source_material := original.mesh.surface_get_material(0) if original.mesh != null and original.mesh.get_surface_count() > 0 else null
        if source_material != null:
            mesh.surface_set_material(0, source_material)
        original.visible = false

    var replacement := MeshInstance3D.new()
    replacement.name = "OfficialBuildingsDSM"
    replacement.mesh = mesh
    get_parent().add_child(replacement)
    height_mesh_ready = true

    print("LAEKEN_BUILDING_HEIGHTS_READY: derived=%d fallback=%d landmark_corrected=%d quality={high:%d,medium:%d,low:%d} height=[%.2f,%.2f] roof_y=[%.2f,%.2f]" % [
        derived_buildings,
        fallback_buildings,
        landmark_corrected_buildings,
        high_quality,
        medium_quality,
        low_quality,
        derived_min_height_m if derived_min_height_m < INF else 0.0,
        derived_max_height_m if derived_max_height_m > -INF else 0.0,
        roof_min_y if roof_min_y < INF else 0.0,
        roof_max_y if roof_max_y > -INF else 0.0,
    ])
