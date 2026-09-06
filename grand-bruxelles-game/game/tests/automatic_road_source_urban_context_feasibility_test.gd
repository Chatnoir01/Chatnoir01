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
const CLEARANCE_EPSILON_M := 0.001


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("AUTOMATIC_ROAD_SOURCE_URBAN_CONTEXT_FEASIBILITY_FAIL: %s" % message)
    quit(1)


func _production_camera_contract_is_current() -> bool:
    if not FileAccess.file_exists(MAIN_SCENE_PATH):
        return false
    var scene_text := FileAccess.get_file_as_string(MAIN_SCENE_PATH)
    return scene_text.contains("spring_length = 4.9") and scene_text.contains("fov = 69.0")


func _ray_first_hit_distance(origin: Vector2, finish: Vector2, polygon: PackedVector2Array) -> float:
    if Geometry2D.is_point_in_polygon(origin, polygon):
        return 0.0
    var best := INF
    for index: int in range(polygon.size()):
        var intersection: Variant = Geometry2D.segment_intersects_segment(origin, finish, polygon[index], polygon[(index + 1) % polygon.size()])
        if intersection is Vector2:
            best = minf(best, origin.distance_to(intersection as Vector2))
    return best


func _sampled_context(resolver: Node, document: Dictionary, spawn: Vector2, target: Vector2) -> Dictionary:
    var forward := (target - spawn).normalized()
    if forward == Vector2.ZERO:
        return {}
    var polygons: Array[PackedVector2Array] = resolver._source_building_polygons(document)
    if polygons.is_empty():
        return {}
    var camera_origin := spawn - forward * PRODUCTION_SPRING_LENGTH_M
    var aspect := WIDTH / HEIGHT
    var tan_half_vertical := tan(deg_to_rad(PRODUCTION_FOV_DEGREES) * 0.5)
    var hit_count := 0
    var nearest_hit_m := INF
    var hit_distances: Array[String] = []
    for sample_x: float in SCREEN_SAMPLES:
        var normalized_x := sample_x / WIDTH * 2.0 - 1.0
        var horizontal_angle := atan(normalized_x * tan_half_vertical * aspect)
        var ray_finish := camera_origin + forward.rotated(horizontal_angle).normalized() * RAY_LENGTH_M
        var sample_distance := INF
        for polygon: PackedVector2Array in polygons:
            sample_distance = minf(sample_distance, _ray_first_hit_distance(camera_origin, ray_finish, polygon))
        if is_finite(sample_distance):
            hit_count += 1
            nearest_hit_m = minf(nearest_hit_m, sample_distance)
            hit_distances.append("%.3f" % sample_distance)
        else:
            hit_distances.append("none")
    return {
        "hits": hit_count,
        "nearest_hit_m": nearest_hit_m,
        "distances": ",".join(hit_distances),
    }


func _run() -> void:
    if not _production_camera_contract_is_current():
        _fail("production camera contract drifted from 69-degree / 4.9 m witness")
        return

    var resolver := RESOLVER_SCRIPT.new()
    root.add_child(resolver)
    var bundle: Dictionary = resolver._source_bundle_by_id(ANNEESSENS_ROAD_ID)
    if bundle.is_empty():
        _fail("Anneessens exact source bundle unavailable")
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
        _fail("no eligible exact-source segment")
        return

    var start_connections := resolver._source_endpoint_continuation_count(document, road, points[0])
    var end_connections := resolver._source_endpoint_continuation_count(document, road, points[points.size() - 1])
    if start_connections < 0 or end_connections < 0:
        _fail("exact-source network continuation unavailable")
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
    var eligible_count := 0
    var acceptable_count := 0
    var acceptable_offsets: Array[String] = []
    var diagnostics: Array[String] = []

    for offset: float in offsets:
        var required_lookahead := offset * 2.10
        var lookahead := minf(22.0, best_length * 0.5)
        if lookahead < required_lookahead:
            diagnostics.append("offset=%.3f skipped=lookahead" % offset)
            continue

        var offset_candidates: Array[Dictionary] = []
        var safest_corridor_clearance := -INF
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
                var corridor_clearance := resolver._source_view_corridor_clearance(document, spawn, target)
                if not is_finite(corridor_clearance) or corridor_clearance < 0.0:
                    continue
                var continuation_count := end_connections if along_sign > 0.0 else start_connections
                var context := _sampled_context(resolver, document, spawn, target)
                if context.is_empty():
                    _fail("source building context unavailable")
                    return
                safest_corridor_clearance = maxf(safest_corridor_clearance, corridor_clearance)
                offset_candidates.append({
                    "side": side,
                    "along_sign": along_sign,
                    "corridor_clearance": corridor_clearance,
                    "continuation_count": continuation_count,
                    "context": context,
                })

        if offset_candidates.is_empty() or not is_finite(safest_corridor_clearance):
            diagnostics.append("offset=%.3f eligible=0" % offset)
            continue

        var max_continuation := -1
        for candidate: Dictionary in offset_candidates:
            var clearance := float(candidate.get("corridor_clearance", -INF))
            if clearance + CLEARANCE_EPSILON_M < safest_corridor_clearance:
                continue
            max_continuation = maxi(max_continuation, int(candidate.get("continuation_count", -1)))

        var offset_eligible := 0
        var offset_acceptable := 0
        for candidate: Dictionary in offset_candidates:
            var clearance := float(candidate.get("corridor_clearance", -INF))
            var continuation_count := int(candidate.get("continuation_count", -1))
            if clearance + CLEARANCE_EPSILON_M < safest_corridor_clearance or continuation_count != max_continuation:
                continue
            var context: Dictionary = candidate.get("context", {}) as Dictionary
            var hits := int(context.get("hits", -1))
            offset_eligible += 1
            eligible_count += 1
            if hits >= 1 and hits <= 2:
                offset_acceptable += 1
                acceptable_count += 1
            diagnostics.append("offset=%.3f side=%+.0f along=%+.0f eligible=true hits=%d nearest=%s clearance=%.3f continuation=%d distances=%s" % [offset, float(candidate.get("side", 0.0)), float(candidate.get("along_sign", 0.0)), hits, ("%.3f" % float(context.get("nearest_hit_m", INF))) if is_finite(float(context.get("nearest_hit_m", INF))) else "none", clearance, continuation_count, str(context.get("distances", ""))])
        if offset_acceptable > 0:
            acceptable_offsets.append("%.3f" % offset)
        if offset_eligible == 0:
            diagnostics.append("offset=%.3f eligible=0 after_clearance_and_continuation" % offset)

    if eligible_count < 1:
        _fail("no candidate survives current per-offset clearance + continuation rails")
        return
    if acceptable_count < 1:
        _fail("configured offsets provide no 1-2-hit player context within current per-offset clearance + continuation rails: %s" % " | ".join(diagnostics))
        return

    print("AUTOMATIC_ROAD_SOURCE_URBAN_CONTEXT_FEASIBILITY_GREEN: road_id=%d eligible_candidates=%d acceptable_candidates=%d acceptable_offsets=%s diagnostics=%s source_only=true camera_unchanged=true geometry_unchanged=true resolver_ranking_unchanged=true destination_advertisable=false jouable=false" % [ANNEESSENS_ROAD_ID, eligible_count, acceptable_count, ",".join(acceptable_offsets), " | ".join(diagnostics)])
    quit(0)
