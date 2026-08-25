extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const LEMONNIER_ID := 359177328
const SOURCE_PATH := "res://data/osm/vertical_slice_01.game.json"
const RUNTIME_INDEX_PATH := "res://data/runtime/road_destination_runtime_index.json"
const RUNTIME_INDEX_FORMAT := "grand-bruxelles-road-runtime-index-v1"
const OUTPUT_PATH := "res://artifacts/visual/automatic_road_359177328_player.png"
const ANIMATION_DIAGNOSTIC_PATH := "res://artifacts/visual/automatic_road_359177328_player_animation_diagnostic.json"
const WIDTH := 1280
const HEIGHT := 720
const MIN_ROAD_AXIS_ALIGNMENT := 0.90

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("AUTOMATIC_ROAD_DIRECT_SPAWN_WITNESS_FAIL: %s" % message)
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
        if expected_sha.length() != 64 or not road_ids is Array or road_ids.is_empty():
            return ""
        var contains_lemonnier := false
        for raw_id: Variant in road_ids:
            if int(raw_id) == LEMONNIER_ID:
                contains_lemonnier = true
                break
        return expected_sha if contains_lemonnier else ""
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

func _authored_animation_driver_state(player: CharacterBody3D) -> Dictionary:
    var visual := player.get_node_or_null("VisualUpgrade")
    if visual == null or not visual.has_method("is_using_authored_character"):
        return {"using_authored_character": false, "authored_character_found": false, "animation_player_count": 0, "animation_tree_count": 0, "active_driver_count": 0, "active_driver": "", "active_animation": ""}
    if not bool(visual.call("is_using_authored_character")):
        return {"using_authored_character": false, "authored_character_found": false, "animation_player_count": 0, "animation_tree_count": 0, "active_driver_count": 0, "active_driver": "", "active_animation": ""}
    var authored := visual.get_node_or_null("AuthoredCharacter")
    if authored == null:
        return {"using_authored_character": true, "authored_character_found": false, "animation_player_count": 0, "animation_tree_count": 0, "active_driver_count": 0, "active_driver": "", "active_animation": ""}
    var animation_player_count := 0
    var animation_tree_count := 0
    var active_driver_count := 0
    var active_driver := ""
    var active_animation := ""
    var stack: Array[Node] = [authored]
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        if node is AnimationPlayer:
            animation_player_count += 1
            var animation_player := node as AnimationPlayer
            if animation_player.is_playing() and not animation_player.current_animation.is_empty():
                active_driver_count += 1
                if active_driver.is_empty():
                    active_driver = "AnimationPlayer"
                    active_animation = animation_player.current_animation
        elif node is AnimationTree:
            animation_tree_count += 1
            var animation_tree := node as AnimationTree
            if animation_tree.active:
                active_driver_count += 1
                if active_driver.is_empty():
                    active_driver = "AnimationTree"
                    active_animation = "animation_tree_active"
        for child: Node in node.get_children():
            stack.append(child)
    return {"using_authored_character": true, "authored_character_found": true, "animation_player_count": animation_player_count, "animation_tree_count": animation_tree_count, "active_driver_count": active_driver_count, "active_driver": active_driver, "active_animation": active_animation}

func _write_animation_diagnostic(player: CharacterBody3D, animation_state: Dictionary, status: String, reason: String) -> bool:
    var payload := {
        "schema": "grand-bruxelles-automatic-road-player-animation-diagnostic-v1",
        "road_osm_id": LEMONNIER_ID,
        "source_path": SOURCE_PATH,
        "source_sha256": str(player.get_meta("automatic_road_direct_source_sha256", "")).to_lower(),
        "lookup_mode": str(player.get_meta("automatic_road_direct_lookup_mode", "")),
        "using_authored_character": bool(animation_state.get("using_authored_character", false)),
        "authored_character_found": bool(animation_state.get("authored_character_found", false)),
        "animation_player_count": int(animation_state.get("animation_player_count", 0)),
        "animation_tree_count": int(animation_state.get("animation_tree_count", 0)),
        "active_driver_count": int(animation_state.get("active_driver_count", 0)),
        "active_driver": str(animation_state.get("active_driver", "")),
        "active_animation": str(animation_state.get("active_animation", "")),
        "status": status,
        "reason": reason,
        "qa_witness_accepted": false,
        "playability_claimed": false,
        "destination_advertisable": false,
        "jouable_authorized": false
    }
    var absolute := ProjectSettings.globalize_path(ANIMATION_DIAGNOSTIC_PATH)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    var file := FileAccess.open(ANIMATION_DIAGNOSTIC_PATH, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(payload, "  ") + "\n")
    file.close()
    return FileAccess.file_exists(ANIMATION_DIAGNOSTIC_PATH)

func _capture(viewport: SubViewport) -> bool:
    RenderingServer.force_draw()
    await process_frame
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        return false
    var absolute := ProjectSettings.globalize_path(OUTPUT_PATH)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    return image.save_png(absolute) == OK

func _selected_source_tangent(segment_index: int) -> Vector2:
    if segment_index < 0 or not FileAccess.file_exists(SOURCE_PATH):
        return Vector2.ZERO
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
    if not parsed is Dictionary:
        return Vector2.ZERO
    var roads: Variant = (parsed as Dictionary).get("roads", [])
    if not roads is Array:
        return Vector2.ZERO
    for raw: Variant in roads:
        if not raw is Dictionary or int((raw as Dictionary).get("osm_id", 0)) != LEMONNIER_ID:
            continue
        var points: Variant = (raw as Dictionary).get("points", [])
        if not points is Array or segment_index + 1 >= points.size():
            return Vector2.ZERO
        var a_raw: Variant = points[segment_index]
        var b_raw: Variant = points[segment_index + 1]
        if not a_raw is Array or not b_raw is Array or a_raw.size() < 2 or b_raw.size() < 2:
            return Vector2.ZERO
        var a := Vector2(float(a_raw[0]), float(a_raw[1]))
        var b := Vector2(float(b_raw[0]), float(b_raw[1]))
        return (b - a).normalized()
    return Vector2.ZERO

func _run() -> void:
    var expected_source_sha := _runtime_index_source_sha()
    if expected_source_sha.is_empty(): _fail("deterministic source-only runtime index contract missing"); return
    if FileAccess.get_sha256(SOURCE_PATH).to_lower() != expected_source_sha: _fail("source digest no longer matches deterministic runtime index"); return
    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    var scene := MAIN_SCENE.instantiate(); viewport.add_child(scene); _hide_dynamic(scene)
    for _frame: int in range(36): await process_frame; await physics_frame
    var player := scene.get_node_or_null("Player") as CharacterBody3D
    if player == null: _fail("production Player missing"); return
    var resolver := RESOLVER_SCRIPT.new(); viewport.add_child(resolver)
    if not resolver.apply_to_player(player, LEMONNIER_ID): _fail("road-359177328 did not resolve into a collision-safe rendered road"); return
    if int(player.get_meta("automatic_road_direct_osm_id", 0)) != LEMONNIER_ID: _fail("OSM identity metadata drifted"); return
    if str(player.get_meta("automatic_road_direct_source_path", "")) != SOURCE_PATH: _fail("source path provenance drifted"); return
    if str(player.get_meta("automatic_road_direct_source_sha256", "")).to_lower() != expected_source_sha: _fail("source digest provenance drifted"); return
    if not str(player.get_meta("automatic_road_direct_source_name", "")).contains("Maurice Lemonnier"): _fail("source road name drifted"); return
    if not bool(player.get_meta("automatic_road_direct_source_sightline_clear", false)): _fail("source sightline safety proof missing"); return
    var ground_y := float(player.get_meta("automatic_road_direct_ground_y", INF))
    if not is_finite(ground_y): _fail("physics-backed ground height missing"); return
    var spawn_xz: Vector2 = player.get_meta("automatic_road_direct_spawn_xz", Vector2(INF, INF))
    var target_xz: Vector2 = player.get_meta("automatic_road_direct_target_xz", Vector2(INF, INF))
    if not is_finite(spawn_xz.x) or not is_finite(spawn_xz.y) or not is_finite(target_xz.x) or not is_finite(target_xz.y): _fail("spawn/target coordinates are not finite"); return
    var offset_m := float(player.get_meta("automatic_road_direct_offset_m", -1.0))
    if offset_m < 4.0 or offset_m > 20.0: _fail("safe player offset escaped bounded road-side envelope: %.3f" % offset_m); return
    if absf(player.global_position.y - (ground_y + 1.05)) > 0.01: _fail("player body clearance no longer matches physics-backed ground"); return
    var segment_index := int(player.get_meta("automatic_road_direct_segment_index", -1))
    var source_tangent := _selected_source_tangent(segment_index)
    if source_tangent == Vector2.ZERO: _fail("selected source segment tangent unavailable"); return
    var forward_3d := -player.global_basis.z
    var player_forward := Vector2(forward_3d.x, forward_3d.z).normalized()
    var road_axis_alignment := absf(player_forward.dot(source_tangent))
    if road_axis_alignment < MIN_ROAD_AXIS_ALIGNMENT: _fail("player view is cross-road instead of boulevard-aligned: alignment=%.4f required=%.2f" % [road_axis_alignment, MIN_ROAD_AXIS_ALIGNMENT]); return
    for _frame: int in range(12): await process_frame; await physics_frame
    var animation_state := _authored_animation_driver_state(player)
    if not bool(animation_state.get("using_authored_character", false)) or not bool(animation_state.get("authored_character_found", false)):
        _write_animation_diagnostic(player, animation_state, "reject", "authored_player_visual_missing")
        _fail("authored player visual missing from player-view witness")
        return
    if int(animation_state.get("active_driver_count", 0)) <= 0:
        _write_animation_diagnostic(player, animation_state, "reject", "authored_animation_driver_inactive")
        _fail("authored player animation driver inactive; refusing bind/T-pose player-view witness")
        return
    if not _write_animation_diagnostic(player, animation_state, "candidate", "active_authored_animation_driver"):
        _fail("animation diagnostic could not be written")
        return
    var camera := player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if camera == null: _fail("production player camera missing"); return
    camera.current = true
    for _frame: int in range(12): await process_frame
    if not await _capture(viewport): _fail("1280x720 player-view capture failed"); return
    print("AUTOMATIC_ROAD_DIRECT_SPAWN_WITNESS_GREEN: osm_id=%d name=%s spawn=(%.3f,%.3f) target=(%.3f,%.3f) ground_y=%.3f offset_m=%.3f road_axis_alignment=%.4f source_sha=%s animation_driver=%s animation=%s frame=%s diagnostic=%s" % [LEMONNIER_ID, str(player.get_meta("automatic_road_direct_source_name", "")), spawn_xz.x, spawn_xz.y, target_xz.x, target_xz.y, ground_y, offset_m, road_axis_alignment, expected_source_sha, str(animation_state.get("active_driver", "")), str(animation_state.get("active_animation", "")), OUTPUT_PATH, ANIMATION_DIAGNOSTIC_PATH])
    quit(0)
