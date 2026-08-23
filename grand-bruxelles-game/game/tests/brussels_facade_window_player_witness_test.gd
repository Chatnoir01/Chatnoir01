extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const SOURCE_PATH := "res://data/osm/vertical_slice_01.game.json"
const SOURCE_SHA256 := "a96123a6098c2a94dcef2622b6ea099c831f426e1ebfeb28a2edda74675c2493"
const TARGET_OSM_ID := 359177328
const TARGET_NAME_FRAGMENT := "Maurice Lemonnier"
const ARTIFACT_DIR := "res://artifacts/facade_window_player_witness"
const CURRENT_PATH := ARTIFACT_DIR + "/facade_windows_current.png"
const CONTROL_PATH := ARTIFACT_DIR + "/facade_windows_control.png"
const REPORT_PATH := ARTIFACT_DIR + "/facade_window_player_witness.json"
const DIFF_THRESHOLD := 0.08
const MIN_CONTROL_CHANGED_FRACTION := 0.005
const MIN_CONTROL_BBOX_WIDTH := 220
const MIN_CONTROL_BBOX_HEIGHT := 100

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_FACADE_WINDOW_PLAYER_WITNESS_FAIL: %s" % message)
    quit(1)

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

func _find_facade_windows(main: Node) -> MultiMeshInstance3D:
    var stack: Array[Node] = [main]
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        if node is MultiMeshInstance3D and str(node.name) == "CorridorFacadeWindows":
            return node as MultiMeshInstance3D
        for child: Node in node.get_children():
            stack.append(child)
    return null

func _control_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = Color(1.0, 0.0, 1.0, 1.0)
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
    return {
        "changed_pixels": changed,
        "changed_fraction": float(changed) / float(total),
        "bbox": [min_x, min_y, max_x, max_y] if changed > 0 else [],
        "bbox_width": 0 if changed == 0 else max_x - min_x + 1,
        "bbox_height": 0 if changed == 0 else max_y - min_y + 1,
    }

func _run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ARTIFACT_DIR))
    if FileAccess.get_sha256(SOURCE_PATH).to_lower() != SOURCE_SHA256:
        _fail("OSM source SHA drifted")
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

    for _frame: int in range(4):
        await process_frame
        await physics_frame
    var active_camera := root.get_camera_3d()
    if active_camera == null:
        _fail("production player camera missing after source-backed road resolve")
        return
    var review_camera := Camera3D.new()
    review_camera.name = "FacadeWindowPlayerWitnessCamera"
    review_camera.global_transform = active_camera.global_transform
    review_camera.fov = active_camera.fov
    review_camera.near = active_camera.near
    review_camera.far = active_camera.far
    main.add_child(review_camera)
    review_camera.current = true
    _hide_dynamic_review_noise(main, player)

    var windows := _find_facade_windows(main)
    if windows == null or windows.multimesh == null or windows.multimesh.mesh == null:
        _fail("CorridorFacadeWindows MultiMesh missing")
        return
    var instance_count := windows.multimesh.instance_count
    if instance_count <= 0:
        _fail("CorridorFacadeWindows has no instances")
        return
    var mesh := windows.multimesh.mesh
    var original_material := mesh.surface_get_material(0)
    if original_material == null:
        _fail("facade window material missing")
        return
    var original_transform := windows.global_transform
    var original_visible_count := windows.multimesh.visible_instance_count

    var current := await _capture(CURRENT_PATH)
    mesh.surface_set_material(0, _control_material())
    var control := await _capture(CONTROL_PATH)
    mesh.surface_set_material(0, original_material)
    if current == null or control == null:
        _fail("failed to capture facade-window 1280x720 frames")
        return
    if not windows.global_transform.is_equal_approx(original_transform) or windows.multimesh.visible_instance_count != original_visible_count:
        _fail("facade window geometry/visibility changed during witness")
        return
    if mesh.surface_get_material(0) != original_material:
        _fail("facade window production material was not restored")
        return

    var metrics := _diff_metrics(current, control)
    var report := {
        "schema": "grand-bruxelles-facade-window-player-witness-v1",
        "target_road_osm_id": TARGET_OSM_ID,
        "target_road_name": str(player.get_meta("automatic_road_direct_source_name", "")),
        "source_path": SOURCE_PATH,
        "source_sha256": SOURCE_SHA256,
        "source_license": "ODbL-1.0",
        "window_instance_count": instance_count,
        "camera_fov": review_camera.fov,
        "resolution": [1280, 720],
        "camera_copied_from_legitimate_player_witness": true,
        "dynamic_review_noise_hidden": true,
        "control_is_test_only": true,
        "geometry_changed": false,
        "runtime_changed": false,
        "control_diff_threshold": DIFF_THRESHOLD,
        "control_metrics": metrics,
        "candidate_status": "REVIEWABLE" if float(metrics["changed_fraction"]) >= MIN_CONTROL_CHANGED_FRACTION and int(metrics["bbox_width"]) >= MIN_CONTROL_BBOX_WIDTH and int(metrics["bbox_height"]) >= MIN_CONTROL_BBOX_HEIGHT else "REJECT_LOW_SCREEN_COVERAGE",
        "art_pass_authorized": false,
        "claims": {
            "building_footprint_placement_source_backed": true,
            "window_presence_source_backed": false,
            "window_dimensions_source_backed": false,
            "window_material_identity_source_backed": false,
            "window_grid_source_backed": false,
        },
    }
    var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
    if file == null:
        _fail("could not write facade-window witness report")
        return
    file.store_string(JSON.stringify(report, "  "))
    file.close()

    if str(report["candidate_status"]) == "REJECT_LOW_SCREEN_COVERAGE":
        _fail("facade windows occupy too little of legitimate player frame: fraction=%.6f bbox=%dx%d" % [float(metrics["changed_fraction"]), int(metrics["bbox_width"]), int(metrics["bbox_height"])])
        return

    print("BRUSSELS_FACADE_WINDOW_PLAYER_WITNESS_OK: windows=%d control_fraction=%.6f bbox=%dx%d fov=%.2f human_review=pending" % [instance_count, float(metrics["changed_fraction"]), int(metrics["bbox_width"]), int(metrics["bbox_height"]), review_camera.fov])
    quit(0)
