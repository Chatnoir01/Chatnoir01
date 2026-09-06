extends SceneTree

const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const ANNEESSENS_ROAD_ID := 1382734012
const EPSILON_M := 0.001


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("AUTOMATIC_ROAD_SOURCE_VIEW_CORRIDOR_CLEARANCE_FAIL: %s" % message)
    quit(1)


func _point_segment_distance(point: Vector2, start: Vector2, finish: Vector2) -> float:
    var segment := finish - start
    var length_sq := segment.length_squared()
    if length_sq <= 0.0000001:
        return point.distance_to(start)
    var t := clampf((point - start).dot(segment) / length_sq, 0.0, 1.0)
    return point.distance_to(start + segment * t)


func _segment_segment_distance(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> float:
    if Geometry2D.segment_intersects_segment(a0, a1, b0, b1) != null:
        return 0.0
    return minf(
        minf(_point_segment_distance(a0, b0, b1), _point_segment_distance(a1, b0, b1)),
        minf(_point_segment_distance(b0, a0, a1), _point_segment_distance(b1, a0, a1))
    )


func _view_corridor_clearance(resolver: Node, document: Dictionary, start: Vector2, finish: Vector2) -> float:
    if not resolver._segment_clear_of_source_buildings(document, start, finish):
        return 0.0
    var best := INF
    for polygon: PackedVector2Array in resolver._source_building_polygons(document):
        for index: int in range(polygon.size()):
            best = minf(best, _segment_segment_distance(start, finish, polygon[index], polygon[(index + 1) % polygon.size()]))
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
    var lookahead := float(viewpoint.get("axis_lookahead_m", 0.0))
    if offset <= 0.0 or lookahead <= 0.0:
        _fail("selected placement metadata invalid")
        return

    var start_connections := resolver._source_endpoint_continuation_count(document, road, points[0])
    var end_connections := resolver._source_endpoint_continuation_count(document, road, points[points.size() - 1])
    if start_connections < 0 or end_connections < 0:
        _fail("source network continuation metadata unavailable")
        return

    var selected_spawn := viewpoint.get("spawn", Vector2.ZERO) as Vector2
    var selected_target := viewpoint.get("target", Vector2.ZERO) as Vector2
    var selected_clearance := _view_corridor_clearance(resolver, document, selected_spawn, selected_target)
    var selected_continuation := int(viewpoint.get("source_network_continuation_count", -1))
    if not is_finite(selected_clearance) or selected_continuation < 0:
        _fail("selected source view metadata unavailable")
        return

    # Safety is the hard constraint. First find the globally safest valid
    # source-view corridor at the production-selected offset/lookahead. Only
    # candidates within the existing 1 mm numeric epsilon of that maximum may
    # compete on source-network continuation. This prevents urban-context
    # preference from overriding a materially safer source-backed sightline.
    var best_clearance := -INF
    var candidates: Array[Dictionary] = []
    for side: float in [1.0, -1.0]:
        var candidate := midpoint + perpendicular * offset * side
        if resolver._point_inside_any_source_building(document, candidate):
            continue
        for along_sign: float in [1.0, -1.0]:
            var target := midpoint + direction * lookahead * along_sign
            if resolver._point_inside_any_source_building(document, target):
                continue
            var view_axis := target - candidate
            if view_axis == Vector2.ZERO:
                continue
            var axis_alignment := absf(view_axis.normalized().dot(direction))
            if axis_alignment < resolver.MIN_SOURCE_AXIS_ALIGNMENT:
                continue
            if not resolver._segment_clear_of_source_buildings(document, candidate, target):
                continue
            var continuation_count := end_connections if along_sign > 0.0 else start_connections
            var clearance := _view_corridor_clearance(resolver, document, candidate, target)
            if not is_finite(clearance) or clearance < 0.0:
                continue
            best_clearance = maxf(best_clearance, clearance)
            candidates.append({
                "side": side,
                "along": along_sign,
                "clearance": clearance,
                "continuation": continuation_count,
            })

    if candidates.is_empty() or not is_finite(best_clearance) or best_clearance < 0.0:
        _fail("no valid source view corridor candidate")
        return

    var best_safe_continuation := -1
    var best_safe_side := 0.0
    var best_safe_along := 0.0
    for raw_candidate: Dictionary in candidates:
        var clearance := float(raw_candidate.get("clearance", -INF))
        if clearance + EPSILON_M < best_clearance:
            continue
        var continuation := int(raw_candidate.get("continuation", -1))
        if continuation > best_safe_continuation:
            best_safe_continuation = continuation
            best_safe_side = float(raw_candidate.get("side", 0.0))
            best_safe_along = float(raw_candidate.get("along", 0.0))

    if selected_clearance + EPSILON_M < best_clearance:
        _fail("resolver let continuation override safer source-view corridor: selected=%.3f m safest=%.3f m selected_continuation=%d safe_continuation=%d safe_side=%.1f safe_along=%.1f" % [selected_clearance, best_clearance, selected_continuation, best_safe_continuation, best_safe_side, best_safe_along])
        return
    if selected_continuation != best_safe_continuation:
        _fail("resolver failed continuation tie-break inside safest source-view stratum: selected=%d best_safe=%d clearance=%.3f m safest=%.3f m" % [selected_continuation, best_safe_continuation, selected_clearance, best_clearance])
        return

    print("AUTOMATIC_ROAD_SOURCE_VIEW_CORRIDOR_CLEARANCE_GREEN: road_id=%d selected_clearance_m=%.3f safest_clearance_m=%.3f selected_continuation=%d best_safe_continuation=%d safety_first=true source_only=true camera_unchanged=true geometry_unchanged=true destination_advertisable=false jouable=false" % [ANNEESSENS_ROAD_ID, selected_clearance, best_clearance, selected_continuation, best_safe_continuation])
    quit(0)
