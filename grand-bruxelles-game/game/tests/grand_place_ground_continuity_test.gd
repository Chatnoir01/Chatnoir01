extends SceneTree

const DATA_PATH := "res://data/visual/grand_place_granite_paving.json"
const OUTPUT_PATH := "res://artifacts/qa/grand_place_ground_continuity.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_GROUND_CONTINUITY_FAIL: %s" % message)
    quit(1)

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
    for _i: int in range(30):
        await process_frame
    await physics_frame

    var paving := root.get_node_or_null("GrandPlaceGranitePaving")
    if paving == null:
        _fail("GrandPlaceGranitePaving autoload missing")
        return
    if not bool(paving.geometry_loaded()) or not bool(paving.collision_ready()):
        _fail("official granite geometry/collision not ready")
        return
    if not str(paving.source_feature_id()).ends_with("/42405"):
        _fail("unexpected official StreetSurface feature")
        return
    var area := float(paving.source_polygon_area_m2())
    if area < 5000.0 or area > 5500.0:
        _fail("official paving polygon area outside frozen sanity band: %.3f" % area)
        return

    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("paving source JSON invalid")
        return
    var data: Dictionary = parsed
    var raw_polygon: Array = data.get("polygon_lambert72", [])
    var transform: Dictionary = data.get("transform", {})
    var lambert_origin: Array = transform.get("lambert72_origin", [])
    var world_origin: Array = transform.get("world_origin", [])
    if raw_polygon.size() < 4 or lambert_origin.size() != 2 or world_origin.size() != 2:
        _fail("source transform/polygon incomplete")
        return

    var polygon := PackedVector2Array()
    for raw: Variant in raw_polygon:
        var p: Array = raw
        polygon.append(Vector2(
            float(p[0]) - float(lambert_origin[0]) + float(world_origin[0]),
            -(float(p[1]) - float(lambert_origin[1])) + float(world_origin[1])
        ))
    if polygon.size() >= 2 and polygon[0].distance_to(polygon[polygon.size()-1]) < 0.001:
        polygon.resize(polygon.size()-1)
    var indices := Geometry2D.triangulate_polygon(polygon)
    if indices.is_empty() or indices.size() % 3 != 0:
        _fail("official paving triangulation failed")
        return

    var mean := Vector2.ZERO
    for p: Vector2 in polygon:
        mean += p
    mean /= float(polygon.size())

    var best_by_quadrant := [{}, {}, {}, {}]
    var largest := {}
    for i: int in range(0, indices.size(), 3):
        var a := polygon[indices[i]]
        var b := polygon[indices[i+1]]
        var c := polygon[indices[i+2]]
        var centroid := (a+b+c)/3.0
        var tri_area := _triangle_area(a,b,c)
        var d := centroid - mean
        var q := 0
        if d.x >= 0.0 and d.y < 0.0:
            q = 1
        elif d.x < 0.0 and d.y < 0.0:
            q = 2
        elif d.x < 0.0 and d.y >= 0.0:
            q = 3
        if best_by_quadrant[q].is_empty() or tri_area > float(best_by_quadrant[q].get("area", 0.0)):
            best_by_quadrant[q] = {"point": centroid, "area": tri_area}
        if largest.is_empty() or tri_area > float(largest.get("area", 0.0)):
            largest = {"point": centroid, "area": tri_area}

    var samples: Array[Vector2] = []
    samples.append(largest["point"])
    for q: int in range(4):
        if best_by_quadrant[q].is_empty():
            _fail("missing triangulated paving sample quadrant %d" % q)
            return
        samples.append(best_by_quadrant[q]["point"])

    var space := scene.get_world_3d().direct_space_state
    var evidence: Array = []
    for index: int in range(samples.size()):
        var p := samples[index]
        var query := PhysicsRayQueryParameters3D.create(Vector3(p.x, 3.0, p.y), Vector3(p.x, -1.0, p.y), 1)
        var hit := space.intersect_ray(query)
        if hit.is_empty():
            _fail("no ground collision at source-derived sample %d" % index)
            return
        var collider: Object = hit.get("collider")
        var collider_name := str((collider as Node).name) if collider is Node else str(collider)
        if collider_name != "OfficialGraniteStreetSurfaceCollision":
            _fail("sample %d hit %s instead of official granite collision" % [index, collider_name])
            return
        var pos: Vector3 = hit.get("position")
        evidence.append({
            "sample": index,
            "world_xz": [p.x, p.y],
            "hit_y": pos.y,
            "collider": collider_name,
        })

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/qa"))
    var report := {
        "schema": "grand-bruxelles-grand-place-ground-continuity-v1",
        "source_feature_id": str(paving.source_feature_id()),
        "source_polygon_area_m2": area,
        "sample_policy": "largest official polygon triangle centroid + largest triangle centroid in each world-XZ quadrant; every sample lies inside source triangulation",
        "sample_count": evidence.size(),
        "samples": evidence,
        "street_join_geometry_invented": false,
        "curb_height_claimed": false,
    }
    var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
    if file == null:
        _fail("report write failed")
        return
    file.store_string(JSON.stringify(report, "  ") + "\n")
    file.close()
    print("GRAND_PLACE_GROUND_CONTINUITY_OK: feature=42405 area=%.3f samples=%d" % [area, evidence.size()])
    quit(0)
