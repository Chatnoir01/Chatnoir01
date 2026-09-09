extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const SOURCE_PATH := "res://data/osm/vertical_slice_01.game.json"
const RUNTIME_INDEX_PATH := "res://data/runtime/road_destination_runtime_index.json"
const RUNTIME_INDEX_FORMAT := "grand-bruxelles-road-runtime-index-v1"
const OUTPUT_PATH := "res://artifacts/visual/automatic_midi_road_player.png"
const WIDTH := 1280
const HEIGHT := 720
const MIDI_ANCHOR_ID := "midi"
const MIDI_ROAD_NAME := "Avenue Fonsny - Fonsnylaan"
const MAX_MIDI_ANCHOR_DISTANCE_M := 80.0
const MIN_ROAD_AXIS_ALIGNMENT := 0.90
const CAMERA_EPSILON := 0.0001
const GROUND_EPSILON_M := 0.01
const ROAD_SUPPORT_COLLISION_MASK := 1 << 19
const CANONICAL_GROUND_COLLISION_MASK := 1
const SAFE_GROUND_COLLISION_MASK := ROAD_SUPPORT_COLLISION_MASK | CANONICAL_GROUND_COLLISION_MASK
const ROAD_SUPPORT_OWNER_META := "grand_bruxelles_owner"
const ROAD_SUPPORT_OWNER_ID := "generic_osm_surface_collision_runtime"
const ROAD_SUPPORT_OSM_IDS_META := "road_support_osm_ids"
const CANONICAL_GROUND_NAME := "Ground"
const MAX_RAY_HITS := 32

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_AUTOMATIC_ROAD_PLAYER_WITNESS_FAIL: %s" % message)
    quit(1)

func _document() -> Dictionary:
    if not FileAccess.file_exists(SOURCE_PATH):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
    return parsed as Dictionary if parsed is Dictionary else {}

func _midi_anchor() -> Vector2:
    var corridor: Variant = _document().get("corridor", {})
    if not corridor is Dictionary:
        return Vector2(INF, INF)
    var anchors: Variant = (corridor as Dictionary).get("anchors", [])
    if not anchors is Array:
        return Vector2(INF, INF)
    for raw: Variant in anchors:
        if raw is Dictionary and str((raw as Dictionary).get("id", "")) == MIDI_ANCHOR_ID:
            return Vector2(float((raw as Dictionary).get("x", INF)), float((raw as Dictionary).get("z", INF)))
    return Vector2(INF, INF)

func _road_points(road: Dictionary) -> Array[Vector2]:
    var result: Array[Vector2] = []
    var raw_points: Variant = road.get("points", [])
    if not raw_points is Array:
        return result
    for raw: Variant in raw_points:
        if not raw is Array or raw.size() < 2:
            return []
        var point := Vector2(float(raw[0]), float(raw[1]))
        if not is_finite(point.x) or not is_finite(point.y):
            return []
        result.append(point)
    return result

func _nearest_anchor_distance(road: Dictionary, anchor: Vector2) -> float:
    var best := INF
    for point: Vector2 in _road_points(road):
        best = minf(best, point.distance_to(anchor))
    return best

func _candidate_roads(anchor: Vector2) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    var roads: Variant = _document().get("roads", [])
    if not roads is Array:
        return result
    for raw: Variant in roads:
        if not raw is Dictionary:
            continue
        var road := raw as Dictionary
        var osm_id := int(road.get("osm_id", 0))
        if osm_id <= 0 or str(road.get("name", "")) != MIDI_ROAD_NAME or not bool(road.get("drivable", false)):
            continue
        var distance := _nearest_anchor_distance(road, anchor)
        if not is_finite(distance) or distance > MAX_MIDI_ANCHOR_DISTANCE_M:
            continue
        result.append({"osm_id": osm_id, "road": road, "anchor_distance": distance})
    result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        var da := float(a.get("anchor_distance", INF))
        var db := float(b.get("anchor_distance", INF))
        if absf(da - db) > 0.000001:
            return da < db
        return int(a.get("osm_id", 0)) < int(b.get("osm_id", 0))
    )
    return result

func _runtime_index_source_sha(candidate_ids: Array[int]) -> String:
    if not FileAccess.file_exists(RUNTIME_INDEX_PATH):
        return ""
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RUNTIME_INDEX_PATH))
    if not parsed is Dictionary:
        return ""
    var index := parsed as Dictionary
    if str(index.get("format", "")) != RUNTIME_INDEX_FORMAT or not bool(index.get("source_lookup_only", false)):
        return ""
    var authorization: Variant = index.get("authorization", {})
    if not authorization is Dictionary or not bool((authorization as Dictionary).get("source_lookup_only", false)):
        return ""
    for forbidden: String in ["render_authorized", "collision_authorized", "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized"]:
        if bool((authorization as Dictionary).get(forbidden, true)):
            return ""
    var documents: Variant = index.get("documents", [])
    if not documents is Array:
        return ""
    var source_relative := SOURCE_PATH.trim_prefix("res://")
    for raw_document: Variant in documents:
        if not raw_document is Dictionary:
            continue
        var descriptor := raw_document as Dictionary
        if str(descriptor.get("path", "")) != source_relative:
            continue
        var road_ids: Variant = descriptor.get("road_ids", [])
        var expected_sha := str(descriptor.get("sha256", "")).strip_edges().to_lower()
        if expected_sha.length() != 64 or not road_ids is Array:
            return ""
        for candidate_id: int in candidate_ids:
            if not road_ids.has(candidate_id):
                return ""
        return expected_sha
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

func _contains_osm_id(raw_ids: Variant, osm_id: int) -> bool:
    if not raw_ids is Array:
        return false
    for raw: Variant in raw_ids:
        if not (raw is int or raw is float):
            return false
        var numeric := float(raw)
        if not is_finite(numeric) or floor(numeric) != numeric:
            return false
        if int(numeric) == osm_id:
            return true
    return false

func _authorized_support(collider: Object, osm_id: int) -> Dictionary:
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
    if str(node.get_meta(ROAD_SUPPORT_OWNER_META, "")) != ROAD_SUPPORT_OWNER_ID or not node is CollisionObject3D:
        return {}
    var support := node as CollisionObject3D
    if (support.collision_layer & ROAD_SUPPORT_COLLISION_MASK) == 0:
        return {}
    if not _contains_osm_id(node.get_meta(ROAD_SUPPORT_OSM_IDS_META, []), osm_id):
        return {}
    return {"kind": "source_road_support", "path": str(node.get_path()), "layer": support.collision_layer, "owner": ROAD_SUPPORT_OWNER_ID}

func _support_below(player: CharacterBody3D, osm_id: int) -> Dictionary:
    var world := player.get_world_3d()
    if world == null:
        return {}
    var excluded: Array[RID] = []
    for _attempt: int in range(MAX_RAY_HITS):
        var query := PhysicsRayQueryParameters3D.create(player.global_position + Vector3(0.0, 25.0, 0.0), Vector3(player.global_position.x, -200.0, player.global_position.z))
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
            var identity := _authorized_support(collider as Object, osm_id)
            if not identity.is_empty():
                identity["y"] = (position as Vector3).y
                return identity
        var rid: Variant = hit.get("rid")
        if not rid is RID or not (rid as RID).is_valid():
            return {}
        excluded.append(rid as RID)
    return {}

func _source_tangent(road: Dictionary, segment_index: int) -> Vector2:
    var points := _road_points(road)
    if segment_index < 0 or segment_index + 1 >= points.size():
        return Vector2.ZERO
    return (points[segment_index + 1] - points[segment_index]).normalized()

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
    var midi_anchor := _midi_anchor()
    if not is_finite(midi_anchor.x) or not is_finite(midi_anchor.y): _fail("Midi source anchor missing"); return
    var candidates := _candidate_roads(midi_anchor)
    if candidates.is_empty(): _fail("no exact Fonsny source-road candidate exists inside Midi neighborhood"); return
    var candidate_ids: Array[int] = []
    for candidate: Dictionary in candidates:
        candidate_ids.append(int(candidate.get("osm_id", 0)))
    var expected_source_sha := _runtime_index_source_sha(candidate_ids)
    if expected_source_sha.is_empty(): _fail("Midi Fonsny candidate set missing from deterministic source-only runtime index"); return
    if FileAccess.get_sha256(SOURCE_PATH).to_lower() != expected_source_sha: _fail("source digest no longer matches runtime index"); return

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
    var camera_before := camera.transform
    var fov_before := camera.fov
    var projection_before := camera.projection
    var near_before := camera.near
    var far_before := camera.far
    var cull_before := camera.cull_mask
    var spring_before := spring_arm.transform
    var spring_length_before := spring_arm.spring_length

    var resolver := RESOLVER_SCRIPT.new()
    viewport.add_child(resolver)
    var selected: Dictionary = {}
    var rejected_ids: Array[int] = []
    for candidate: Dictionary in candidates:
        var osm_id := int(candidate.get("osm_id", 0))
        if resolver.apply_to_player(player, osm_id):
            selected = candidate
            break
        rejected_ids.append(osm_id)
    if selected.is_empty(): _fail("no source-backed Fonsny road inside Midi neighborhood resolves collision-safe; candidates=%s" % str(candidate_ids)); return

    var selected_id := int(selected.get("osm_id", 0))
    var road := selected.get("road", {}) as Dictionary
    if int(player.get_meta("automatic_road_direct_osm_id", 0)) != selected_id: _fail("OSM identity metadata drifted"); return
    if str(player.get_meta("automatic_road_direct_source_path", "")) != SOURCE_PATH: _fail("source path provenance drifted"); return
    if str(player.get_meta("automatic_road_direct_source_sha256", "")).to_lower() != expected_source_sha: _fail("source digest provenance drifted"); return
    if str(player.get_meta("automatic_road_direct_source_name", "")) != MIDI_ROAD_NAME: _fail("source road name drifted"); return
    if not bool(player.get_meta("automatic_road_direct_source_sightline_clear", false)): _fail("source sightline safety proof missing"); return

    if not camera.transform.is_equal_approx(camera_before) or absf(camera.fov - fov_before) > CAMERA_EPSILON or camera.projection != projection_before: _fail("resolver mutated production camera"); return
    if absf(camera.near - near_before) > CAMERA_EPSILON or absf(camera.far - far_before) > CAMERA_EPSILON or camera.cull_mask != cull_before: _fail("resolver mutated camera clip/cull contract"); return
    if not spring_arm.transform.is_equal_approx(spring_before) or absf(spring_arm.spring_length - spring_length_before) > CAMERA_EPSILON: _fail("resolver mutated spring-arm contract"); return

    var ground_y := float(player.get_meta("automatic_road_direct_ground_y", INF))
    if not is_finite(ground_y): _fail("physics-backed ground height missing"); return
    if absf(player.global_position.y - (ground_y + 1.05)) > GROUND_EPSILON_M: _fail("player clearance no longer matches physics-backed ground"); return
    var spawn_xz := Vector2(player.global_position.x, player.global_position.z)
    var anchor_distance := spawn_xz.distance_to(midi_anchor)
    if anchor_distance > MAX_MIDI_ANCHOR_DISTANCE_M: _fail("resolved player position escaped Midi source anchor neighborhood"); return

    await physics_frame
    var support := _support_below(player, selected_id)
    if support.is_empty(): _fail("no independently verified authorized collider supports selected Midi road"); return
    var observed_ground_y := float(support.get("y", INF))
    if not is_finite(observed_ground_y) or absf(observed_ground_y - ground_y) > GROUND_EPSILON_M: _fail("independent support collider disagrees with resolver ground_y"); return

    var segment_index := int(player.get_meta("automatic_road_direct_segment_index", -1))
    var tangent := _source_tangent(road, segment_index)
    if tangent == Vector2.ZERO: _fail("selected source segment tangent unavailable"); return
    var forward_3d := -player.global_basis.z
    var alignment := absf(Vector2(forward_3d.x, forward_3d.z).normalized().dot(tangent))
    if alignment < MIN_ROAD_AXIS_ALIGNMENT: _fail("player view is cross-road: alignment=%.4f" % alignment); return

    camera.current = true
    for _frame: int in range(12): await process_frame
    if not await _capture(viewport): _fail("1280x720 non-blank player-view capture failed"); return

    print("MIDI_AUTOMATIC_ROAD_PLAYER_WITNESS_GREEN: osm_id=%d source_name=%s candidate_count=%d rejected_before_success=%s anchor_distance_m=%.3f ground_y=%.3f independently_observed_ground_y=%.3f support_kind=%s support_path=%s road_axis_alignment=%.4f camera_unchanged=true source_sha=%s dynamic_state_frozen=true human_full_frame_review_required=true destination_advertisable=false visual_acceptance=false jouable_authorized=false" % [selected_id, MIDI_ROAD_NAME.replace(" ", "_"), candidates.size(), str(rejected_ids).replace(" ", ""), anchor_distance, ground_y, observed_ground_y, str(support.get("kind", "")), str(support.get("path", "")), alignment, expected_source_sha])
    quit(0)
