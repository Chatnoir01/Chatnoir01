extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const MATERIAL_FACTORY := preload("res://game/scripts/brussels_osm_rail_surface_material.gd")
const SOURCE_PATH := "res://data/osm/vertical_slice_01.game.json"
const ROAD_CANDIDATE_PATH := "res://data/city_machine/road_cell_coverage_candidates.json"
const ROAD_SEMANTIC_SHA256 := "4ec4ba4ad46a999d3ea32ab4a42b6825d6e43f11fcae92ac9b7a4236222913e0"
const TARGET_OSM_ID := 359177328
const TARGET_NAME_FRAGMENT := "Maurice Lemonnier"
const ARTIFACT_DIR := "res://artifacts/rail_material_player_witness"
const LEGACY_PATH := ARTIFACT_DIR + "/rail_material_legacy.png"
const CURRENT_PATH := ARTIFACT_DIR + "/rail_material_current.png"
const CONTROL_PATH := ARTIFACT_DIR + "/rail_material_control.png"
const REPORT_PATH := ARTIFACT_DIR + "/rail_material_player_witness.json"
const DIFF_THRESHOLD := 0.08
const MIN_CONTROL_CHANGED_FRACTION := 0.0005
const MIN_CONTROL_BBOX_WIDTH := 120
const MIN_CONTROL_BBOX_HEIGHT := 24

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_RAIL_MATERIAL_PLAYER_WITNESS_FAIL: %s" % message)
    quit(1)

func _load_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    return parsed as Dictionary if parsed is Dictionary else {}

func _source_target_identity_is_locked() -> bool:
    var candidate := _load_json(ROAD_CANDIDATE_PATH)
    if candidate.is_empty():
        return false
    if str(candidate.get("schema", "")) != "grand-bruxelles-road-cell-coverage-candidates-v2":
        return false
    if str(candidate.get("road_source", "")) != "data/osm/vertical_slice_01.game.json":
        return false
    if str(candidate.get("road_source_provider", "")) != "OpenStreetMap contributors via Overpass API":
        return false
    if str(candidate.get("road_source_license", "")) != "ODbL-1.0":
        return false
    if str(candidate.get("road_semantic_sha256", "")).to_lower() != ROAD_SEMANTIC_SHA256:
        return false
    if str(candidate.get("status", "")) != "DISCOVERED_SOURCE_ONLY":
        return false
    for authorization: String in ["road_cell_mapping_authorized", "registration_authorized", "runtime_mount_authorized", "rendered_geometry_authorized", "collision_authorized", "safe_spawn_authorized", "jouable_promotion_authorized"]:
        if bool(candidate.get(authorization, true)):
            return false
    var target_in_candidate := false
    for raw_candidate: Variant in candidate.get("candidates", []) as Array:
        if not raw_candidate is Dictionary:
            continue
        var row := raw_candidate as Dictionary
        for raw_id: Variant in row.get("road_ids", []) as Array:
            if int(raw_id) == TARGET_OSM_ID:
                target_in_candidate = true
                break
        if target_in_candidate:
            break
    if not target_in_candidate:
        return false

    var source := _load_json(SOURCE_PATH)
    if source.is_empty():
        return false
    if str(source.get("provider", "")) != "OpenStreetMap contributors via Overpass API":
        return false
    if str(source.get("license", "")) != "ODbL-1.0":
        return false
    var matched := false
    for raw_road: Variant in source.get("roads", []) as Array:
        if not raw_road is Dictionary:
            continue
        var road := raw_road as Dictionary
        if int(road.get("osm_id", 0)) != TARGET_OSM_ID:
            continue
        if not str(road.get("name", "")).contains(TARGET_NAME_FRAGMENT):
            return false
        var points := road.get("points", []) as Array
        if points.size() < 2:
            return false
        matched = true
        break
    return matched

func _capture(path: String) -> Image:
    for _frame: int in range(3):
        await process_frame
    await RenderingServer.frame_post_draw
    var image := root.get_texture().get_image()
    if image == null or image.is_empty():
        return null
    if image.get_width() != 1280 or image.get_height() != 720:
        return null
    if image.save_png(path) != OK:
        return null
    return image

func _hide_dynamic_review_noise(main: Node, player: Node3D) -> void:
    player.visible = false
    player.process_mode = Node.PROCESS_MODE_DISABLED
    var traffic := main.get_node_or_null("TrafficManager")
    if traffic is Node3D:
        (traffic as Node3D).visible = false
        traffic.process_mode = Node.PROCESS_MODE_DISABLED
    var stack: Array[Node] = [main]
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        if node is CanvasItem:
            (node as CanvasItem).visible = false
        for child: Node in node.get_children():
            stack.append(child)

func _rails(root_node: Node) -> Array[CSGBox3D]:
    var found: Array[CSGBox3D] = []
    var stack: Array[Node] = [root_node]
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        if node is CSGBox3D and str(node.name).begins_with("Rail_"):
            found.append(node as CSGBox3D)
        for child: Node in node.get_children():
            stack.append(child)
    return found

func _control_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = Color(1.0, 0.0, 1.0, 1.0)
    material.metallic = 0.0
    material.roughness = 1.0
    return material

func _diff_metrics(a: Image, b: Image) -> Dictionary:
    var changed := 0
    var min_x := a.get_width()
    var min_y := a.get_height()
    var max_x := -1
    var max_y := -1
    for y: int in range(a.get_height()):
        for x: int in range(a.get_width()):
            var left := a.get_pixel(x, y)
            var right := b.get_pixel(x, y)
            var delta := maxf(absf(left.r - right.r), maxf(absf(left.g - right.g), absf(left.b - right.b)))
            if delta <= DIFF_THRESHOLD:
                continue
            changed += 1
            min_x = mini(min_x, x)
            min_y = mini(min_y, y)
            max_x = maxi(max_x, x)
            max_y = maxi(max_y, y)
    var total := a.get_width() * a.get_height()
    var fraction := float(changed) / float(total)
    var bbox_width := 0 if max_x < min_x else max_x - min_x + 1
    var bbox_height := 0 if max_y < min_y else max_y - min_y + 1
    return {
        "changed_pixels": changed,
        "changed_fraction": fraction,
        "bbox": [min_x, min_y, max_x, max_y] if changed > 0 else [],
        "bbox_width": bbox_width,
        "bbox_height": bbox_height,
    }

func _run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ARTIFACT_DIR))
    if not _source_target_identity_is_locked():
        _fail("road-semantic source identity drifted")
        return
    if MATERIAL_FACTORY.MATERIAL_FAMILY != "brussels_osm_rail_surface_v1":
        _fail("shared rail material family drifted")
        return

    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    for _frame: int in range(20):
        await process_frame
        await physics_frame

    var player := main.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _fail("production Player missing")
        return
    var resolver := RESOLVER_SCRIPT.new()
    root.add_child(resolver)
    if not resolver.apply_to_player(player, TARGET_OSM_ID):
        _fail("source-backed Lemonnier resolver refused target")
        return
    if int(player.get_meta("automatic_road_direct_osm_id", 0)) != TARGET_OSM_ID:
        _fail("resolver target identity missing")
        return
    if not str(player.get_meta("automatic_road_direct_source_name", "")).contains(TARGET_NAME_FRAGMENT):
        _fail("resolver target name drifted")
        return
    if not bool(player.get_meta("automatic_road_direct_source_sightline_clear", false)):
        _fail("resolver source sightline proof missing")
        return
    var ground_y := float(player.get_meta("automatic_road_direct_ground_y", INF))
    if not is_finite(ground_y):
        _fail("resolver ground proof missing")
        return

    var runtime := root.get_node_or_null("BrusselsOsmRailSurfaceRuntime")
    if runtime == null:
        _fail("shared rail surface runtime missing")
        return
    for _frame: int in range(180):
        if bool(runtime.call("ready_complete")):
            break
        await process_frame
    if not bool(runtime.call("ready_complete")) or bool(runtime.call("failed")):
        _fail("shared rail surface runtime did not bind cleanly")
        return

    for _frame: int in range(4):
        await process_frame
        await physics_frame
    var active_camera := root.get_camera_3d()
    if active_camera == null:
        _fail("production player camera missing after source-backed road resolve")
        return
    var review_camera := Camera3D.new()
    review_camera.name = "RailMaterialPlayerWitnessCamera"
    review_camera.global_transform = active_camera.global_transform
    review_camera.fov = active_camera.fov
    review_camera.near = active_camera.near
    review_camera.far = active_camera.far
    main.add_child(review_camera)
    review_camera.current = true
    _hide_dynamic_review_noise(main, player)

    var rails := _rails(main)
    if rails.is_empty():
        _fail("rendered Rail_* geometry missing")
        return
    if rails.size() != int(runtime.call("applied_rail_count")):
        _fail("rail runtime count does not match rendered Rail_* geometry")
        return

    var transforms: Array[Transform3D] = []
    var sizes: Array[Vector3] = []
    for rail: CSGBox3D in rails:
        transforms.append(rail.global_transform)
        sizes.append(rail.size)

    runtime.call("set_enhanced_enabled", false)
    var legacy := await _capture(LEGACY_PATH)
    runtime.call("set_enhanced_enabled", true)
    var current := await _capture(CURRENT_PATH)
    if legacy == null or current == null:
        _fail("failed to capture rail legacy/current 1280x720 frames")
        return

    var current_materials: Array[Material] = []
    var control := _control_material()
    for rail: CSGBox3D in rails:
        current_materials.append(rail.material)
        rail.material = control
    var control_image := await _capture(CONTROL_PATH)
    for index: int in range(rails.size()):
        rails[index].material = current_materials[index]
    if control_image == null:
        _fail("failed to capture rail control frame")
        return

    var control_metrics := _diff_metrics(current, control_image)
    if float(control_metrics["changed_fraction"]) < MIN_CONTROL_CHANGED_FRACTION:
        _fail("shared rails occupy too little of legitimate player frame: %.6f" % float(control_metrics["changed_fraction"]))
        return
    if int(control_metrics["bbox_width"]) < MIN_CONTROL_BBOX_WIDTH or int(control_metrics["bbox_height"]) < MIN_CONTROL_BBOX_HEIGHT:
        _fail("shared rail footprint bbox too small: %dx%d" % [int(control_metrics["bbox_width"]), int(control_metrics["bbox_height"])])
        return

    for index: int in range(rails.size()):
        if not rails[index].global_transform.is_equal_approx(transforms[index]) or not rails[index].size.is_equal_approx(sizes[index]):
            _fail("rail geometry changed during material witness")
            return
    if not bool(runtime.call("enhanced_enabled")):
        _fail("production enhanced rail material was not restored")
        return

    var enhancement_metrics := _diff_metrics(legacy, current)
    var report := {
        "schema": "grand-bruxelles-rail-material-player-witness-v1",
        "target_road_osm_id": TARGET_OSM_ID,
        "target_road_name": str(player.get_meta("automatic_road_direct_source_name", "")),
        "source_path": SOURCE_PATH,
        "road_candidate_path": ROAD_CANDIDATE_PATH,
        "road_semantic_sha256": ROAD_SEMANTIC_SHA256,
        "source_license": "ODbL-1.0",
        "material_family": MATERIAL_FACTORY.MATERIAL_FAMILY,
        "rail_count": rails.size(),
        "ground_y": ground_y,
        "camera_transform": review_camera.global_transform,
        "camera_fov": review_camera.fov,
        "resolution": [1280, 720],
        "camera_copied_from_legitimate_player_witness": true,
        "dynamic_review_noise_hidden": true,
        "control_is_test_only": true,
        "geometry_changed": false,
        "runtime_material_restored": true,
        "control_diff_threshold": DIFF_THRESHOLD,
        "control_metrics": control_metrics,
        "legacy_vs_current_metrics": enhancement_metrics,
        "human_review_status": "pending",
        "claims": {
            "alignment_source_backed": true,
            "material_identity_source_backed": false,
            "alloy_claimed": false,
            "wear_pattern_claimed": false,
            "photometry_claimed": false,
        },
    }
    var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
    if file == null:
        _fail("could not write rail witness report")
        return
    file.store_string(JSON.stringify(report, "  "))
    file.close()

    print("BRUSSELS_RAIL_MATERIAL_PLAYER_WITNESS_OK: rails=%d control_fraction=%.6f control_bbox=%dx%d enhanced_fraction=%.6f enhanced_bbox=%dx%d ground_y=%.3f fov=%.2f human_review=pending" % [rails.size(), float(control_metrics["changed_fraction"]), int(control_metrics["bbox_width"]), int(control_metrics["bbox_height"]), float(enhancement_metrics["changed_fraction"]), int(enhancement_metrics["bbox_width"]), int(enhancement_metrics["bbox_height"]), ground_y, review_camera.fov])
    quit(0)
