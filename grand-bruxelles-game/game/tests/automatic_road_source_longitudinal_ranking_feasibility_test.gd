extends SceneTree

const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const ANNEESSENS_ROAD_ID := 1382734012
const MAIN_SCENE_PATH := "res://game/main.tscn"
const FOV_DEGREES := 69.0
const SPRING_LENGTH_M := 4.9
const WIDTH := 1280.0
const HEIGHT := 720.0
const RAY_LENGTH_M := 250.0
const SCREEN_SAMPLES: Array[float] = [760.0, 900.0, 1100.0]
const ANCHOR_FRACTIONS: Array[float] = [0.20, 0.35, 0.50, 0.65, 0.80]
const LOOKAHEADS_M: Array[float] = [12.0, 18.0, 22.0]

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("AUTOMATIC_ROAD_SOURCE_LONGITUDINAL_RANKING_FEASIBILITY_FAIL: %s" % message)
    quit(1)

func _camera_contract_current() -> bool:
    if not FileAccess.file_exists(MAIN_SCENE_PATH):
        return false
    var text := FileAccess.get_file_as_string(MAIN_SCENE_PATH)
    return text.contains("spring_length = 4.9") and text.contains("fov = 69.0")

func _ray_first_hit_distance(origin: Vector2, finish: Vector2, polygon: PackedVector2Array) -> float:
    if Geometry2D.is_point_in_polygon(origin, polygon):
        return 0.0
    var best := INF
    for index: int in range(polygon.size()):
        var hit: Variant = Geometry2D.segment_intersects_segment(origin, finish, polygon[index], polygon[(index + 1) % polygon.size()])
        if hit is Vector2:
            best = minf(best, origin.distance_to(hit as Vector2))
    return best

func _sample_hits(resolver: Node, document: Dictionary, spawn: Vector2, target: Vector2) -> int:
    var forward := (target - spawn).normalized()
    if forward == Vector2.ZERO:
        return -1
    var polygons: Array[PackedVector2Array] = resolver._source_building_polygons(document)
    if polygons.is_empty():
        return -1
    var camera_origin := spawn - forward * SPRING_LENGTH_M
    var tan_half_vertical := tan(deg_to_rad(FOV_DEGREES) * 0.5)
    var aspect := WIDTH / HEIGHT
    var hits := 0
    for sample_x: float in SCREEN_SAMPLES:
        var normalized_x := sample_x / WIDTH * 2.0 - 1.0
        var horizontal_angle := atan(normalized_x * tan_half_vertical * aspect)
        var ray_finish := camera_origin + forward.rotated(horizontal_angle).normalized() * RAY_LENGTH_M
        var sample_hit := INF
        for polygon: PackedVector2Array in polygons:
            sample_hit = minf(sample_hit, _ray_first_hit_distance(camera_origin, ray_finish, polygon))
        if is_finite(sample_hit):
            hits += 1
    return hits

func _run() -> void:
    if not _camera_contract_current():
        _fail("production camera contract drifted")
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

    var start_connections := resolver._source_endpoint_continuation_count(document, road, points[0])
    var end_connections := resolver._source_endpoint_continuation_count(document, road, points[points.size() - 1])
    if start_connections < 0 or end_connections < 0:
        _fail("source continuation unavailable")
        return

    var half_road := resolver._display_road_width(road) * 0.5
    var offsets: Array[float] = [half_road + 1.10, half_road + 2.00, half_road + 3.50, half_road + 5.00, half_road + 7.50]
    var candidates: Array[Dictionary] = []

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
                var continuation := end_connections if along_sign > 0.0 else start_connections
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
                            var view_clearance := resolver._source_view_corridor_clearance(document, spawn, target)
                            var spawn_clearance := resolver._source_building_clearance(document, spawn)
                            if view_clearance <= 0.0 or spawn_clearance <= 0.0:
                                continue
                            candidates.append({
                                "segment": segment_index,
                                "fraction": fraction,
                                "offset": offset,
                                "side": side,
                                "along": along_sign,
                                "lookahead": lookahead,
                                "spawn": spawn,
                                "target": target,
                                "view_clearance": view_clearance,
                                "continuation": continuation,
                                "spawn_clearance": spawn_clearance,
                            })

    if candidates.is_empty():
        _fail("no longitudinal candidate survives exact-source safety rails")
        return

    var max_view_clearance := -1.0
    for candidate: Dictionary in candidates:
        max_view_clearance = maxf(max_view_clearance, float(candidate["view_clearance"]))
    var safe_stratum: Array[Dictionary] = []
    for candidate: Dictionary in candidates:
        if float(candidate["view_clearance"]) + resolver.SOURCE_VIEW_CLEARANCE_EPSILON_M >= max_view_clearance:
            safe_stratum.append(candidate)

    var max_continuation := -1
    for candidate: Dictionary in safe_stratum:
        max_continuation = maxi(max_continuation, int(candidate["continuation"]))
    var continuation_stratum: Array[Dictionary] = []
    for candidate: Dictionary in safe_stratum:
        if int(candidate["continuation"]) == max_continuation:
            continuation_stratum.append(candidate)

    var selected: Dictionary = {}
    var best_spawn_clearance := -1.0
    for candidate: Dictionary in continuation_stratum:
        var clearance := float(candidate["spawn_clearance"])
        if clearance > best_spawn_clearance:
            best_spawn_clearance = clearance
            selected = candidate

    if selected.is_empty():
        _fail("frozen ranking produced no candidate")
        return
    var hits := _sample_hits(resolver, document, selected["spawn"] as Vector2, selected["target"] as Vector2)
    var diagnostic := "segment=%d fraction=%.2f offset=%.3f side=%+.0f along=%+.0f lookahead=%.1f view_clearance=%.3f continuation=%d spawn_clearance=%.3f hits=%d candidates=%d safe_stratum=%d continuation_stratum=%d" % [int(selected["segment"]), float(selected["fraction"]), float(selected["offset"]), float(selected["side"]), float(selected["along"]), float(selected["lookahead"]), float(selected["view_clearance"]), int(selected["continuation"]), float(selected["spawn_clearance"]), hits, candidates.size(), safe_stratum.size(), continuation_stratum.size()]
    if hits < 1 or hits > 2:
        _fail("expanded longitudinal set still resolves to unbalanced player context under frozen ranking: %s camera_unchanged=true source_only=true" % diagnostic)
        return

    print("AUTOMATIC_ROAD_SOURCE_LONGITUDINAL_RANKING_FEASIBILITY_GREEN: road_id=%d %s camera_unchanged=true source_only=true geometry_unchanged=true resolver_unchanged=true destination_advertisable=false jouable=false" % [ANNEESSENS_ROAD_ID, diagnostic])
    quit(0)
