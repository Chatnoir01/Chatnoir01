extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const MATERIAL_FACTORY := preload("res://game/scripts/brussels_osm_road_surface_material.gd")
const TARGET_OSM_ID := 359177328
const EXPECTED_PRESENTATION_REVISION := 2
const ARTIFACT_DIR := "res://artifacts/road_surface_microtexture_ab"
const BEFORE_PATH := ARTIFACT_DIR + "/road_surface_before.png"
const AFTER_PATH := ARTIFACT_DIR + "/road_surface_after.png"
const REPORT_PATH := ARTIFACT_DIR + "/road_surface_microtexture_ab.json"
const PIXEL_GT3 := 3.0 / 255.0
const PIXEL_GT8 := 8.0 / 255.0
const MIN_GT3_FRACTION := 0.002
const MAX_GT3_FRACTION := 0.08
const MIN_BBOX_WIDTH := 220
const MIN_BBOX_HEIGHT := 80

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_ROAD_SURFACE_MICROTEXTURE_FAIL: %s" % message)
    quit(1)

func _capture(path: String) -> Image:
    for _frame: int in range(3):
        await process_frame
    await RenderingServer.frame_post_draw
    var image := root.get_texture().get_image()
    if image == null or image.is_empty() or image.get_size() != Vector2i(1280, 720):
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

func _road_materials(main: Node) -> Array[ShaderMaterial]:
    var found: Array[ShaderMaterial] = []
    var seen := {}
    var stack: Array[Node] = [main]
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        if node is CSGBox3D:
            var material := (node as CSGBox3D).material
            if material is ShaderMaterial and str(material.get_meta("material_family", "")) == MATERIAL_FACTORY.MATERIAL_FAMILY:
                var id := material.get_instance_id()
                if not seen.has(id):
                    seen[id] = true
                    found.append(material as ShaderMaterial)
        for child: Node in node.get_children():
            stack.append(child)
    return found

func _metrics(before: Image, after: Image) -> Dictionary:
    var gt3 := 0
    var gt8 := 0
    var min_x := before.get_width()
    var min_y := before.get_height()
    var max_x := -1
    var max_y := -1
    for y: int in range(before.get_height()):
        for x: int in range(before.get_width()):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
            if delta > PIXEL_GT3:
                gt3 += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
            if delta > PIXEL_GT8:
                gt8 += 1
    var total := before.get_width() * before.get_height()
    return {
        "fraction_gt_3_rgb": float(gt3) / float(total),
        "fraction_gt_8_rgb": float(gt8) / float(total),
        "bbox_width": 0 if max_x < min_x else max_x - min_x + 1,
        "bbox_height": 0 if max_y < min_y else max_y - min_y + 1,
        "bbox": [] if gt3 == 0 else [min_x, min_y, max_x, max_y],
    }

func _run() -> void:
    if not "PRESENTATION_REVISION" in MATERIAL_FACTORY or int(MATERIAL_FACTORY.PRESENTATION_REVISION) != EXPECTED_PRESENTATION_REVISION:
        _fail("road surface presentation revision 2 missing")
        return
    if not "MICRO_GRAIN_STRENGTH" in MATERIAL_FACTORY or float(MATERIAL_FACTORY.MICRO_GRAIN_STRENGTH) <= 0.0:
        _fail("road surface micro-grain contract missing")
        return

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ARTIFACT_DIR))
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
        _fail("legitimate Lemonnier player witness unavailable")
        return
    for _frame: int in range(4):
        await process_frame
        await physics_frame
    var active_camera := root.get_camera_3d()
    if active_camera == null:
        _fail("production player camera missing")
        return

    var review_camera := Camera3D.new()
    review_camera.global_transform = active_camera.global_transform
    review_camera.fov = active_camera.fov
    review_camera.near = active_camera.near
    review_camera.far = active_camera.far
    main.add_child(review_camera)
    review_camera.current = true
    _hide_dynamic_review_noise(main, player)

    var materials := _road_materials(main)
    if materials.size() != 2:
        _fail("expected exactly two shared road materials, got %d" % materials.size())
        return
    var authored_strength := float(MATERIAL_FACTORY.MICRO_GRAIN_STRENGTH)
    for material: ShaderMaterial in materials:
        material.set_shader_parameter("micro_grain_strength", 0.0)
    var before := await _capture(BEFORE_PATH)
    if before == null:
        _fail("failed BEFORE capture")
        return
    for material: ShaderMaterial in materials:
        material.set_shader_parameter("micro_grain_strength", authored_strength)
    var after := await _capture(AFTER_PATH)
    if after == null:
        _fail("failed AFTER capture")
        return

    var metrics := _metrics(before, after)
    if float(metrics["fraction_gt_3_rgb"]) < MIN_GT3_FRACTION:
        _fail("road microtexture too weak: %.6f < %.6f" % [float(metrics["fraction_gt_3_rgb"]), MIN_GT3_FRACTION])
        return
    if float(metrics["fraction_gt_3_rgb"]) > MAX_GT3_FRACTION:
        _fail("road microtexture too dominant: %.6f > %.6f" % [float(metrics["fraction_gt_3_rgb"]), MAX_GT3_FRACTION])
        return
    if int(metrics["bbox_width"]) < MIN_BBOX_WIDTH or int(metrics["bbox_height"]) < MIN_BBOX_HEIGHT:
        _fail("road microtexture footprint too small: %dx%d" % [int(metrics["bbox_width"]), int(metrics["bbox_height"])])
        return

    var report := {
        "schema": "grand-bruxelles-road-surface-microtexture-ab-v1",
        "target_osm_id": TARGET_OSM_ID,
        "presentation_revision": EXPECTED_PRESENTATION_REVISION,
        "material_family": MATERIAL_FACTORY.MATERIAL_FAMILY,
        "micro_grain_strength": authored_strength,
        "camera_copied_from_legitimate_player_witness": true,
        "camera_transform": review_camera.global_transform,
        "camera_fov": review_camera.fov,
        "resolution": [1280, 720],
        "geometry_changed": false,
        "source": "OpenStreetMap contributors via Overpass API",
        "license": "ODbL-1.0",
        "surface_composition_claimed": false,
        "aggregate_scale_claimed": false,
        "wear_pattern_claimed": false,
        "road_marking_claimed": false,
        "microtexture_scale_source_measured": false,
        "human_review_status": "pending",
        "metrics": metrics,
    }
    var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
    if file == null:
        _fail("could not write A/B report")
        return
    file.store_string(JSON.stringify(report, "  "))
    file.close()
    print("BRUSSELS_ROAD_SURFACE_MICROTEXTURE_OK: gt3=%.6f gt8=%.6f bbox=%dx%d fov=%.2f human_review=pending" % [float(metrics["fraction_gt_3_rgb"]), float(metrics["fraction_gt_8_rgb"]), int(metrics["bbox_width"]), int(metrics["bbox_height"]), review_camera.fov])
    quit(0)
