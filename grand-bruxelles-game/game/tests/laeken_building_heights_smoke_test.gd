extends SceneTree

const BUILDINGS_PATH := "res://data/urbis/laeken_jette/buildings.game.json"
const HEIGHTS_PATH := "res://data/urbis/laeken_jette/building_heights_dsm.game.json"
const OVERRIDES_PATH := "res://data/urbis/laeken_jette/building_height_landmark_overrides.game.json"
const PALAIS5_OUTLINE_PATH := "res://data/sources/laeken_jette/palais5_osm_outline.game.json"
const PALAIS5_EXPO_INSPIRE_ID := "https://databrussels.be/id/building/1635598"
const MAX_READY_FRAMES := 90
const ROOF_Y_EPSILON := 0.001
const OVERLAP_AREA_EPSILON_M2 := 0.0001


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("LAEKEN_BUILDING_HEIGHTS_FAIL: %s" % message)
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


func _triangle_bounds(triangle: PackedVector2Array) -> Rect2:
    return _polygon_bounds(triangle)


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
        if not (properties is Dictionary):
            continue
        if str(properties.get("INSPIRE_ID", "")) != PALAIS5_EXPO_INSPIRE_ID:
            continue
        var geometry = feature.get("geometry", {})
        if not (geometry is Dictionary):
            return {}
        var kind := str(geometry.get("type", ""))
        var coordinates = geometry.get("coordinates", [])
        var polygon: Array = []
        if kind == "Polygon" and coordinates is Array and not coordinates.is_empty():
            polygon = coordinates
        elif kind == "MultiPolygon" and coordinates is Array and coordinates.size() == 1 and coordinates[0] is Array:
            polygon = coordinates[0]
        if polygon.is_empty():
            return {}
        var outer := _ring_to_points(polygon[0])
        var holes: Array[PackedVector2Array] = []
        for ring_index in range(1, polygon.size()):
            var hole := _ring_to_points(polygon[ring_index])
            if hole.size() >= 3:
                holes.append(hole)
        return {"outer": outer, "holes": holes}
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


func _verify_expo_roof_voids(mesh: Mesh) -> Dictionary:
    var expo := _load_expo_geometry()
    if expo.is_empty():
        return {"error": "Expo aggregate source geometry missing"}
    var outer: PackedVector2Array = expo["outer"]
    var official_holes: Array[PackedVector2Array] = expo["holes"]
    var palais5 := _load_palais5_outline()
    if outer.size() < 3 or official_holes.size() < 14 or palais5.size() < 3:
        return {
            "error": "invalid Expo/Palais 5 source geometry: outer=%d holes=%d palais5=%d" % [
                outer.size(),
                official_holes.size(),
                palais5.size(),
            ]
        }

    var forbidden: Array[PackedVector2Array] = official_holes.duplicate()
    forbidden.append(palais5)
    var forbidden_bounds: Array[Rect2] = []
    for polygon in forbidden:
        forbidden_bounds.append(_polygon_bounds(polygon))

    var expo_bounds := _polygon_bounds(outer)
    var arrays := mesh.surface_get_arrays(0)
    if arrays.is_empty():
        return {"error": "DSM mesh surface arrays missing"}
    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    if vertices.size() < 3 or vertices.size() % 3 != 0:
        return {"error": "unexpected DSM triangle vertex array size: %d" % vertices.size()}

    var roof_triangles_checked := 0
    var expo_roof_triangles := 0
    var forbidden_overlap_triangles := 0
    var max_forbidden_overlap_m2 := 0.0
    var expo_survivor_area_m2 := 0.0

    for offset in range(0, vertices.size(), 3):
        var a := vertices[offset]
        var b := vertices[offset + 1]
        var c := vertices[offset + 2]
        if absf(a.y - b.y) > ROOF_Y_EPSILON or absf(a.y - c.y) > ROOF_Y_EPSILON:
            continue
        roof_triangles_checked += 1
        var triangle := PackedVector2Array([
            Vector2(a.x, a.z),
            Vector2(b.x, b.z),
            Vector2(c.x, c.z),
        ])
        var tri_bounds := _triangle_bounds(triangle)
        if not expo_bounds.intersects(tri_bounds, true):
            continue

        var centroid := (triangle[0] + triangle[1] + triangle[2]) / 3.0
        if Geometry2D.is_point_in_polygon(centroid, outer):
            expo_roof_triangles += 1

        var blocked_overlap := 0.0
        for forbidden_index in range(forbidden.size()):
            if not forbidden_bounds[forbidden_index].intersects(tri_bounds, true):
                continue
            blocked_overlap += _intersection_area(triangle, forbidden[forbidden_index])
        if blocked_overlap > OVERLAP_AREA_EPSILON_M2:
            forbidden_overlap_triangles += 1
            max_forbidden_overlap_m2 = maxf(max_forbidden_overlap_m2, blocked_overlap)
        elif Geometry2D.is_point_in_polygon(centroid, outer):
            expo_survivor_area_m2 += _polygon_area(triangle)

    if forbidden_overlap_triangles > 0:
        return {
            "error": "DSM roof geometry fills an official void/cutout: triangles=%d max_overlap=%.6fm2" % [
                forbidden_overlap_triangles,
                max_forbidden_overlap_m2,
            ],
            "roof_triangles_checked": roof_triangles_checked,
            "expo_roof_triangles": expo_roof_triangles,
            "forbidden_overlap_triangles": forbidden_overlap_triangles,
            "max_forbidden_overlap_m2": max_forbidden_overlap_m2,
            "expo_survivor_area_m2": expo_survivor_area_m2,
        }
    if expo_roof_triangles < 50 or expo_survivor_area_m2 < 10000.0:
        return {
            "error": "Expo aggregate appears over-cut or missing after void preservation: roof_triangles=%d survivor_area=%.2fm2" % [
                expo_roof_triangles,
                expo_survivor_area_m2,
            ]
        }

    return {
        "roof_triangles_checked": roof_triangles_checked,
        "expo_roof_triangles": expo_roof_triangles,
        "forbidden_overlap_triangles": forbidden_overlap_triangles,
        "max_forbidden_overlap_m2": max_forbidden_overlap_m2,
        "expo_survivor_area_m2": expo_survivor_area_m2,
        "official_holes": official_holes.size(),
    }


func _run() -> void:
    for required in [BUILDINGS_PATH, HEIGHTS_PATH, OVERRIDES_PATH, PALAIS5_OUTLINE_PATH]:
        if not FileAccess.file_exists(required):
            _fail("required building-height data missing: %s" % required)
            return
    var packed := load("res://game/zones/laeken_jette/laeken_jette.tscn") as PackedScene
    if packed == null:
        _fail("Laeken scene failed to load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)

    var height_pass = scene.get_node_or_null("BuildingHeightPass")
    var bridge = scene.get_node_or_null("BuildingDSMMaterialBridge")
    if height_pass == null:
        _fail("BuildingHeightPass missing")
        return
    if bridge == null:
        _fail("BuildingDSMMaterialBridge missing")
        return

    var ready_frame := -1
    for frame_index in range(MAX_READY_FRAMES):
        if bool(height_pass.get("height_mesh_ready")) and bool(bridge.get("material_bridged")):
            ready_frame = frame_index
            break
        await process_frame
    if ready_frame < 0:
        _fail("DSM mesh/material did not become ready within %d frames; height_ready=%s material_bridged=%s" % [
            MAX_READY_FRAMES,
            bool(height_pass.get("height_mesh_ready")),
            bool(bridge.get("material_bridged")),
        ])
        return

    var derived := int(height_pass.get("derived_buildings"))
    var fallback := int(height_pass.get("fallback_buildings"))
    var corrected := int(height_pass.get("landmark_corrected_buildings"))
    var official_holes := int(height_pass.get("official_hole_rings"))
    var palais5_cutouts := int(height_pass.get("palais5_cutouts"))
    var roof_triangles := int(height_pass.get("hole_aware_roof_triangles"))
    var high := int(height_pass.get("high_quality"))
    var medium := int(height_pass.get("medium_quality"))
    var low := int(height_pass.get("low_quality"))
    var min_height := float(height_pass.get("derived_min_height_m"))
    var max_height := float(height_pass.get("derived_max_height_m"))

    if derived != 9163 or fallback != 355:
        _fail("building accounting mismatch: derived=%d fallback=%d" % [derived, fallback])
        return
    if corrected != 1:
        _fail("expected exactly one audited landmark-overlap correction, got %d" % corrected)
        return
    if official_holes < 14:
        _fail("official UrbIS interior rings were lost: holes=%d" % official_holes)
        return
    if palais5_cutouts != 1:
        _fail("Palais 5 must be cut from exactly one Expo aggregate polygon, got %d" % palais5_cutouts)
        return
    if roof_triangles <= 0:
        _fail("hole-aware roof triangulation emitted no triangles")
        return
    if high != 7357 or medium != 1136 or low != 670:
        _fail("source quality accounting changed: high=%d medium=%d low=%d" % [high, medium, low])
        return
    if min_height < 2.0 or max_height < 35.0 or max_height > 120.0:
        _fail("runtime height range implausible after landmark correction: [%.3f, %.3f]" % [min_height, max_height])
        return

    var old_mesh := scene.get_node_or_null("OfficialBuildings") as MeshInstance3D
    var dsm_mesh := scene.get_node_or_null("OfficialBuildingsDSM") as MeshInstance3D
    if old_mesh == null or dsm_mesh == null:
        _fail("old or DSM building mesh missing")
        return
    if old_mesh.visible:
        _fail("uniform-height original building mesh is still visible")
        return
    if not dsm_mesh.visible:
        _fail("DSM building mesh is not visible")
        return
    if dsm_mesh.mesh == null or dsm_mesh.mesh.get_surface_count() == 0:
        _fail("DSM building mesh geometry missing")
        return
    var bounds := dsm_mesh.mesh.get_aabb()
    if bounds.size.y < 50.0:
        _fail("DSM building mesh still lacks meaningful vertical variation: AABB %.3fm" % bounds.size.y)
        return
    if not dsm_mesh.material_override is ShaderMaterial:
        _fail("DSM mesh final ShaderMaterial missing")
        return

    var void_proof := _verify_expo_roof_voids(dsm_mesh.mesh)
    if void_proof.has("error"):
        _fail(str(void_proof["error"]))
        return

    print("LAEKEN_BUILDING_HEIGHTS_OK: ready_frame=%d derived=%d fallback=%d landmark_corrected=%d holes=%d palais5_cutouts=%d roof_triangles=%d quality={high:%d,medium:%d,low:%d} height=[%.2f,%.2f] mesh_vertical=%.2fm expo_roofs=%d expo_survivor_area=%.2fm2 forbidden_overlap=%d" % [
        ready_frame,
        derived,
        fallback,
        corrected,
        official_holes,
        palais5_cutouts,
        roof_triangles,
        high,
        medium,
        low,
        min_height,
        max_height,
        bounds.size.y,
        int(void_proof["expo_roof_triangles"]),
        float(void_proof["expo_survivor_area_m2"]),
        int(void_proof["forbidden_overlap_triangles"]),
    ])
    scene.queue_free()
    await process_frame
    quit(0)
