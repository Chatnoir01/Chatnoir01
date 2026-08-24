extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const SOURCE_PATH := "res://data/osm/vertical_slice_01.game.json"
const TARGET_OSM_ID := 359177328
const TARGET_SOURCE := "OpenStreetMap contributors via Overpass API"
const TARGET_LICENSE := "ODbL-1.0"
const ARTIFACT_DIR := "res://artifacts/base_ground_surface_player_witness"
const BEFORE_PATH := ARTIFACT_DIR + "/base_ground_before.png"
const AFTER_PATH := ARTIFACT_DIR + "/base_ground_after.png"
const REPORT_PATH := ARTIFACT_DIR + "/base_ground_surface_player_witness.json"
const DIFF_THRESHOLD := 0.03
const MIN_CHANGED_FRACTION := 0.18
const MAX_CHANGED_FRACTION := 0.70
const MIN_BBOX_WIDTH := 700
const MIN_BBOX_HEIGHT := 250
const EXPECTED_REVISION := 6
const PRODUCTION_BASE_SHA := "a037436b408889bd4895c225da4a98da886dbfef"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_BASE_GROUND_SURFACE_PLAYER_WITNESS_FAIL: %s" % message)
    quit(1)

func _source_identity() -> Dictionary:
    if not FileAccess.file_exists(SOURCE_PATH):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    var data := parsed as Dictionary
    if str(data.get("source", "")) != TARGET_SOURCE or str(data.get("license", "")) != TARGET_LICENSE:
        return {}
    for raw: Variant in data.get("roads", []):
        if typeof(raw) != TYPE_DICTIONARY:
            continue
        var road := raw as Dictionary
        if int(road.get("osm_id", 0)) == TARGET_OSM_ID:
            return {
                "name": str(road.get("name", "")),
                "class": str(road.get("class", "")),
                "drivable": bool(road.get("drivable", false)),
                "sha256": FileAccess.get_sha256(SOURCE_PATH).to_lower(),
            }
    return {}

func _capture(path: String) -> Image:
    for _frame: int in range(5):
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
    var fraction := float(changed) / float(total)
    var bbox_width := 0 if max_x < min_x else max_x - min_x + 1
    var bbox_height := 0 if max_y < min_y else max_y - min_y + 1
    return {
        "changed_pixels": changed,
        "changed_fraction": fraction,
        "mean_changed_delta": delta_sum / float(maxi(changed, 1)),
        "bbox": [min_x, min_y, max_x, max_y] if changed > 0 else [],
        "bbox_width": bbox_width,
        "bbox_height": bbox_height,
    }

func _run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ARTIFACT_DIR))
    var source := _source_identity()
    if source.is_empty():
        _fail("current OSM source identity or target Lemonnier road is missing")
        return
    if not bool(source.get("drivable", false)):
        _fail("target Lemonnier road is no longer drivable in source snapshot")
        return

    var main := MAIN_SCENE.instantiate()
    root.add_child(main)

    var runtime := root.get_node_or_null("BrusselsBaseGroundSurfaceRuntime")
    if runtime == null:
        _fail("BrusselsBaseGroundSurfaceRuntime autoload missing")
        return
    for _frame: int in range(180):
        await process_frame
        if bool(runtime.call("ready_complete")):
            break
    if not bool(runtime.call("ready_complete")):
        _fail("base-ground runtime did not finish binding")
        return
    if bool(runtime.call("failed")):
        _fail("base-ground runtime failed closed")
        return
    if str(runtime.call("material_family")) != "brussels_base_ground_surface_v1":
        _fail("base-ground material family drifted")
        return
    if int(runtime.call("presentation_revision")) != EXPECTED_REVISION:
        _fail("base-ground presentation revision %d missing" % EXPECTED_REVISION)
        return

    for _frame: int in range(12):
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
    if ground == null:
        _fail("production Ground missing")
        return
    var position_before := ground.position
    var size_before := ground.size
    var collision_before := ground.use_collision

    var production_material := ground.material
    if not production_material is ShaderMaterial:
        _fail("production Ground material is not the authored procedural ShaderMaterial")
        return
    var shader_material := production_material as ShaderMaterial
    if shader_material.shader == null:
        _fail("production Ground shader missing")
        return
    var shader_code := shader_material.shader.code
    if not shader_code.contains("authored_ground_tone") or not shader_code.contains("authored_isotropic_noise"):
        _fail("production Ground shader lacks isotropic authored-ground contract")
        return
    if not shader_code.contains("ROT_A") or not shader_code.contains("ROT_B"):
        _fail("production Ground shader lacks multi-directional rotation contract")
        return
    if shader_code.contains("CAMERA_POSITION_WORLD"):
        _fail("production Ground shader must not use camera-dependent presentation bands")
        return
    if shader_code.contains("TIME"):
        _fail("production Ground shader must remain deterministic and time-independent")
        return
    if int(shader_material.get_meta("presentation_revision", 0)) != EXPECTED_REVISION:
        _fail("production Ground material metadata revision drifted")
        return
    if not bool(shader_material.get_meta("multidirectional_isotropic_recipe", false)):
        _fail("production Ground material isotropic metadata missing")
        return
    if bool(shader_material.get_meta("surface_composition_claimed", true)):
        _fail("production Ground material must not claim source-backed composition")
        return

    runtime.call("set_enhanced_enabled", false)
    var before := await _capture(BEFORE_PATH)
    runtime.call("set_enhanced_enabled", true)
    var after := await _capture(AFTER_PATH)
    if before == null or after == null:
        _fail("failed to capture exact 1280x720 before/after frames")
        return

    if ground.position != position_before or ground.size != size_before or ground.use_collision != collision_before:
        _fail("Ground geometry/collision changed during material A/B")
        return

    var metrics := _diff_metrics(before, after)
    var fraction := float(metrics["changed_fraction"])
    if fraction < MIN_CHANGED_FRACTION:
        _fail("authored base-ground pass changes too little of legitimate player frame: %.6f" % fraction)
        return
    if fraction > MAX_CHANGED_FRACTION:
        _fail("base-ground pass leaks beyond bounded screen footprint: %.6f" % fraction)
        return
    if int(metrics["bbox_width"]) < MIN_BBOX_WIDTH or int(metrics["bbox_height"]) < MIN_BBOX_HEIGHT:
        _fail("base-ground player footprint too small: %dx%d" % [int(metrics["bbox_width"]), int(metrics["bbox_height"])])
        return

    var report := {
        "schema": "grand-bruxelles-base-ground-surface-player-witness-v2",
        "production_base_sha": PRODUCTION_BASE_SHA,
        "presentation_revision": EXPECTED_REVISION,
        "target_osm_id": TARGET_OSM_ID,
        "target_name": str(player.get_meta("automatic_road_direct_source_name", source.get("name", ""))),
        "source_path": SOURCE_PATH,
        "source_sha256": str(source.get("sha256", "")),
        "source_license": TARGET_LICENSE,
        "resolution": [1280, 720],
        "camera_transform": review_camera.global_transform,
        "camera_fov": review_camera.fov,
        "camera_copied_from_legitimate_player_witness": true,
        "dynamic_review_noise_hidden": true,
        "legacy_material_captured_from_current_main": true,
        "geometry_changed": false,
        "collision_changed": false,
        "ground_material_only": true,
        "procedural_only": true,
        "time_dependent": false,
        "camera_dependent_recipe": false,
        "multidirectional_isotropic_recipe": true,
        "source_surface_composition_claimed": false,
        "prior_v5_human_verdict": "AMELIORER_DO_NOT_SHIP_BANDING",
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

    print("BRUSSELS_BASE_GROUND_SURFACE_PLAYER_WITNESS_OK: revision=%d changed_fraction=%.6f mean_delta=%.6f bbox=%dx%d fov=%.2f human_review=pending" % [EXPECTED_REVISION, fraction, float(metrics["mean_changed_delta"]), int(metrics["bbox_width"]), int(metrics["bbox_height"]), review_camera.fov])
    quit(0)
