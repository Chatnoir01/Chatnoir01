extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const OSM_ID := 8512036
const SOURCE_PATH := "res://data/osm/vertical_slice_01.game.json"
const RUNTIME_INDEX_PATH := "res://data/runtime/road_destination_runtime_index.json"
const OUTPUT_PATH := "res://artifacts/visual/automatic_road_8512036_player.png"
const WIDTH := 1280
const HEIGHT := 720
const MIN_AXIS_ALIGNMENT := 0.90
const CAMERA_EPSILON := 0.0001

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_8512036_CANDIDATE_PLAYER_WITNESS_FAIL: %s" % message)
    quit(1)

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
        if raw is Dictionary and int((raw as Dictionary).get("osm_id", 0)) == OSM_ID:
            return raw as Dictionary
    return {}

func _runtime_index_source_sha() -> String:
    if not FileAccess.file_exists(RUNTIME_INDEX_PATH):
        return ""
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RUNTIME_INDEX_PATH))
    if not parsed is Dictionary:
        return ""
    var index := parsed as Dictionary
    if not bool(index.get("source_lookup_only", false)):
        return ""
    var authorization: Variant = index.get("authorization", {})
    if not authorization is Dictionary:
        return ""
    var auth := authorization as Dictionary
    for forbidden: String in ["render_authorized", "collision_authorized", "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized"]:
        if bool(auth.get(forbidden, true)):
            return ""
    var documents: Variant = index.get("documents", [])
    if not documents is Array:
        return ""
    for raw_document: Variant in documents:
        if not raw_document is Dictionary:
            return ""
        var document := raw_document as Dictionary
        if str(document.get("path", "")) != SOURCE_PATH.trim_prefix("res://"):
            continue
        var road_ids: Variant = document.get("road_ids", [])
        if not road_ids is Array:
            return ""
        var found := false
        for raw_id: Variant in road_ids:
            if int(raw_id) == OSM_ID:
                found = true
                break
        if not found:
            return ""
        return str(document.get("sha256", "")).strip_edges().to_lower()
    return ""

func _source_tangent(segment_index: int) -> Vector2:
    var road := _source_road()
    var points: Variant = road.get("points", [])
    if not points is Array or segment_index < 0 or segment_index + 1 >= points.size():
        return Vector2.ZERO
    var a: Variant = points[segment_index]
    var b: Variant = points[segment_index + 1]
    if not a is Array or not b is Array or a.size() < 2 or b.size() < 2:
        return Vector2.ZERO
    return (Vector2(float(b[0]), float(b[1])) - Vector2(float(a[0]), float(a[1]))).normalized()

func _freeze_dynamic(scene: Node) -> void:
    for path: String in ["MissionLabel", "PrototypeLabel", "MiniMap", "MobileControls"]:
        var canvas := scene.get_node_or_null(path) as CanvasItem
        if canvas != null:
            canvas.visible = false
    for path: String in ["PrototypeCar", "PhysicalCarB", "MidiUrbanLife"]:
        var spatial := scene.get_node_or_null(path) as Node3D
        if spatial != null:
            spatial.visible = false
    var traffic := scene.get_node_or_null("TrafficManager")
    if traffic != null:
        traffic.set("auto_spawn_runtime", false)
        if traffic is Node3D:
            (traffic as Node3D).visible = false

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
    var road := _source_road()
    if road.is_empty():
        _fail("winning candidate road missing from locked source")
        return
    if not str(road.get("name", "")).contains("Saint-G"):
        _fail("winning candidate source name drifted")
        return
    if not bool(road.get("drivable", false)):
        _fail("winning candidate is no longer source-drivable")
        return
    var expected_source_sha := _runtime_index_source_sha()
    if expected_source_sha.length() != 64:
        _fail("winning candidate missing from source-only runtime index")
        return
    if FileAccess.get_sha256(SOURCE_PATH).to_lower() != expected_source_sha:
        _fail("locked source bytes no longer match runtime-index identity")
        return

    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    var scene := MAIN_SCENE.instantiate()
    viewport.add_child(scene)
    _freeze_dynamic(scene)
    for _frame: int in range(36):
        await process_frame
        await physics_frame

    var player := scene.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _fail("production Player missing")
        return
    var spring_arm := player.get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
    var camera := player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if spring_arm == null or camera == null:
        _fail("production camera rig missing")
        return
    var camera_before := camera.transform
    var fov_before := camera.fov
    var projection_before := camera.projection
    var spring_before := spring_arm.transform
    var spring_length_before := spring_arm.spring_length

    var resolver := RESOLVER_SCRIPT.new()
    viewport.add_child(resolver)
    if not resolver.apply_to_player(player, OSM_ID):
        _fail("winning repository-derived Bourse candidate failed shared road resolver")
        return
    if int(player.get_meta("automatic_road_direct_osm_id", 0)) != OSM_ID:
        _fail("resolved OSM identity drifted")
        return
    if str(player.get_meta("automatic_road_direct_source_sha256", "")).to_lower() != expected_source_sha:
        _fail("resolved source digest drifted")
        return
    if not str(player.get_meta("automatic_road_direct_source_name", "")).contains("Saint-G"):
        _fail("resolved source name drifted")
        return
    if not bool(player.get_meta("automatic_road_direct_source_sightline_clear", false)):
        _fail("resolver did not prove source sightline clearance")
        return
    var ground_y := float(player.get_meta("automatic_road_direct_ground_y", INF))
    if not is_finite(ground_y):
        _fail("resolver did not prove finite collision-backed ground")
        return
    if not camera.transform.is_equal_approx(camera_before) or absf(camera.fov - fov_before) > CAMERA_EPSILON or camera.projection != projection_before:
        _fail("resolver mutated production camera")
        return
    if not spring_arm.transform.is_equal_approx(spring_before) or absf(spring_arm.spring_length - spring_length_before) > CAMERA_EPSILON:
        _fail("resolver mutated production spring arm")
        return

    var segment_index := int(player.get_meta("automatic_road_direct_segment_index", -1))
    var tangent := _source_tangent(segment_index)
    if tangent == Vector2.ZERO:
        _fail("resolved source tangent unavailable")
        return
    var forward := -player.global_basis.z
    var alignment := absf(Vector2(forward.x, forward.z).normalized().dot(tangent))
    if alignment < MIN_AXIS_ALIGNMENT:
        _fail("winning candidate view is cross-road: %.4f" % alignment)
        return

    camera.current = true
    for _frame: int in range(12):
        await process_frame
    if not await _capture(viewport):
        _fail("1280x720 player witness capture failed")
        return

    print("BOURSE_8512036_CANDIDATE_PLAYER_WITNESS_GREEN: osm_id=%d name=%s ground_y=%.3f axis_alignment=%.4f source_sha=%s camera_unchanged=true dynamic_state_frozen=true human_full_frame_review_required=true destination_advertisable=false visual_acceptance=false jouable_authorized=false frame=%s" % [OSM_ID, str(road.get("name", "")), ground_y, alignment, expected_source_sha, OUTPUT_PATH])
    quit(0)
