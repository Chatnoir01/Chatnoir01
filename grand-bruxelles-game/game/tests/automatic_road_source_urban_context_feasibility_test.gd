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

    var viewpoint: Dictionary = resolver._safe_viewpoint(document, road)
    if viewpoint.is_empty():
        _fail("current safe-viewpoint ranking produced no candidate")
        return
    var spawn := viewpoint.get("spawn", Vector2.ZERO) as Vector2
    var raw_target := viewpoint.get("target", Vector2.ZERO) as Vector2
    if spawn == Vector2.ZERO or raw_target == Vector2.ZERO or spawn == raw_target:
        _fail("safe viewpoint metadata invalid")
        return

    var raw_clearance := resolver._source_view_corridor_clearance(document, spawn, raw_target)
    if not is_finite(raw_clearance) or raw_clearance <= 0.0:
        _fail("raw safe viewpoint lost exact-source corridor clearance")
        return

    var effective: Dictionary = resolver._corridor_oriented_target(document, spawn, raw_target)
    var effective_target := effective.get("target", Vector2.ZERO) as Vector2
    if effective_target == Vector2.ZERO or effective_target == spawn:
        _fail("effective heading unavailable")
        return
    if not resolver._segment_clear_of_source_buildings(document, spawn, effective_target):
        _fail("effective heading is not exact-source clear")
        return
    var effective_clearance := resolver._source_view_corridor_clearance(document, spawn, effective_target)
    if not is_finite(effective_clearance) or effective_clearance + CLEARANCE_EPSILON_M < resolver.PLAYER_BODY_CLEARANCE_M:
        _fail("effective heading violates frozen player physical clearance")
        return

    var context := _sampled_context(resolver, document, spawn, effective_target)
    if context.is_empty():
        _fail("effective source-building context unavailable")
        return
    var hits := int(context.get("hits", -1))

    # Keep the frozen player-context witness unchanged: exactly 1-2 sampled
    # source-building rays. This gate validates the effective arrival heading;
    # it does not weaken the raw spawn safety ranking or camera contract.
    if hits < 1 or hits > 2:
        _fail("effective heading provides no frozen 1-2-hit player context: hits=%d nearest=%s raw_target=%s effective_target=%s anchor_oriented=%s distances=%s" % [hits, ("%.3f" % float(context.get("nearest_hit_m", INF))) if is_finite(float(context.get("nearest_hit_m", INF))) else "none", str(raw_target), str(effective_target), str(bool(effective.get("anchor_oriented", false))), str(context.get("distances", ""))])
        return

    print("AUTOMATIC_ROAD_SOURCE_URBAN_CONTEXT_FEASIBILITY_GREEN: road_id=%d hits=%d raw_clearance_m=%.3f effective_clearance_m=%.3f anchor_oriented=%s nearest_hit_m=%s distances=%s source_only=true camera_unchanged=true geometry_unchanged=true spawn_ranking_unchanged=true destination_advertisable=false jouable=false" % [ANNEESSENS_ROAD_ID, hits, raw_clearance, effective_clearance, str(bool(effective.get("anchor_oriented", false))), ("%.3f" % float(context.get("nearest_hit_m", INF))) if is_finite(float(context.get("nearest_hit_m", INF))) else "none", str(context.get("distances", ""))])
    quit(0)
