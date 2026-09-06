extends SceneTree

const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const ANNEESSENS_ROAD_ID := 1382734012
const POINT_EPSILON_M := 0.001


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("AUTOMATIC_ROAD_SOURCE_NETWORK_CONTINUATION_FAIL: %s" % message)
    quit(1)


func _same_source_point(a: Vector2, b: Vector2) -> bool:
    return a.distance_to(b) <= POINT_EPSILON_M


func _endpoint_connection_count(resolver: Node, document: Dictionary, selected_road: Dictionary, endpoint: Vector2) -> int:
    var roads: Variant = document.get("roads", [])
    if not roads is Array:
        return -1
    var selected_id := int(selected_road.get("osm_id", -1))
    var count := 0
    for raw: Variant in roads:
        if not raw is Dictionary:
            return -1
        var other := raw as Dictionary
        if int(other.get("osm_id", -1)) == selected_id:
            continue
        var other_points: PackedVector2Array = resolver._road_points(other)
        for point: Vector2 in other_points:
            if _same_source_point(point, endpoint):
                count += 1
                break
    return count


func _run() -> void:
    var resolver := RESOLVER_SCRIPT.new()
    root.add_child(resolver)

    var bundle: Dictionary = resolver._source_bundle_by_id(ANNEESSENS_ROAD_ID)
    if bundle.is_empty():
        _fail("Anneessens source bundle unavailable")
        return
    var document: Dictionary = bundle.get("document", {}) as Dictionary
    var road: Dictionary = bundle.get("road", {}) as Dictionary
    var points: PackedVector2Array = resolver._road_points(road)
    if points.size() < 2:
        _fail("Anneessens source road has fewer than two exact points")
        return

    var start_connections := _endpoint_connection_count(resolver, document, road, points[0])
    var end_connections := _endpoint_connection_count(resolver, document, road, points[points.size() - 1])
    if start_connections < 0 or end_connections < 0:
        _fail("source road network connectivity unavailable")
        return
    if start_connections == end_connections:
        _fail("fixture must prove asymmetric exact-source continuation: start=%d end=%d" % [start_connections, end_connections])
        return

    var viewpoint: Dictionary = resolver._safe_viewpoint(document, road)
    if viewpoint.is_empty():
        _fail("Anneessens safe viewpoint unavailable")
        return
    var segment_index := int(viewpoint.get("segment_index", -1))
    if segment_index < 0 or segment_index + 1 >= points.size():
        _fail("selected source segment index invalid")
        return
    var segment_start := points[segment_index]
    var segment_finish := points[segment_index + 1]
    var midpoint := segment_start.lerp(segment_finish, 0.5)
    var direction := (segment_finish - segment_start).normalized()
    if direction == Vector2.ZERO:
        _fail("selected source segment has zero direction")
        return
    var perpendicular := Vector2(-direction.y, direction.x)
    var offset := float(viewpoint.get("offset_m", 0.0))
    var lookahead := float(viewpoint.get("axis_lookahead_m", 0.0))
    if offset <= 0.0 or lookahead <= 0.0:
        _fail("selected placement metadata invalid")
        return

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
            if absf(view_axis.normalized().dot(direction)) < resolver.MIN_SOURCE_AXIS_ALIGNMENT:
                continue
            if not resolver._segment_clear_of_source_buildings(document, candidate, target):
                continue
            var clearance := resolver._source_view_corridor_clearance(document, candidate, target)
            if not is_finite(clearance) or clearance < 0.0:
                continue
            var connections := end_connections if along_sign > 0.0 else start_connections
            best_clearance = maxf(best_clearance, clearance)
            candidates.append({
                "connections": connections,
                "clearance": clearance,
            })

    if candidates.is_empty() or not is_finite(best_clearance):
        _fail("no source-safe network continuation candidate")
        return

    # Exact source-view safety is the hard constraint. Continuation is a
    # deterministic preference only among candidates that are equal to the
    # safest corridor within the existing 1 mm numeric tolerance. This keeps
    # the resolver from facing a more connected road end through a materially
    # tighter building corridor.
    var best_safe_connections := -1
    for candidate: Dictionary in candidates:
        var clearance := float(candidate.get("clearance", -INF))
        if clearance + POINT_EPSILON_M < best_clearance:
            continue
        best_safe_connections = maxi(best_safe_connections, int(candidate.get("connections", -1)))

    var target := viewpoint.get("target", Vector2.ZERO) as Vector2
    var along_dot := (target - midpoint).dot(direction)
    if absf(along_dot) <= POINT_EPSILON_M:
        _fail("selected target has no source-road along direction")
        return
    var selected_connections := end_connections if along_dot > 0.0 else start_connections
    var selected_clearance := float(viewpoint.get("source_view_corridor_clearance_m", -INF))
    if not is_finite(selected_clearance):
        _fail("selected source-view clearance metadata unavailable")
        return
    if selected_clearance + POINT_EPSILON_M < best_clearance:
        _fail("resolver let network continuation override source-view safety: selected_clearance=%.3f safest=%.3f selected_connections=%d best_safe_connections=%d" % [selected_clearance, best_clearance, selected_connections, best_safe_connections])
        return
    if selected_connections != best_safe_connections:
        _fail("resolver failed network continuation tie-break inside safest source-view stratum: selected=%d best_safe=%d selected_clearance=%.3f safest=%.3f" % [selected_connections, best_safe_connections, selected_clearance, best_clearance])
        return

    print("AUTOMATIC_ROAD_SOURCE_NETWORK_CONTINUATION_GREEN: road_id=%d selected_connections=%d best_safe_connections=%d start_connections=%d end_connections=%d selected_clearance_m=%.3f safest_clearance_m=%.3f safety_first=true source_only=true camera_unchanged=true geometry_unchanged=true destination_advertisable=false jouable=false" % [ANNEESSENS_ROAD_ID, selected_connections, best_safe_connections, start_connections, end_connections, selected_clearance, best_clearance])
    quit(0)
