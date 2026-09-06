extends SceneTree

const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const ANNEESSENS_ROAD_ID := 1382734012
const MAIN_SCENE_PATH := "res://game/main.tscn"
const PRODUCTION_FOV_DEGREES := 69.0
const PRODUCTION_SPRING_LENGTH_M := 4.9
const WIDTH := 1280.0
const HEIGHT := 720.0
const RAY_LENGTH_M := 250.0
const SCREEN_SAMPLES: Array[float] = [760.0, 900.0, 1100.0]
const EPSILON_M := 0.001


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("AUTOMATIC_ROAD_SOURCE_URBAN_CONTEXT_OFFSET_DIAGNOSTIC_FAIL: %s" % message)
    quit(1)


func _production_camera_contract_is_current() -> bool:
    if not FileAccess.file_exists(MAIN_SCENE_PATH):
        return false
    var scene_text := FileAccess.get_file_as_string(MAIN_SCENE_PATH)
    return scene_text.contains("spring_length = 4.9") and scene_text.contains("fov = 69.0")


func _ray_hits_polygon(origin: Vector2, finish: Vector2, polygon: PackedVector2Array) -> bool:
    if Geometry2D.is_point_in_polygon(origin, polygon):
        return true
    for index: int in range(polygon.size()):
        if Geometry2D.segment_intersects_segment(origin, finish, polygon[index], polygon[(index + 1) % polygon.size()]) != null:
            return true
    return false


func _sampled_hits(resolver: Node, document: Dictionary, spawn: Vector2, target: Vector2) -> int:
    var forward := (target - spawn).normalized()
    if forward == Vector2.ZERO:
        return -1
    var polygons: Array[PackedVector2Array] = resolver._source_building_polygons(document)
    if polygons.is_empty():
        return -1
    var camera_origin := spawn - forward * PRODUCTION_SPRING_LENGTH_M
    var aspect := WIDTH / HEIGHT
    var tan_half_vertical := tan(deg_to_rad(PRODUCTION_FOV_DEGREES) * 0.5)
    var hit_count := 0
    for sample_x: float in SCREEN_SAMPLES:
        var normalized_x := sample_x / WIDTH * 2.0 - 1.0
        var horizontal_angle := atan(normalized_x * tan_half_vertical * aspect)
        var ray_finish := camera_origin + forward.rotated(horizontal_angle).normalized() * RAY_LENGTH_M
        var hit := false
        for polygon: PackedVector2Array in polygons:
            if _ray_hits_polygon(camera_origin, ray_finish, polygon):
                hit = true
                break
        if hit:
            hit_count += 1
    return hit_count


func _run() -> void:
    if not _production_camera_contract_is_current():
        _fail("production camera contract drifted from 69-degree / 4.9 m witness")
        return

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
        _fail("Anneessens source road invalid")
        return

    var best_index := -1
    var best_length := -1.0
    for index: int in range(points.size() - 1):
        var length := points[index].distance_to(points[index + 1])
        if length > best_length:
            best_length = length
            best_index = index
    if best_index < 0 or best_length < 1.0:
        _fail("no eligible source segment")
        return

    var start_connections := resolver._source_endpoint_continuation_count(document, road, points[0])
    var end_connections := resolver._source_endpoint_continuation_count(document, road, points[points.size() - 1])
    if start_connections < 0 or end_connections < 0:
        _fail("source continuation unavailable")
        return

    var start := points[best_index]
    var finish := points[best_index + 1]
    var midpoint := start.lerp(finish, 0.5)
    var direction := (finish - start).normalized()
    if direction == Vector2.ZERO:
        _fail("source segment direction is zero")
        return
    var perpendicular := Vector2(-direction.y, direction.x)
    var half_road := resolver._display_road_width(road) * 0.5
    var offsets: Array[float] = [half_road + 1.10, half_road + 2.00, half_road + 3.50, half_road + 5.00, half_road + 7.50]
    var diagnostics: Array[String] = []
    var safe_candidate_count := 0
    var acceptable_context_count := 0

    for offset: float in offsets:
        var required_lookahead := offset * 2.10
        var lookahead := minf(22.0, best_length * 0.5)
        if lookahead < required_lookahead:
            diagnostics.append("offset=%.3f skipped=lookahead" % offset)
            continue
        var candidates: Array[Dictionary] = []
        var safest_clearance := -INF
        for side: float in [1.0, -1.0]:
            var spawn := midpoint + perpendicular * offset * side
            if absf(spawn.x) > resolver.MAX_WORLD_ABS_M or absf(spawn.y) > resolver.MAX_WORLD_ABS_M:
                continue
            if resolver._point_inside_any_source_building(document, spawn):
                continue
            for along_sign: float in [1.0, -1.0]:
                var target := midpoint + direction * lookahead * along_sign
                if absf(target.x) > resolver.MAX_WORLD_ABS_M or absf(target.y) > resolver.MAX_WORLD_ABS_M:
                    continue
                if resolver._point_inside_any_source_building(document, target):
                    continue
                var axis := target - spawn
                if axis == Vector2.ZERO or absf(axis.normalized().dot(direction)) < resolver.MIN_SOURCE_AXIS_ALIGNMENT:
                    continue
                if not resolver._segment_clear_of_source_buildings(document, spawn, target):
                    continue
                var clearance := resolver._source_view_corridor_clearance(document, spawn, target)
                if not is_finite(clearance) or clearance < 0.0:
                    continue
                var continuation := end_connections if along_sign > 0.0 else start_connections
                var hits := _sampled_hits(resolver, document, spawn, target)
                safest_clearance = maxf(safest_clearance, clearance)
                candidates.append({"spawn": spawn, "target": target, "clearance": clearance, "continuation": continuation, "hits": hits})
        if candidates.is_empty() or not is_finite(safest_clearance):
            diagnostics.append("offset=%.3f candidates=0" % offset)
            continue
        var best_continuation := -1
        for candidate: Dictionary in candidates:
            if float(candidate.get("clearance", -INF)) + EPSILON_M >= safest_clearance:
                best_continuation = maxi(best_continuation, int(candidate.get("continuation", -1)))
        var offset_entries: Array[String] = []
        for candidate: Dictionary in candidates:
            if float(candidate.get("clearance", -INF)) + EPSILON_M < safest_clearance:
                continue
            if int(candidate.get("continuation", -1)) != best_continuation:
                continue
            safe_candidate_count += 1
            var hits := int(candidate.get("hits", -1))
            if hits >= 1 and hits <= 2:
                acceptable_context_count += 1
            offset_entries.append("hits=%d clearance=%.3f cont=%d spawn=%s target=%s" % [hits, float(candidate.get("clearance", 0.0)), best_continuation, str(candidate.get("spawn", Vector2.ZERO)), str(candidate.get("target", Vector2.ZERO))])
        diagnostics.append("offset=%.3f safest=%.3f best_cont=%d [%s]" % [offset, safest_clearance, best_continuation, "; ".join(offset_entries)])

    if safe_candidate_count < 1:
        _fail("no safety+continuation candidate across configured offsets: %s" % " | ".join(diagnostics))
        return

    print("AUTOMATIC_ROAD_SOURCE_URBAN_CONTEXT_OFFSET_DIAGNOSTIC_GREEN: road_id=%d safe_candidates=%d acceptable_context_candidates=%d diagnostics=%s source_only=true camera_unchanged=true geometry_unchanged=true runtime_unchanged=true promotion=false" % [ANNEESSENS_ROAD_ID, safe_candidate_count, acceptable_context_count, " | ".join(diagnostics)])
    quit(0)
