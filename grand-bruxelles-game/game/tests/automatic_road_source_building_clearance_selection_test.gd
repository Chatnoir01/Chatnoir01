extends SceneTree

const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const ANNEESSENS_ROAD_ID := 1382734012
const EPSILON_M := 0.001


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("AUTOMATIC_ROAD_SOURCE_BUILDING_CLEARANCE_FAIL: %s" % message)
    quit(1)


func _point_segment_distance(point: Vector2, start: Vector2, finish: Vector2) -> float:
    var segment := finish - start
    var length_sq := segment.length_squared()
    if length_sq <= 0.0000001:
        return point.distance_to(start)
    var t := clampf((point - start).dot(segment) / length_sq, 0.0, 1.0)
    return point.distance_to(start + segment * t)


func _source_building_clearance(resolver: Node, document: Dictionary, point: Vector2) -> float:
    if resolver._point_inside_any_source_building(document, point):
        return 0.0
    var best := INF
    for polygon: PackedVector2Array in resolver._source_building_polygons(document):
        for index: int in range(polygon.size()):
            best = minf(best, _point_segment_distance(point, polygon[index], polygon[(index + 1) % polygon.size()]))
    return best


func _run() -> void:
    var resolver := RESOLVER_SCRIPT.new()
    root.add_child(resolver)

    var bundle: Dictionary = resolver._source_bundle_by_id(ANNEESSENS_ROAD_ID)
    if bundle.is_empty():
        _fail("Anneessens source bundle unavailable")
        return
    var document: Dictionary = bundle.get("document", {}) as Dictionary
    var road: Dictionary = bundle.get("road", {}) as Dictionary
    var viewpoint: Dictionary = resolver._safe_viewpoint(document, road)
    if viewpoint.is_empty():
        _fail("Anneessens safe viewpoint unavailable")
        return

    var points: PackedVector2Array = resolver._road_points(road)
    var segment_index := int(viewpoint.get("segment_index", -1))
    if segment_index < 0 or segment_index + 1 >= points.size():
        _fail("selected segment index invalid")
        return
    var start := points[segment_index]
    var finish := points[segment_index + 1]
    var midpoint := start.lerp(finish, 0.5)
    var direction := (finish - start).normalized()
    if direction == Vector2.ZERO:
        _fail("selected source segment has zero direction")
        return
    var perpendicular := Vector2(-direction.y, direction.x)
    var offset := float(viewpoint.get("offset_m", 0.0))
    var side := float(viewpoint.get("side", 0.0))
    if offset <= 0.0 or absf(absf(side) - 1.0) > 0.000001:
        _fail("selected lateral placement metadata invalid")
        return

    var selected := viewpoint.get("spawn", Vector2.ZERO) as Vector2
    var opposite := midpoint - perpendicular * offset * side
    var target := viewpoint.get("target", Vector2.ZERO) as Vector2

    if resolver._point_inside_any_source_building(document, opposite):
        print("AUTOMATIC_ROAD_SOURCE_BUILDING_CLEARANCE_GREEN: opposite_side_source_blocked=true")
        quit(0)
        return
    if not resolver._segment_clear_of_source_buildings(document, opposite, target):
        print("AUTOMATIC_ROAD_SOURCE_BUILDING_CLEARANCE_GREEN: opposite_side_sightline_blocked=true")
        quit(0)
        return

    var selected_clearance := _source_building_clearance(resolver, document, selected)
    var opposite_clearance := _source_building_clearance(resolver, document, opposite)
    if not is_finite(selected_clearance) or not is_finite(opposite_clearance):
        _fail("source building clearance could not be measured")
        return

    if selected_clearance + EPSILON_M < opposite_clearance:
        _fail("resolver selected lower-clearance side: selected=%.3f m opposite=%.3f m side=%.1f" % [selected_clearance, opposite_clearance, side])
        return

    print("AUTOMATIC_ROAD_SOURCE_BUILDING_CLEARANCE_GREEN: road_id=%d selected_clearance_m=%.3f opposite_clearance_m=%.3f source_only=true camera_unchanged=true geometry_unchanged=true destination_advertisable=false jouable=false" % [ANNEESSENS_ROAD_ID, selected_clearance, opposite_clearance])
    quit(0)
