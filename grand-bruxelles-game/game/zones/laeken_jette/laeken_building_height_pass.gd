extends Node

## Rebuild the Laeken building mesh with official remote-sensing-derived heights.
## Horizontal footprints remain UrbIS WFS geometry, including official interior rings.
## Per-building height and ground elevation come from the committed DSM-DTM analysis.
## Buildings without enough valid DSM/DTM samples keep the explicit 10.5 m fallback.
## A tiny, audited override set can correct landmark-overlap contamination without
## mutating the raw DSM-derived dataset. Palais 5 is cut out only from the monolithic
## Brussels Expo UrbIS feature so its sourced hero geometry can replace that volume.

const BUILDINGS_PATH := "res://data/urbis/laeken_jette/buildings.game.json"
const HEIGHTS_PATH := "res://data/urbis/laeken_jette/building_heights_dsm.game.json"
const OVERRIDES_PATH := "res://data/urbis/laeken_jette/building_height_landmark_overrides.game.json"
const PALAIS5_OUTLINE_PATH := "res://data/sources/laeken_jette/palais5_osm_outline.game.json"
const PALAIS5_EXPO_INSPIRE_ID := "https://databrussels.be/id/building/1635598"
const FALLBACK_HEIGHT_M := 10.5
const VALID_QUALITIES := ["high", "medium", "low"]

var height_mesh_ready: bool = false
var derived_buildings: int = 0
var fallback_buildings: int = 0
var high_quality: int = 0
var medium_quality: int = 0
var low_quality: int = 0
var landmark_corrected_buildings: int = 0
var official_hole_rings: int = 0
var palais5_cutouts: int = 0
var hole_aware_roof_triangles: int = 0
var derived_min_height_m: float = INF
var derived_max_height_m: float = -INF
var roof_min_y: float = INF
var roof_max_y: float = -INF
var atomium_absolute_elevation_m: float = 0.0
var _height_overrides: Dictionary = {}
var _palais5_cutout := PackedVector2Array()


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
        var ab := (a + b) * 0.5
        var bc := (b + c) * 0.5
        var ca := (c + a) * 0.5
        if not _point_in_surface(centroid, outer, holes):
            continue
        if not _point_in_surface(ab, outer, holes) or not _point_in_surface(bc, outer, holes) or not _point_in_surface(ca, outer, holes):
            continue
        for point in [a, b, c]:
            st.set_normal(Vector3.UP)
            st.add_vertex(Vector3(point.x, y, point.y))
        accepted += 1
    return accepted


func _append_walls(st: SurfaceTool, points: PackedVector2Array, bottom_y: float, top_y: float, reverse_normal: bool = false) -> void:
    for index in range(points.size()):
        var a := points[index]
        var b := points[(index + 1) % points.size()]
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
    var document := _load_json(PALAIS5_OUTLINE_PATH)
    var geometry = document.get("geometry", {})
    if not (geometry is Dictionary):
        return
    var sets := _polygon_ring_sets(geometry)
    if sets.size() != 1:
        return
    _palais5_cutout = sets[0]["outer"]


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
    _load_palais5_cutout()

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

        var polygon_sets := _polygon_ring_sets(geometry)
        if polygon_sets.is_empty():
            continue

        var first_outer: PackedVector2Array = polygon_sets[0]["outer"]
        var resolved := _resolve_record(record, properties, terrain, first_outer)
        var height := float(resolved["height"])
        var base_y := float(resolved["base_y"])
        var roof_y := base_y + height
        var inspire_id := str(properties.get("INSPIRE_ID", ""))

        for polygon_set in polygon_sets:
            var outer: PackedVector2Array = polygon_set["outer"]
            var holes: Array[PackedVector2Array] = polygon_set["holes"].duplicate()
            official_hole_rings += holes.size()
            if inspire_id == PALAIS5_EXPO_INSPIRE_ID and _palais5_cutout.size() >= 3:
                var cutout_centroid := _polygon_centroid(_palais5_cutout)
                if Geometry2D.is_point_in_polygon(cutout_centroid, outer):
                    holes.append(_palais5_cutout)
                    palais5_cutouts += 1
            hole_aware_roof_triangles += _append_flat_polygon_with_holes(surface, outer, holes, roof_y)
            _append_walls(surface, outer, base_y, roof_y)
            for hole in holes:
                _append_walls(surface, hole, base_y, roof_y, true)

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

    print("LAEKEN_BUILDING_HEIGHTS_READY: derived=%d fallback=%d landmark_corrected=%d holes=%d palais5_cutouts=%d roof_triangles=%d quality={high:%d,medium:%d,low:%d} height=[%.2f,%.2f] roof_y=[%.2f,%.2f]" % [
        derived_buildings,
        fallback_buildings,
        landmark_corrected_buildings,
        official_hole_rings,
        palais5_cutouts,
        hole_aware_roof_triangles,
        high_quality,
        medium_quality,
        low_quality,
        derived_min_height_m if derived_min_height_m < INF else 0.0,
        derived_max_height_m if derived_max_height_m > -INF else 0.0,
        roof_min_y if roof_min_y < INF else 0.0,
        roof_max_y if roof_max_y > -INF else 0.0,
    ])
