extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const BOURSE_ORTS_ID := 411724192
const SOURCE_PATH := "res://data/osm/vertical_slice_01.game.json"
const RUNTIME_INDEX_PATH := "res://data/runtime/road_destination_runtime_index.json"
const RUNTIME_INDEX_FORMAT := "grand-bruxelles-road-runtime-index-v1"
const OUTPUT_PATH := "res://artifacts/visual/automatic_road_411724192_player.png"
const WIDTH := 1280
const HEIGHT := 720
const MIN_ROAD_AXIS_ALIGNMENT := 0.90
const OFFSET_EPSILON_M := 0.01
const CAMERA_EPSILON := 0.0001
const ROAD_SUPPORT_COLLISION_MASK := 1 << 19
const CANONICAL_GROUND_COLLISION_MASK := 1
const SAFE_GROUND_COLLISION_MASK := ROAD_SUPPORT_COLLISION_MASK | CANONICAL_GROUND_COLLISION_MASK
const ROAD_SUPPORT_OWNER_META := "grand_bruxelles_owner"
const ROAD_SUPPORT_OWNER_ID := "generic_osm_surface_collision_runtime"
const ROAD_SUPPORT_OSM_IDS_META := "road_support_osm_ids"
const CANONICAL_GROUND_NAME := "Ground"
const MAX_RAY_HITS := 32
const GROUND_EPSILON_M := 0.01

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_AUTOMATIC_ROAD_PLAYER_WITNESS_FAIL: %s" % message)
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
            if int(raw_id) == BOURSE_ORTS_ID:
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
        if raw is Dictionary and int((raw as Dictionary).get("osm_id", 0)) == BOURSE_ORTS_ID:
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

func _contains_osm_id(raw_ids: Variant) -> bool:
    if not raw_ids is Array:
        return false
    for raw: Variant in raw_ids:
        if not (raw is int or raw is float):
            return false
        var numeric := float(raw)
        if not is_finite(numeric) or floor(numeric) != numeric:
            return false
        if int(numeric) == BOURSE_ORTS_ID:
            return true
    return false

func _authorized_support(collider: Object) -> Dictionary:
    if collider == null or not collider is Node:
        return {}
    var node := collider as Node
    if str(node.name) == CANONICAL_GROUND_NAME:
        if not node is CollisionObject3D:
            return {}
        var body := node as CollisionObject3D
        if (body.collision_layer & CANONICAL_GROUND_COLLISION_MASK) == 0:
            return {}
        return {"kind": "canonical_ground", "path": str(node.get_path()), "layer": body.collision_layer}
    if str(node.get_meta(ROAD_SUPPORT_OWNER_META, "")) != ROAD_SUPPORT_OWNER_ID:
        return {}
    if not node is CollisionObject3D:
        return {}
    var support := node as CollisionObject3D
    if (support.collision_layer & ROAD_SUPPORT_COLLISION_MASK) == 0:
        return {}
    if not _contains_osm_id(node.get_meta(ROAD_SUPPORT_OSM_IDS_META, [])):
        return {}
    return {
        "kind": "source_road_support",
        "path": str(node.get_path()),
        "layer": support.collision_layer,
        "owner": str(node.get_meta(ROAD_SUPPORT_OWNER_META, "")),
    }

func _support_below(player: CharacterBody3D) -> Dictionary:
    var world := player.get_world_3d()
    if world == null:
        return {}
    var excluded: Array[RID] = []
    for _attempt: int in range(MAX_RAY_HITS):
        var query := PhysicsRayQueryParameters3D.create(
            player.global_position + Vector3(0.0, 25.0, 0.0),
            Vector3(player.global_position.x, -200.0, player.global_position.z)
        )
        query.collision_mask = SAFE_GROUND_COLLISION_MASK
        query.collide_with_areas = false
        query.collide_with_bodies = true
        query.exclude = excluded
        var hit := world.direct_space_state.intersect_ray(query)
        if hit.is_empty():
            return {}
        var collider: Variant = hit.get("collider")
        var position: Variant = hit.get("position")
        if collider is Object and position is Vector3:
            var identity := _authorized_support(collider as Object)
            if not identity.is_empty():
                identity["y"] = (position as Vector3).y
                return identity
        var rid: Variant = hit.get("rid")
        if not rid is RID or not (rid as RID).is_valid():
            return {}
        excluded.append(rid as RID)
    return {}

func _capture(viewport: SubViewport) -> bool:
    RenderingServer.force_draw()
    await process_frame
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        return false
    var data := image.get_data()
    if data.is_empty():
        return false
    var min_byte := 255
    var max_byte := 0
    for value: int in data:
        min_byte = mini(min_byte, value)
        max_byte = maxi(max_byte, value)
    if max_byte - min_byte < 8:
        return false
    var absolute := ProjectSettings.globalize_path(OUTPUT_PATH)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    return image.save_png(absolute) == OK

func _run() -> void:
    var expected_source_sha := _runtime_index_source_sha()
    if expected_source_sha.is_empty(): _fail("Bourse road missing from deterministic source-only runtime index"); return
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
    if not resolver.apply_to_player(player, BOURSE_ORTS_ID): _fail("road-411724192 did not resolve into a collision-safe rendered road"); return
    if int(player.get_meta("automatic_road_direct_osm_id", 0)) != BOURSE_ORTS_ID: _fail("OSM identity metadata drifted"); return
    if str(player.get_meta("automatic_road_direct_source_path", "")) != SOURCE_PATH: _fail("source path provenance drifted"); return
    if str(player.get_meta("automatic_road_direct_source_sha256", "")).to_lower() != expected_source_sha: _fail("source digest provenance drifted"); return
    if not str(player.get_meta("automatic_road_direct_source_name", "")).contains("Auguste Orts"): _fail("source road name drifted"); return
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
    if absf(player.global_position.y - (ground_y + 1.05)) > GROUND_EPSILON_M: _fail("player body clearance no longer matches physics-backed ground"); return

    await physics_frame
    var support := _support_below(player)
    if support.is_empty(): _fail("no independently verified authorized collider supports road-411724192 spawn"); return
    var observed_ground_y := float(support.get("y", INF))
    if not is_finite(observed_ground_y) or absf(observed_ground_y - ground_y) > GROUND_EPSILON_M: _fail("independent support collider disagrees with resolver ground_y"); return

    var segment_index := int(player.get_meta("automatic_road_direct_segment_index", -1))
    var tangent := _source_tangent(segment_index)
    if tangent == Vector2.ZERO: _fail("selected source segment tangent unavailable"); return
    var forward_3d := -player.global_basis.z
    var alignment := absf(Vector2(forward_3d.x, forward_3d.z).normalized().dot(tangent))
    if alignment < MIN_ROAD_AXIS_ALIGNMENT: _fail("player view is cross-road: alignment=%.4f required=%.2f" % [alignment, MIN_ROAD_AXIS_ALIGNMENT]); return

    camera.current = true
    for _frame: int in range(12): await process_frame
    if not await _capture(viewport): _fail("1280x720 non-blank player-view capture failed"); return

    print("BOURSE_AUTOMATIC_ROAD_PLAYER_WITNESS_GREEN: osm_id=%d name=%s spawn=(%.3f,%.3f) target=(%.3f,%.3f) ground_y=%.3f independently_observed_ground_y=%.3f support_kind=%s support_path=%s collision_layer=%d offset_m=%.3f road_axis_alignment=%.4f camera_unchanged=true camera_clip_unchanged=true camera_cull_mask_unchanged=true source_sha=%s dynamic_state_frozen=true human_full_frame_review_required=true destination_advertisable=false visual_acceptance=false jouable_authorized=false frame=%s" % [BOURSE_ORTS_ID, str(player.get_meta("automatic_road_direct_source_name", "")), spawn_xz.x, spawn_xz.y, target_xz.x, target_xz.y, ground_y, observed_ground_y, str(support.get("kind", "")), str(support.get("path", "")), int(support.get("layer", 0)), offset_m, alignment, expected_source_sha, OUTPUT_PATH])
    quit(0)
