extends SceneTree

const BUILDER_SCRIPT := preload("res://game/scripts/osm_city_builder.gd")
const SOURCE_PATH := "res://data/osm/vertical_slice_01.game.json"
const TARGET_OSM_ID := 256376389
const EXPECTED_HEIGHT := 14.0
const EXPECTED_CENTER := Vector2(-285.4966, -185.4604)
const EXPECTED_FOOTPRINT: Array[Vector2] = [
    Vector2(-285.331, -198.761),
    Vector2(-274.885, -190.701),
    Vector2(-277.514, -187.262),
    Vector2(-289.696, -171.354),
    Vector2(-300.057, -179.224),
]

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ANNEESSENS_OSM_BUILDING_RUNTIME_CONFORMANCE_FAIL: %s" % message)
    quit(1)

func _close(a: float, b: float, tolerance: float = 0.001) -> bool:
    return absf(a - b) <= tolerance

func _run() -> void:
    if not FileAccess.file_exists(SOURCE_PATH):
        _fail("source missing")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("source JSON invalid")
        return

    var source_matches: Array[Dictionary] = []
    for raw: Variant in parsed.get("buildings", []):
        if typeof(raw) == TYPE_DICTIONARY and int(raw.get("osm_id", -1)) == TARGET_OSM_ID:
            source_matches.append(raw)
    if source_matches.size() != 1:
        _fail("source building 256376389 must exist exactly once; observed=%d" % source_matches.size())
        return
    var source_building: Dictionary = source_matches[0]
    if not _close(float(source_building.get("height", -1.0)), EXPECTED_HEIGHT):
        _fail("source height drift")
        return
    var source_footprint: Array = source_building.get("footprint", [])
    if source_footprint.size() != EXPECTED_FOOTPRINT.size():
        _fail("source footprint vertex count drift")
        return
    for i: int in range(EXPECTED_FOOTPRINT.size()):
        var raw_point: Variant = source_footprint[i]
        var observed := Vector2(float(raw_point[0]), float(raw_point[1]))
        if observed.distance_to(EXPECTED_FOOTPRINT[i]) > 0.001:
            _fail("source footprint drift at vertex %d" % i)
            return

    var builder := BUILDER_SCRIPT.new()
    builder.name = "AnneessensBuilderProbe"
    builder.data_path = SOURCE_PATH
    builder.max_buildings = 260
    builder.build_collisions = true
    root.add_child(builder)
    await process_frame
    await process_frame

    var buildings_root := builder.get_node_or_null("GeneratedBuildings")
    if buildings_root == null:
        _fail("GeneratedBuildings missing")
        return
    var candidates: Array[Node] = []
    for child: Node in buildings_root.get_children():
        if child is CSGPolygon3D and str(child.name).begins_with("Building_%d" % TARGET_OSM_ID):
            candidates.append(child)
    if candidates.size() != 1:
        _fail("runtime building 256376389 must exist exactly once; observed=%d" % candidates.size())
        return

    var solid := candidates[0] as CSGPolygon3D
    if not _close(solid.depth, EXPECTED_HEIGHT):
        _fail("runtime depth does not match source height")
        return
    if not _close(solid.rotation_degrees.x, -90.0):
        _fail("runtime extrusion rotation drift")
        return
    if Vector2(solid.position.x, solid.position.z).distance_to(EXPECTED_CENTER) > 0.001:
        _fail("runtime center drift")
        return
    if not _close(solid.position.y, EXPECTED_HEIGHT):
        _fail("runtime vertical placement drift")
        return
    if not solid.use_collision:
        _fail("runtime collision unexpectedly disabled")
        return
    if solid.polygon.size() != EXPECTED_FOOTPRINT.size():
        _fail("runtime polygon vertex count drift")
        return
    for i: int in range(EXPECTED_FOOTPRINT.size()):
        var expected_local: Vector2 = EXPECTED_FOOTPRINT[i] - EXPECTED_CENTER
        if solid.polygon[i].distance_to(expected_local) > 0.001:
            _fail("runtime polygon no longer source-derived at vertex %d" % i)
            return

    print("ANNEESSENS_OSM_BUILDING_RUNTIME_CONFORMANCE_OK: osm_id=256376389 source_unique=true runtime_unique=true source_height=14.0 runtime_depth=14.0 source_footprint_preserved=true runtime_center=(-285.4966,-185.4604) collision=true geometry_change_authorized=false camera_rescue_authorized=false visual_acceptance=false")
    quit(0)
