extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const SOURCE_PATH := "res://data/osm/vertical_slice_01.game.json"
const RUNTIME_INDEX_PATH := "res://data/runtime/road_destination_runtime_index.json"
const TARGET_OSM_ID := 359177328
const ARTIFACT_DIR := "res://artifacts/base_ground_surface_player_witness"
const BEFORE_PATH := ARTIFACT_DIR + "/base_ground_before.png"
const AFTER_PATH := ARTIFACT_DIR + "/base_ground_after.png"
const REPORT_PATH := ARTIFACT_DIR + "/base_ground_surface_player_witness.json"
const DIFF_THRESHOLD := 0.03
const MIN_CHANGED_FRACTION := 0.18
const MAX_CHANGED_FRACTION := 0.70
const MIN_BBOX_WIDTH := 700
const MIN_BBOX_HEIGHT := 250
const EXPECTED_REVISION := 8
const EXPECTED_CALIBRATION_REVISION := 2
const EXPECTED_PROFILE := "authored_near_field_isotropic_variation_v8"

func _initialize() -> void:
    call_deferred("_run")
func _fail(message: String) -> void:
    push_error("BRUSSELS_BASE_GROUND_SURFACE_PLAYER_WITNESS_FAIL: %s" % message)
    quit(1)

func _parse_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed as Dictionary if parsed is Dictionary else {}

func _expected_source_sha_from_runtime_index() -> String:
    var index := _parse_json(RUNTIME_INDEX_PATH)
    if index.is_empty() or str(index.get("format", "")) != "grand-bruxelles-road-runtime-index-v1":
        return ""
    var documents: Variant = index.get("documents", [])
    if not documents is Array:
        return ""
    for raw: Variant in documents:
        if not raw is Dictionary:
            continue
        var descriptor := raw as Dictionary
        var path := str(descriptor.get("path", "")).trim_prefix("res://")
        if path == SOURCE_PATH.trim_prefix("res://"):
            return str(descriptor.get("sha256", "")).to_lower()
    return ""

func _legacy_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.135, 0.14, 0.14, 1.0)
    material.metallic = 0.03
    material.roughness = 0.88
    return material

func _capture(path: String) -> Image:
    for _frame: int in range(5):
        await process_frame
    await RenderingServer.frame_post_draw
    var image := root.get_texture().get_image()
    if image == null or image.is_empty() or image.get_size() != Vector2i(1280, 720):
        return null
    return image if image.save_png(path) == OK else null

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

func _diff_metrics(before: Image, after: Image) -> Dictionary:
    var changed := 0
    var min_x := before.get_width()
    var min_y := before.get_height()
    var max_x := -1
    var max_y := -1
    var delta_sum := 0.0
    var total := before.get_width() * before.get_height()
    for y: int in range(before.get_height()):
        for x: int in range(before.get_width()):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
            if delta <= DIFF_THRESHOLD:
                continue
            changed += 1
            delta_sum += delta
            min_x = mini(min_x, x)
            min_y = mini(min_y, y)
            max_x = maxi(max_x, x)
            max_y = maxi(max_y, y)
    return {
        "changed_pixels": changed,
        "changed_fraction": float(changed) / float(total),
        "mean_changed_delta": delta_sum / float(maxi(changed, 1)),
        "bbox": [min_x, min_y, max_x, max_y] if changed > 0 else [],
        "bbox_width": 0 if changed == 0 else max_x - min_x + 1,
        "bbox_height": 0 if changed == 0 else max_y - min_y + 1,
    }

func _run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ARTIFACT_DIR))
    var expected_source_sha := _expected_source_sha_from_runtime_index()
    var actual_source_sha := FileAccess.get_sha256(SOURCE_PATH).to_lower()
    if expected_source_sha.is_empty() or actual_source_sha.is_empty() or expected_source_sha != actual_source_sha:
        _fail("road source/index freshness blocker: runtime index SHA does not match live OSM slice; owned by source-index workstream")
        return

    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    for _frame: int in range(16):
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
    if not bool(player.get_meta("automatic_road_direct_source_sightline_clear", false)):
        _fail("source-backed player sightline proof missing")
        return
    for _frame: int in range(4):
        await process_frame
        await physics_frame
    var active_camera := root.get_camera_3d()
    if active_camera == null:
        _fail("production player camera missing")
        return
    var review_camera := Camera3D.new()
    review_camera.name = "BaseGroundSurfacePlayerWitnessCamera"
    review_camera.global_transform = active_camera.global_transform
    review_camera.fov = active_camera.fov
    review_camera.near = active_camera.near
    review_camera.far = active_camera.far
    main.add_child(review_camera)
    review_camera.current = true
    _hide_dynamic_review_noise(main, player)

    var ground := main.get_node_or_null("Ground") as CSGBox3D
    if ground == null or not ground.material is ShaderMaterial:
        _fail("production Ground authored material missing")
        return
    var production_material := ground.material as ShaderMaterial
    if int(production_material.get_meta("presentation_revision", 0)) != EXPECTED_REVISION or int(production_material.get_meta("calibration_revision", 0)) != EXPECTED_CALIBRATION_REVISION:
        _fail("production Ground revision mismatch")
        return
    if str(production_material.get_meta("visual_recipe_profile", "")) != EXPECTED_PROFILE:
        _fail("production Ground profile mismatch")
        return
    if not bool(production_material.get_meta("far_field_contrast_zero", false)) or int(production_material.get_meta("anti_banding_revision", 0)) != 2:
        _fail("v8 anti-banding material contract missing")
        return
    if bool(production_material.get_meta("surface_composition_claimed", true)) or bool(production_material.get_meta("surface_identity_claimed", true)) or bool(production_material.get_meta("microtexture_scale_source_measured", true)):
        _fail("authored Ground presentation manufactured source semantics")
        return

    ground.material = _legacy_material()
    var before := await _capture(BEFORE_PATH)
    ground.material = production_material
    var after := await _capture(AFTER_PATH)
    if before == null or after == null:
        _fail("failed to capture exact 1280x720 before/after frames")
        return
    var metrics := _diff_metrics(before, after)
    var fraction := float(metrics["changed_fraction"])
    if fraction < MIN_CHANGED_FRACTION or fraction > MAX_CHANGED_FRACTION:
        _fail("base-ground player response outside frozen range: %.6f" % fraction)
        return
    if int(metrics["bbox_width"]) < MIN_BBOX_WIDTH or int(metrics["bbox_height"]) < MIN_BBOX_HEIGHT:
        _fail("base-ground player footprint too small: %dx%d" % [int(metrics["bbox_width"]), int(metrics["bbox_height"])])
        return

    var report := {
        "schema": "grand-bruxelles-base-ground-surface-player-witness-v3",
        "target_osm_id": TARGET_OSM_ID,
        "target_name": str(player.get_meta("automatic_road_direct_source_name", "")),
        "source_path": SOURCE_PATH,
        "source_sha256": actual_source_sha,
        "runtime_index_source_sha256": expected_source_sha,
        "source_index_fresh": true,
        "source_license": "ODbL-1.0",
        "resolution": [1280, 720],
        "camera_fov": review_camera.fov,
        "camera_copied_from_legitimate_player_witness": true,
        "presentation_revision": EXPECTED_REVISION,
        "calibration_revision": EXPECTED_CALIBRATION_REVISION,
        "visual_recipe_profile": EXPECTED_PROFILE,
        "anti_banding_revision": 2,
        "far_field_contrast_zero": true,
        "geometry_changed": false,
        "collision_changed": false,
        "ground_material_only": true,
        "source_surface_composition_claimed": false,
        "source_surface_identity_claimed": false,
        "microtexture_scale_source_measured": false,
        "human_full_frame_verdict": "pending",
        "diff_threshold": DIFF_THRESHOLD,
        "metrics": metrics,
    }
    var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
    if file == null:
        _fail("could not write witness report")
        return
    file.store_string(JSON.stringify(report, "  "))
    file.close()
    print("BRUSSELS_BASE_GROUND_SURFACE_PLAYER_WITNESS_OK: changed_fraction=%.6f mean_delta=%.6f bbox=%dx%d fov=%.2f revision=%d calibration=%d profile=%s human_review=pending" % [fraction, float(metrics["mean_changed_delta"]), int(metrics["bbox_width"]), int(metrics["bbox_height"]), review_camera.fov, EXPECTED_REVISION, EXPECTED_CALIBRATION_REVISION, EXPECTED_PROFILE])
    quit(0)
