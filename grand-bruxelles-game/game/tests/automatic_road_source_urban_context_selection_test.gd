extends SceneTree

const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const ANNEESSENS_ROAD_ID := 1382734012
const MAIN_SCENE_PATH := "res://game/main.tscn"
const PRODUCTION_FOV_DEGREES := 69.0
const PRODUCTION_SPRING_LENGTH_M := 4.9
const EPSILON_M := 0.001
const WIDTH := 1280.0
const HEIGHT := 720.0
const RAY_LENGTH_M := 250.0
const SCREEN_SAMPLES: Array[float] = [760.0, 900.0, 1100.0]


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("AUTOMATIC_ROAD_SOURCE_URBAN_CONTEXT_FAIL: %s" % message)
    quit(1)


func _production_camera_contract_is_current() -> bool:
    if not FileAccess.file_exists(MAIN_SCENE_PATH):
        return false
    var scene_text := FileAccess.get_file_as_string(MAIN_SCENE_PATH)
    var spring_block := "[node name=\"SpringArm3D\" type=\"SpringArm3D\" parent=\"Player/CameraPivot\"]\nspring_length = 4.9"
    var camera_block := "[node name=\"Camera3D\" type=\"Camera3D\" parent=\"Player/CameraPivot/SpringArm3D\"]\ncurrent = true\nfov = 69.0"
    return scene_text.contains(spring_block) and scene_text.contains(camera_block)


func _ray_hits_polygon(origin: Vector2, finish: Vector2, polygon: PackedVector2Array) -> bool:
    if Geometry2D.is_point_in_polygon(origin, polygon):
        return true
    for index: int in range(polygon.size()):
        if Geometry2D.segment_intersects_segment(origin, finish, polygon[index], polygon[(index + 1) % polygon.size()]) != null:
            return true
    return false


func _sampled_source_building_hits(resolver: Node, document: Dictionary, spawn: Vector2, target: Vector2, vertical_fov_degrees: float, spring_length_m: float) -> int:
    var forward := (target - spawn).normalized()
    if forward == Vector2.ZERO:
        return -1
    # Production player camera is centered on the spring arm and unchanged by
    # direct-entry. In XZ, its source-space origin is therefore the selected
    # spawn moved backward by the production spring length. Center-row screen
    # samples use the exact witness viewport and vertical FOV.
    var camera_origin := spawn - forward * spring_length_m
    var aspect := WIDTH / HEIGHT
    var tan_half_vertical := tan(deg_to_rad(vertical_fov_degrees) * 0.5)
    var polygons: Array[PackedVector2Array] = resolver._source_building_polygons(document)
    if polygons.is_empty():
        return -1
    var hit_count := 0
    for sample_x: float in SCREEN_SAMPLES:
        var normalized_x := sample_x / WIDTH * 2.0 - 1.0
        var horizontal_angle := atan(normalized_x * tan_half_vertical * aspect)
        var ray_direction := forward.rotated(horizontal_angle).normalized()
        var ray_finish := camera_origin + ray_direction * RAY_LENGTH_M
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
        _fail("production player camera rig drifted from frozen 69-degree / 4.9 m witness contract")
        return
    var production_fov := PRODUCTION_FOV_DEGREES
    var production_spring_length := PRODUCTION_SPRING_LENGTH_M

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
        _fail("Anneessens road has fewer than two exact source points")
        return

    var viewpoint: Dictionary = resolver._safe_viewpoint(document, road)
    if viewpoint.is_empty():
        _fail("resolver returned no safe viewpoint")
        return
    var segment_index := int(viewpoint.get("segment_index", -1))
    if segment_index < 0 or segment_index + 1 >= points.size():
        _fail("selected source segment index invalid")
        return

    var start := points[segment_index]
    var finish := points[segment_index + 1]
    var midpoint := start.lerp(finish, 0.5)
    var direction := (finish - start).normalized()
    if direction == Vector2.ZERO:
        _fail("selected source segment direction is zero")
        return
    var perpendicular := Vector2(-direction.y, direction.x)
    var offset := float(viewpoint.get("offset_m", 0.0))
    var lookahead := float(viewpoint.get("axis_lookahead_m", 0.0))
    if offset <= 0.0 or lookahead <= 0.0:
        _fail("selected viewpoint metadata invalid")
        return

    var start_connections := resolver._source_endpoint_continuation_count(document, road, points[0])
    var end_connections := resolver._source_endpoint_continuation_count(document, road, points[points.size() - 1])
    if start_connections < 0 or end_connections < 0:
        _fail("exact source network continuation unavailable")
        return

    var candidates: Array[Dictionary] = []
    var safest_clearance := -INF
    for side: float in [1.0, -1.0]:
        var spawn := midpoint + perpendicular * offset * side
        if resolver._point_inside_any_source_building(document, spawn):
            continue
        for along_sign: float in [1.0, -1.0]:
            var target := midpoint + direction * lookahead * along_sign
            if resolver._point_inside_any_source_building(document, target):
                continue
            var view_axis := target - spawn
            if view_axis == Vector2.ZERO:
                continue
            if absf(view_axis.normalized().dot(direction)) < resolver.MIN_SOURCE_AXIS_ALIGNMENT:
                continue
            if not resolver._segment_clear_of_source_buildings(document, spawn, target):
                continue
            var clearance := resolver._source_view_corridor_clearance(document, spawn, target)
            if not is_finite(clearance) or clearance < 0.0:
                continue
            var continuation := end_connections if along_sign > 0.0 else start_connections
            var sampled_hits := _sampled_source_building_hits(resolver, document, spawn, target, production_fov, production_spring_length)
            if sampled_hits < 0:
                _fail("exact-source player-ray context unavailable")
                return
            safest_clearance = maxf(safest_clearance, clearance)
            candidates.append({
                "spawn": spawn,
                "target": target,
                "clearance": clearance,
                "continuation": continuation,
                "sampled_hits": sampled_hits,
            })

    if candidates.is_empty() or not is_finite(safest_clearance):
        _fail("no exact-source candidates at selected offset")
        return

    var best_continuation := -1
    for candidate: Dictionary in candidates:
        if float(candidate.get("clearance", -INF)) + EPSILON_M < safest_clearance:
            continue
        best_continuation = maxi(best_continuation, int(candidate.get("continuation", -1)))
    if best_continuation < 0:
        _fail("no candidate survived safest source-view stratum")
        return

    var best_acceptable_hits := -1
    var eligible_count := 0
    var diagnostics: Array[String] = []
    for candidate: Dictionary in candidates:
        if float(candidate.get("clearance", -INF)) + EPSILON_M < safest_clearance:
            continue
        if int(candidate.get("continuation", -1)) != best_continuation:
            continue
        var sampled_hits := int(candidate.get("sampled_hits", -1))
        eligible_count += 1
        diagnostics.append("hits=%d spawn=%s target=%s" % [sampled_hits, str(candidate.get("spawn", Vector2.ZERO)), str(candidate.get("target", Vector2.ZERO))])
        # Reuse the frozen witness contract exactly: 0 is barren, 3 is facade-
        # dominated, and 1-2 source-building rays provide usable urban context.
        if sampled_hits >= 1 and sampled_hits <= 2:
            best_acceptable_hits = maxi(best_acceptable_hits, sampled_hits)

    if eligible_count < 1:
        _fail("no candidate survived safety + continuation stratum")
        return
    if best_acceptable_hits < 1:
        _fail("no source-backed candidate satisfies frozen 1-2 building-ray witness contract: %s" % "; ".join(diagnostics))
        return

    var selected_spawn := viewpoint.get("spawn", Vector2.ZERO) as Vector2
    var selected_target := viewpoint.get("target", Vector2.ZERO) as Vector2
    var selected_hits := _sampled_source_building_hits(resolver, document, selected_spawn, selected_target, production_fov, production_spring_length)
    if selected_hits < 1 or selected_hits > 2:
        _fail("resolver selected visually invalid source context inside equal safety+continuation stratum: selected_hits=%d best_acceptable_hits=%d eligible=%d spawn=(%.3f,%.3f) target=(%.3f,%.3f) candidates=%s" % [selected_hits, best_acceptable_hits, eligible_count, selected_spawn.x, selected_spawn.y, selected_target.x, selected_target.y, "; ".join(diagnostics)])
        return

    print("AUTOMATIC_ROAD_SOURCE_URBAN_CONTEXT_GREEN: road_id=%d eligible=%d selected_hits=%d best_acceptable_hits=%d safest_clearance_m=%.3f continuation=%d viewport=1280x720 production_fov=%.1f production_spring_m=%.1f source_only=true camera_unchanged=true geometry_unchanged=true destination_advertisable=false jouable=false" % [ANNEESSENS_ROAD_ID, eligible_count, selected_hits, best_acceptable_hits, safest_clearance, best_continuation, production_fov, production_spring_length])
    quit(0)
