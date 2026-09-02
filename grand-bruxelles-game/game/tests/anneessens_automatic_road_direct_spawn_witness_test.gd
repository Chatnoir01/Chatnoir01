extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const ANNEESSENS_PLACE_ID := 1382734012
const SOURCE_PATH := "res://data/osm/vertical_slice_01.game.json"
const RUNTIME_INDEX_PATH := "res://data/runtime/road_destination_runtime_index.json"
const RUNTIME_INDEX_FORMAT := "grand-bruxelles-road-runtime-index-v1"
const OUTPUT_PATH := "res://artifacts/visual/automatic_road_1382734012_player.png"
const WIDTH := 1280
const HEIGHT := 720
const MIN_ROAD_AXIS_ALIGNMENT := 0.90
const OFFSET_EPSILON_M := 0.01
const CAMERA_EPSILON := 0.0001

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ANNEESSENS_AUTOMATIC_ROAD_PLAYER_WITNESS_FAIL: %s" % message)
    quit(1)

func _runtime_index_source_sha() -> String:
    if not FileAccess.file_exists(RUNTIME_INDEX_PATH):
        return ""
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RUNTIME_INDEX_PATH))
    if not parsed is Dictionary:
        return ""
    var index := parsed as Dictionary
    if str(index.get("format", "")) != RUNTIME_INDEX_FORMAT or not bool(index.get("source_lookup_only", false)):
        return ""
    var authorization: Variant = index.get("authorization", {})
    if not authorization is Dictionary:
        return ""
    var auth := authorization as Dictionary
    if not bool(auth.get("source_lookup_only", false)):
        return ""
    for forbidden: String in ["render_authorized", "collision_authorized", "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized"]:
        if bool(auth.get(forbidden, true)):
            return ""
    var documents: Variant = index.get("documents", [])
    if not documents is Array:
        return ""
    var source_relative := SOURCE_PATH.trim_prefix("res://")
    for raw_document: Variant in documents:
        if not raw_document is Dictionary:
            return ""
        var descriptor := raw_document as Dictionary
        if str(descriptor.get("path", "")) != source_relative:
            continue
        var expected_sha := str(descriptor.get("sha256", "")).strip_edges().to_lower()
        var road_ids: Variant = descriptor.get("road_ids", [])
        if expected_sha.length() != 64 or not road_ids is Array:
            return ""
        for raw_id: Variant in road_ids:
            if int(raw_id) == ANNEESSENS_PLACE_ID:
                return expected_sha
        return ""
    return ""

func _hide_dynamic(scene: Node) -> void:
    for path: String in ["MissionLabel", "PrototypeLabel", "MiniMap", "MobileControls"]:
        var item := scene.get_node_or_null(path) as CanvasItem
        if item != null:
            item.visible = false
    for path: String in ["PrototypeCar", "PhysicalCarB", "MidiUrbanLife"]:
        var spatial := scene.get_node_or_null(path) as Node3D
        if spatial != null:
            spatial.visible = false
    var traffic := scene.get_node_or_null("TrafficManager")
    if traffic != null:
        traffic.set("auto_spawn_runtime", false)
        if traffic is Node3D:
            (traffic as Node3D).visible = false

func _source_road() -> Dictionary:
    if not FileAccess.file_exists(SOURCE_PATH):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
    if not parsed is Dictionary:
        return {}
    var roads: Variant = (parsed as Dictionary).get("roads", [])
    if not roads is Array:
        return {}
    for raw: Variant in roads:
        if raw is Dictionary and int((raw as Dictionary).get("osm_id", 0)) == ANNEESSENS_PLACE_ID:
            return raw as Dictionary
    return {}

func _display_road_width(road: Dictionary) -> float:
    var width := maxf(float(road.get("width", 4.5)), 2.5)
    match str(road.get("class", "")):
        "primary":
            return maxf(width, 10.5)
        "secondary":
            return maxf(width, 8.5)
        "tertiary":
            return maxf(width, 7.2)
    return width

func _offset_matches_source_safe_candidate(offset_m: float) -> bool:
    var road := _source_road()
    if road.is_empty():
        return false
    var half_road := _display_road_width(road) * 0.5
    for shoulder_m: float in [1.10, 2.00, 3.50, 5.00, 7.50]:
        if absf(offset_m - (half_road + shoulder_m)) <= OFFSET_EPSILON_M:
            return true
    return false

func _source_tangent(segment_index: int) -> Vector2:
    if segment_index < 0:
        return Vector2.ZERO
    var road := _source_road()
    if road.is_empty():
        return Vector2.ZERO
    var points: Variant = road.get("points", [])
    if not points is Array or segment_index + 1 >= points.size():
        return Vector2.ZERO
    var a_raw: Variant = points[segment_index]
    var b_raw: Variant = points[segment_index + 1]
    if not a_raw is Array or not b_raw is Array or a_raw.size() < 2 or b_raw.size() < 2:
        return Vector2.ZERO
    return (Vector2(float(b_raw[0]), float(b_raw[1])) - Vector2(float(a_raw[0]), float(a_raw[1]))).normalized()

func _trace_visual_blockers(camera: Camera3D) -> void:
    var world := camera.get_world_3d()
    if world == null:
        print("ANNEESSENS_VISUAL_BLOCKER_TRACE: world_unavailable=true")
        return
    var samples: Array[Vector2] = [Vector2(760.0, 360.0), Vector2(900.0, 360.0), Vector2(1100.0, 360.0)]
    for sample: Vector2 in samples:
        var origin := camera.project_ray_origin(sample)
        var direction := camera.project_ray_normal(sample).normalized()
        var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 250.0)
        query.collide_with_areas = true
        query.collide_with_bodies = true
        query.collision_mask = 0xFFFFFFFF
        var hit := world.direct_space_state.intersect_ray(query)
        if hit.is_empty():
            print("ANNEESSENS_VISUAL_BLOCKER_TRACE: sample=(%.0f,%.0f) hit=false" % [sample.x, sample.y])
            continue
        var collider: Object = hit.get("collider")
        var collider_path := "<non-node>"
        var collider_class := "<unknown>"
        var collider_name := "<unknown>"
        if collider != null:
            collider_class = collider.get_class()
            if collider is Node:
                var collider_node := collider as Node
                collider_path = str(collider_node.get_path())
                collider_name = collider_node.name
        var position: Vector3 = hit.get("position", Vector3.ZERO)
        print("ANNEESSENS_VISUAL_BLOCKER_TRACE: sample=(%.0f,%.0f) hit=true collider_path=%s collider_name=%s collider_class=%s hit=(%.3f,%.3f,%.3f) distance_m=%.3f" % [sample.x, sample.y, collider_path, collider_name, collider_class, position.x, position.y, position.z, origin.distance_to(position)])

func _capture(viewport: SubViewport) -> bool:
    RenderingServer.force_draw()
    await process_frame
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        return false
    var absolute := ProjectSettings.globalize_path(OUTPUT_PATH)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    return image.save_png(absolute) == OK

func _run() -> void:
    var expected_source_sha := _runtime_index_source_sha()
    if expected_source_sha.is_empty(): _fail("Anneessens road missing from deterministic source-only runtime index"); return
    if FileAccess.get_sha256(SOURCE_PATH).to_lower() != expected_source_sha: _fail("source digest no longer matches deterministic runtime index"); return

    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    var scene := MAIN_SCENE.instantiate()
    viewport.add_child(scene)
    _hide_dynamic(scene)
    for _frame: int in range(36): await process_frame; await physics_frame

    var player := scene.get_node_or_null("Player") as CharacterBody3D
    if player == null: _fail("production Player missing"); return
    var spring_arm := player.get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
    var camera := player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if spring_arm == null or camera == null: _fail("production player camera rig missing"); return
    var camera_local_before := camera.transform
    var camera_fov_before := camera.fov
    var camera_projection_before := camera.projection
    var camera_near_before := camera.near
    var camera_far_before := camera.far
    var camera_cull_mask_before := camera.cull_mask
    var spring_local_before := spring_arm.transform
    var spring_length_before := spring_arm.spring_length

    var resolver := RESOLVER_SCRIPT.new()
    viewport.add_child(resolver)
    if not resolver.apply_to_player(player, ANNEESSENS_PLACE_ID): _fail("road-1382734012 did not resolve into a collision-safe rendered road"); return
    if int(player.get_meta("automatic_road_direct_osm_id", 0)) != ANNEESSENS_PLACE_ID: _fail("OSM identity metadata drifted"); return
    if str(player.get_meta("automatic_road_direct_source_path", "")) != SOURCE_PATH: _fail("source path provenance drifted"); return
    if str(player.get_meta("automatic_road_direct_source_sha256", "")).to_lower() != expected_source_sha: _fail("source digest provenance drifted"); return
    if not str(player.get_meta("automatic_road_direct_source_name", "")).contains("Place Anneessens"): _fail("source road name drifted"); return
    if not bool(player.get_meta("automatic_road_direct_source_sightline_clear", false)): _fail("source sightline safety proof missing"); return

    if not camera.transform.is_equal_approx(camera_local_before): _fail("automatic road resolver mutated production camera local transform"); return
    if absf(camera.fov - camera_fov_before) > CAMERA_EPSILON: _fail("automatic road resolver mutated production camera FOV"); return
    if camera.projection != camera_projection_before: _fail("automatic road resolver mutated production camera projection"); return
    if absf(camera.near - camera_near_before) > CAMERA_EPSILON: _fail("automatic road resolver mutated production camera near clip"); return
    if absf(camera.far - camera_far_before) > CAMERA_EPSILON: _fail("automatic road resolver mutated production camera far clip"); return
    if camera.cull_mask != camera_cull_mask_before: _fail("automatic road resolver mutated production camera cull mask"); return
    if not spring_arm.transform.is_equal_approx(spring_local_before): _fail("automatic road resolver mutated production spring-arm transform"); return
    if absf(spring_arm.spring_length - spring_length_before) > CAMERA_EPSILON: _fail("automatic road resolver mutated production spring-arm length"); return

    var ground_y := float(player.get_meta("automatic_road_direct_ground_y", INF))
    if not is_finite(ground_y): _fail("physics-backed ground height missing"); return
    var spawn_xz: Vector2 = player.get_meta("automatic_road_direct_spawn_xz", Vector2(INF, INF))
    var target_xz: Vector2 = player.get_meta("automatic_road_direct_target_xz", Vector2(INF, INF))
    if not is_finite(spawn_xz.x) or not is_finite(spawn_xz.y) or not is_finite(target_xz.x) or not is_finite(target_xz.y): _fail("spawn/target coordinates are not finite"); return
    var offset_m := float(player.get_meta("automatic_road_direct_offset_m", -1.0))
    if not _offset_matches_source_safe_candidate(offset_m): _fail("safe player offset is not one of the source-width-derived resolver candidates: %.3f" % offset_m); return
    if absf(player.global_position.y - (ground_y + 1.05)) > 0.01: _fail("player body clearance no longer matches physics-backed ground"); return

    var segment_index := int(player.get_meta("automatic_road_direct_segment_index", -1))
    var tangent := _source_tangent(segment_index)
    if tangent == Vector2.ZERO: _fail("selected source segment tangent unavailable"); return
    var forward_3d := -player.global_basis.z
    var alignment := absf(Vector2(forward_3d.x, forward_3d.z).normalized().dot(tangent))
    if alignment < MIN_ROAD_AXIS_ALIGNMENT: _fail("player view is cross-road: alignment=%.4f required=%.2f" % [alignment, MIN_ROAD_AXIS_ALIGNMENT]); return

    camera.current = true
    for _frame: int in range(12): await process_frame
    _trace_visual_blockers(camera)
    if not await _capture(viewport): _fail("1280x720 player-view capture failed"); return

    print("ANNEESSENS_AUTOMATIC_ROAD_PLAYER_WITNESS_GREEN: osm_id=%d name=%s spawn=(%.3f,%.3f) target=(%.3f,%.3f) ground_y=%.3f offset_m=%.3f road_axis_alignment=%.4f camera_unchanged=true camera_clip_unchanged=true camera_cull_mask_unchanged=true source_sha=%s destination_advertisable=false jouable_authorized=false frame=%s" % [ANNEESSENS_PLACE_ID, str(player.get_meta("automatic_road_direct_source_name", "")), spawn_xz.x, spawn_xz.y, target_xz.x, target_xz.y, ground_y, offset_m, alignment, expected_source_sha, OUTPUT_PATH])
    quit(0)
