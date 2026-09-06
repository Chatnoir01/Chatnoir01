extends SceneTree

const DATA_PATH := "res://data/visual/grand_place_granite_paving.json"
const EXPECTED_FEATURE_ID := "https://databrussels.be/id/streetsurface/42405"
const EXPECTED_COLLIDER := "OfficialGraniteStreetSurfaceCollision"
const MIN_TRIANGLE_CENTROID_SAMPLES := 80
const RAY_TOP_Y := 1.80
const RAY_BOTTOM_Y := -0.50
const EXPECTED_SURFACE_Y := 0.012
const SURFACE_Y_TOLERANCE := 0.02

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_GROUND_CONTINUITY_FAIL: %s" % message)
    quit(1)

func _finite_number(value: Variant) -> bool:
    return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))

func _triangle_area(a: Vector2, b: Vector2, c: Vector2) -> float:
    return absf((b - a).cross(c - a)) * 0.5

func _run() -> void:
    var packed: PackedScene = load("res://game/main.tscn")
    if packed == null:
        _fail("main scene failed to load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    current_scene = scene
    for _i: int in range(45):
        await process_frame
    await physics_frame

    var paving := root.get_node_or_null("GrandPlaceGranitePaving")
    if paving == null:
        _fail("GrandPlaceGranitePaving autoload missing")
        return
    if not bool(paving.geometry_loaded()) or not bool(paving.collision_ready()):
        _fail("official granite geometry/collision not ready")
        return
    if str(paving.source_feature_id()) != EXPECTED_FEATURE_ID:
        _fail("unexpected official StreetSurface feature: %s" % str(paving.source_feature_id()))
        return
    var runtime_area := float(paving.source_polygon_area_m2())
    if not is_finite(runtime_area) or runtime_area < 5335.0 or runtime_area > 5339.0:
        _fail("official paving polygon area outside frozen source sanity band: %.3f" % runtime_area)
        return

    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("paving source JSON invalid")
        return
    var data: Dictionary = parsed
    var source: Dictionary = data.get("source", {})
    if str(source.get("feature_id", "")) != EXPECTED_FEATURE_ID:
        _fail("source JSON feature id drift")
        return
    if str(source.get("layer", "")) != "urbisvector:StreetSurfaces":
        _fail("source layer drift")
        return
    if str(source.get("crs", "")) != "EPSG:31370":
        _fail("source CRS drift")
        return

    var raw_polygon: Array = data.get("polygon_lambert72", [])
    var transform: Dictionary = data.get("transform", {})
    var lambert_origin: Array = transform.get("lambert72_origin", [])
    var world_origin: Array = transform.get("world_origin", [])
    if raw_polygon.size() < 4 or lambert_origin.size() != 2 or world_origin.size() != 2:
        _fail("source transform/polygon incomplete")
        return
    for value: Variant in lambert_origin + world_origin:
        if not _finite_number(value):
            _fail("non-finite source transform")
            return

    var polygon := PackedVector2Array()
    for raw: Variant in raw_polygon:
        if typeof(raw) != TYPE_ARRAY:
            _fail("source polygon point is not an array")
            return
        var point: Array = raw
        if point.size() != 2 or not _finite_number(point[0]) or not _finite_number(point[1]):
            _fail("source polygon contains malformed/non-finite point")
            return
        polygon.append(Vector2(
            float(point[0]) - float(lambert_origin[0]) + float(world_origin[0]),
            -(float(point[1]) - float(lambert_origin[1])) + float(world_origin[1])
        ))
    if polygon.size() >= 2 and polygon[0].distance_to(polygon[polygon.size() - 1]) < 0.001:
        polygon.resize(polygon.size() - 1)

    var indices := Geometry2D.triangulate_polygon(polygon)
    if indices.is_empty() or indices.size() % 3 != 0:
        _fail("official paving triangulation failed")
        return
    var triangle_count := indices.size() / 3
    if triangle_count < MIN_TRIANGLE_CENTROID_SAMPLES:
        _fail("official paving triangulation unexpectedly sparse: %d" % triangle_count)
        return

    var collision_body := paving.get_node_or_null(EXPECTED_COLLIDER)
    if collision_body == null or not collision_body is StaticBody3D:
        _fail("official collision body missing")
        return
    if int((collision_body as StaticBody3D).collision_layer) & 1 == 0:
        _fail("official collision body is not on player-foot layer 1")
        return
    if str(collision_body.get_meta("source_feature_id", "")) != EXPECTED_FEATURE_ID:
        _fail("collision provenance does not match StreetSurface 42405")
        return
    if str(collision_body.get_meta("geometry_source", "")) != "same_official_granite_mesh":
        _fail("collision is not derived from the rendered official mesh")
        return

    var space: PhysicsDirectSpaceState3D = scene.get_world_3d().direct_space_state
    var samples: Array = []
    var max_hit_y_error := 0.0
    var total_area := 0.0
    var sampled_area := 0.0
    var triangle_index := 0
    for i: int in range(0, indices.size(), 3):
        var a := polygon[indices[i]]
        var b := polygon[indices[i + 1]]
        var c := polygon[indices[i + 2]]
        var area := _triangle_area(a, b, c)
        if not is_finite(area) or area <= 0.0:
            _fail("degenerate/non-finite source triangle %d" % triangle_index)
            return
        total_area += area
        var centroid := (a + b + c) / 3.0
        var query := PhysicsRayQueryParameters3D.create(
            Vector3(centroid.x, RAY_TOP_Y, centroid.y),
            Vector3(centroid.x, RAY_BOTTOM_Y, centroid.y),
            1
        )
        var hit: Dictionary = space.intersect_ray(query)
        if hit.is_empty():
            _fail("player-foot collision hole at source triangle centroid %d" % triangle_index)
            return
        var collider: Object = hit.get("collider")
        var collider_name := str((collider as Node).name) if collider is Node else str(collider)
        if collider_name != EXPECTED_COLLIDER:
            _fail("triangle centroid %d hit %s instead of official paving collision" % [triangle_index, collider_name])
            return
        var hit_pos: Vector3 = hit.get("position", Vector3.INF)
        if not is_finite(hit_pos.x) or not is_finite(hit_pos.y) or not is_finite(hit_pos.z):
            _fail("non-finite collision hit at triangle %d" % triangle_index)
            return
        var hit_y_error := absf(hit_pos.y - EXPECTED_SURFACE_Y)
        if hit_y_error > SURFACE_Y_TOLERANCE:
            _fail("triangle %d collision height drift %.4f m" % [triangle_index, hit_y_error])
            return
        max_hit_y_error = maxf(max_hit_y_error, hit_y_error)
        sampled_area += area
        samples.append({
            "triangle": triangle_index,
            "world_xz": [centroid.x, centroid.y],
            "triangle_area_m2": area,
            "hit_y": hit_pos.y,
            "collider": collider_name,
        })
        triangle_index += 1

    if absf(sampled_area - total_area) > 0.001:
        _fail("triangle sample coverage accounting drift")
        return

    var report := {
        "schema": "grand-bruxelles-grand-place-ground-continuity-v2",
        "source_feature_id": EXPECTED_FEATURE_ID,
        "source_layer": "urbisvector:StreetSurfaces",
        "source_crs": "EPSG:31370",
        "source_polygon_area_m2": runtime_area,
        "triangle_count": triangle_count,
        "sample_count": samples.size(),
        "sample_policy": "every centroid of the exact Godot triangulation of official StreetSurface 42405",
        "sampled_triangle_area_m2": sampled_area,
        "max_collision_height_error_m": max_hit_y_error,
        "collision_layer": 1,
        "collision_owner": EXPECTED_COLLIDER,
        "collision_geometry_source": "same_official_granite_mesh",
        "street_join_geometry_invented": false,
        "curb_height_claimed": false,
        "sidewalk_profile_claimed": false,
        "destination_advertisable": false,
        "visual_acceptance": false,
        "jouable_authorized": false,
        "samples": samples,
    }
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/qa"))
    var output_path := "res://artifacts/qa/grand_place_ground_continuity.json"
    var file := FileAccess.open(output_path, FileAccess.WRITE)
    if file == null:
        _fail("report write failed")
        return
    file.store_string(JSON.stringify(report, "  ") + "\n")
    file.close()
    print("GRAND_PLACE_GROUND_CONTINUITY_OK feature=42405 triangles=%d samples=%d area=%.3f max_hit_y_error=%.4f visual_acceptance=false jouable_authorized=false" % [triangle_count, samples.size(), runtime_area, max_hit_y_error])
    quit(0)
