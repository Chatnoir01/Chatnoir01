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
const ANCHOR_FRACTIONS: Array[float] = [0.20, 0.35, 0.50, 0.65, 0.80]
const LOOKAHEADS_M: Array[float] = [12.0, 18.0, 22.0]


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("AUTOMATIC_ROAD_SOURCE_URBAN_CONTEXT_LONGITUDINAL_COVERAGE_FAIL: %s" % message)
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
    var hits := 0
    var nearest_hit_m := INF
    var distances: Array[String] = []
    for sample_x: float in SCREEN_SAMPLES:
        var normalized_x := sample_x / WIDTH * 2.0 - 1.0
        var horizontal_angle := atan(normalized_x * tan_half_vertical * aspect)
        var ray_finish := camera_origin + forward.rotated(horizontal_angle).normalized() * RAY_LENGTH_M
        var sample_distance := INF
        for polygon: PackedVector2Array in polygons:
            sample_distance = minf(sample_distance, _ray_first_hit_distance(camera_origin, ray_finish, polygon))
        if is_finite(sample_distance):
            hits += 1
            nearest_hit_m = minf(nearest_hit_m, sample_distance)
            distances.append("%.3f" % sample_distance)
        else:
            distances.append("none")
    return {"hits": hits, "nearest_hit_m": nearest_hit_m, "distances": ",".join(distances)}


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

    var half_road := resolver._display_road_width(road) * 0.5
    var offsets: Array[float] = [half_road + 1.10, half_road + 2.00, half_road + 3.50, half_road + 5.00, half_road + 7.50]
    var source_safe_count := 0
    var balanced_context_count := 0
    var best_hits := -1
    var diagnostics: Array[String] = []

    for segment_index: int in range(points.size() - 1):
        var start := points[segment_index]
        var finish := points[segment_index + 1]
        var segment := finish - start
        var segment_length := segment.length()
        if segment_length < 8.0:
            continue
        var direction := segment / segment_length
        var perpendicular := Vector2(-direction.y, direction.x)

        for fraction: float in ANCHOR_FRACTIONS:
            var anchor_distance := segment_length * fraction
            var anchor := start + direction * anchor_distance
            for along_sign: float in [1.0, -1.0]:
                var available_forward := (segment_length - anchor_distance) if along_sign > 0.0 else anchor_distance
                for lookahead: float in LOOKAHEADS_M:
                    if lookahead > available_forward:
                        continue
                    var target := anchor + direction * lookahead * along_sign
                    if resolver._point_inside_any_source_building(document, target):
                        continue
                    for offset: float in offsets:
                        for side: float in [1.0, -1.0]:
                            var spawn := anchor + perpendicular * offset * side
                            if absf(spawn.x) > resolver.MAX_WORLD_ABS_M or absf(spawn.y) > resolver.MAX_WORLD_ABS_M:
                                continue
                            if resolver._point_inside_any_source_building(document, spawn):
                                continue
                            var axis := target - spawn
                            if axis == Vector2.ZERO or absf(axis.normalized().dot(direction)) < resolver.MIN_SOURCE_AXIS_ALIGNMENT:
                                continue
                            if not resolver._segment_clear_of_source_buildings(document, spawn, target):
                                continue
                            var context := _sampled_context(resolver, document, spawn, target)
                            if context.is_empty():
                                _fail("source building context unavailable")
                                return
                            source_safe_count += 1
                            var hits := int(context.get("hits", -1))
                            best_hits = maxi(best_hits, hits)
                            if hits >= 1 and hits <= 2:
                                balanced_context_count += 1
                                diagnostics.append("segment=%d fraction=%.2f offset=%.3f side=%+.0f along=%+.0f lookahead=%.1f hits=%d nearest=%s distances=%s" % [segment_index, fraction, offset, side, along_sign, lookahead, hits, ("%.3f" % float(context.get("nearest_hit_m", INF))) if is_finite(float(context.get("nearest_hit_m", INF))) else "none", str(context.get("distances", ""))])

    if source_safe_count < 1:
        _fail("no longitudinal candidate survives exact-source safety rails")
        return
    if balanced_context_count < 1:
        _fail("no 1-2-hit player context exists anywhere on sampled exact Anneessens road geometry; source_safe_candidates=%d best_hits=%d source_only=true camera_unchanged=true geometry_unchanged=true" % [source_safe_count, best_hits])
        return

    print("AUTOMATIC_ROAD_SOURCE_URBAN_CONTEXT_LONGITUDINAL_COVERAGE_GREEN: road_id=%d source_safe_candidates=%d balanced_context_candidates=%d diagnostics=%s source_only=true camera_unchanged=true geometry_unchanged=true resolver_unchanged=true destination_advertisable=false jouable=false" % [ANNEESSENS_ROAD_ID, source_safe_count, balanced_context_count, " | ".join(diagnostics)])
    quit(0)
