extends SceneTree

const JETTE_ZONE := "res://game/zones/laeken_jette/jette_phase2_zone.gd"
const JETTE_DATA := "res://data/osm/zones/jette/environment.game.json"
const SPAWN := Vector3(-687.700268506218, 1.05, -4952.774160383269)
const BEFORE := "res://artifacts/visual/tree_lod_full_detail_before.png"
const AFTER := "res://artifacts/visual/tree_lod_distance_after.png"
const DIAG_BEFORE := "res://artifacts/visual/tree_lod_signal_before.png"
const DIAG_AFTER := "res://artifacts/visual/tree_lod_signal_after.png"
const EXPECTED_RENDERED_TREES := 170
const EXPECTED_LOBES_PER_NEAR_TREE := 8
const EXPECTED_LOBES_PER_FAR_TREE := 3
const MAX_CHANGED_GT3 := 0.015
const MAX_CHANGED_GT8 := 0.012
const MIN_SIGNAL_CHANGED_GT3 := 0.00005

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_TREE_DISTANCE_LOD_VISUAL_FAIL: %s" % message)
    quit(1)

func _read(path: String) -> String:
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    return file.get_as_text() if file != null else ""

func _capture(viewport: SubViewport, path: String) -> Image:
    RenderingServer.force_draw()
    await process_frame
    var image: Image = viewport.get_texture().get_image()
    if image == null or image.is_empty():
        return null
    var absolute: String = ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    return image if image.save_png(absolute) == OK else null

func _diff_metrics(before: Image, after: Image) -> Dictionary:
    var changed_gt3: int = 0
    var changed_gt8: int = 0
    var total: int = 0
    var min_x: int = before.get_width()
    var min_y: int = before.get_height()
    var max_x: int = -1
    var max_y: int = -1
    for y: int in range(0, before.get_height(), 2):
        for x: int in range(0, before.get_width(), 2):
            total += 1
            var a: Color = before.get_pixel(x, y)
            var b: Color = after.get_pixel(x, y)
            var delta: float = maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) * 255.0
            if delta > 3.0:
                changed_gt3 += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
            if delta > 8.0:
                changed_gt8 += 1
    var bbox_width: int = 0 if max_x < min_x else max_x - min_x + 1
    var bbox_height: int = 0 if max_y < min_y else max_y - min_y + 1
    return {
        "changed_gt3": float(changed_gt3) / float(maxi(total, 1)),
        "changed_gt8": float(changed_gt8) / float(maxi(total, 1)),
        "bbox_width": bbox_width,
        "bbox_height": bbox_height,
    }

func _nearest_tree() -> Vector3:
    var parsed: Variant = JSON.parse_string(_read(JETTE_DATA))
    if typeof(parsed) != TYPE_DICTIONARY:
        return Vector3(INF, INF, INF)
    var nearest: Vector3 = Vector3(INF, INF, INF)
    var nearest_distance: float = INF
    var points: Array = (parsed as Dictionary).get("environment_points", []) as Array
    for row_variant: Variant in points:
        if not row_variant is Dictionary:
            continue
        var row: Dictionary = row_variant as Dictionary
        if str(row.get("kind", "")) != "tree":
            continue
        var position_value: Array = row.get("position", []) as Array
        if position_value.size() < 2:
            continue
        var world: Vector3 = Vector3(float(position_value[0]), 0.0, float(position_value[1]))
        var distance: float = Vector2(world.x - SPAWN.x, world.z - SPAWN.z).length()
        if distance < nearest_distance:
            nearest_distance = distance
            nearest = world
    return nearest

func _tree_batch_count(runtime: Node) -> int:
    var count: int = 0
    for name_value: String in ["TreeTrunks", "TreeFoliageDark", "TreeFoliageLight"]:
        var batch: MultiMeshInstance3D = runtime.get_node_or_null(name_value) as MultiMeshInstance3D
        if batch != null and batch.multimesh != null:
            count += 1
    return count

func _hide_non_tree_geometry(zone: Node, runtime: Node) -> void:
    var keep := {"TreeTrunks": true, "TreeFoliageDark": true, "TreeFoliageLight": true}
    for node_variant: Node in zone.find_children("*", "GeometryInstance3D", true, false):
        var geometry := node_variant as GeometryInstance3D
        if geometry == null:
            continue
        if geometry.get_parent() == runtime and keep.has(String(geometry.name)):
            geometry.visible = true
        else:
            geometry.visible = false

func _run() -> void:
    if not FileAccess.file_exists(JETTE_ZONE) or not FileAccess.file_exists(JETTE_DATA):
        _fail("Jette source-backed environment witness inputs missing")
        return

    var nearest_tree: Vector3 = _nearest_tree()
    if not is_finite(nearest_tree.x):
        _fail("could not resolve a source-backed Jette tree")
        return

    var viewport := SubViewport.new()
    viewport.size = Vector2i(1280, 720)
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)

    var world_root := Node3D.new()
    viewport.add_child(world_root)

    var player := CharacterBody3D.new()
    player.name = "Player"
    player.add_to_group("player")
    player.position = SPAWN
    world_root.add_child(player)

    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
    light.light_energy = 1.25
    world_root.add_child(light)

    var environment := WorldEnvironment.new()
    environment.environment = Environment.new()
    environment.environment.background_mode = Environment.BG_COLOR
    environment.environment.background_color = Color(0.62, 0.72, 0.82)
    environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.environment.ambient_light_color = Color(0.55, 0.58, 0.62)
    environment.environment.ambient_light_energy = 0.7
    world_root.add_child(environment)

    var zone_script: Script = load(JETTE_ZONE) as Script
    var zone: Node3D = zone_script.new() as Node3D
    world_root.add_child(zone)
    for _frame: int in range(12):
        await process_frame

    var runtime: Node3D = zone.get_node_or_null("BrusselsOsmEnvironment") as Node3D
    if runtime == null:
        _fail("Jette generic environment runtime missing")
        return
    runtime.set_process(false)

    var camera_direction: Vector3 = Vector3(SPAWN.x - nearest_tree.x, 0.0, SPAWN.z - nearest_tree.z).normalized()
    if camera_direction.length_squared() < 0.5:
        camera_direction = Vector3.FORWARD
    var camera := Camera3D.new()
    camera.position = nearest_tree + camera_direction * 12.0 + Vector3(0.0, 1.65, 0.0)
    camera.look_at_from_position(camera.position, nearest_tree + Vector3(0.0, 2.8, 0.0), Vector3.UP)
    camera.fov = 70.0
    camera.current = true
    world_root.add_child(camera)

    runtime.set("tree_full_detail_radius_m", float(runtime.get("render_radius_m")))
    runtime.call("_rebuild", SPAWN)
    for _frame: int in range(3):
        await process_frame
    var baseline_counts: Dictionary = (runtime.get("last_tree_lod_counts") as Dictionary).duplicate(true)
    var baseline_render_counts: Dictionary = (runtime.get("last_render_counts") as Dictionary).duplicate(true)
    if int(baseline_render_counts.get("tree", 0)) != EXPECTED_RENDERED_TREES:
        _fail("full-detail baseline tree count drifted")
        return
    if int(baseline_counts.get("far", -1)) != 0 or int(baseline_counts.get("near", 0)) != EXPECTED_RENDERED_TREES:
        _fail("full-detail baseline did not keep all rendered trees near-detail")
        return
    var baseline_foliage := int(baseline_counts.get("foliage_instances", 0))
    if baseline_foliage != EXPECTED_RENDERED_TREES * EXPECTED_LOBES_PER_NEAR_TREE:
        _fail("full-detail baseline foliage instance count drifted")
        return
    if _tree_batch_count(runtime) != 3:
        _fail("full-detail baseline lost deterministic three-batch tree renderer")
        return
    var before: Image = await _capture(viewport, BEFORE)

    runtime.set("tree_full_detail_radius_m", 140.0)
    runtime.call("_rebuild", SPAWN)
    for _frame: int in range(3):
        await process_frame
    var optimized_counts: Dictionary = (runtime.get("last_tree_lod_counts") as Dictionary).duplicate(true)
    var optimized_render_counts: Dictionary = (runtime.get("last_render_counts") as Dictionary).duplicate(true)
    if int(optimized_render_counts.get("tree", 0)) != EXPECTED_RENDERED_TREES:
        _fail("distance LOD changed source-backed rendered tree count")
        return
    var near_count := int(optimized_counts.get("near", 0))
    var far_count := int(optimized_counts.get("far", 0))
    var optimized_foliage := int(optimized_counts.get("foliage_instances", 0))
    if near_count + far_count != EXPECTED_RENDERED_TREES or near_count <= 0 or far_count <= 0:
        _fail("real-scene LOD partition is invalid")
        return
    var expected_optimized_foliage := near_count * EXPECTED_LOBES_PER_NEAR_TREE + far_count * EXPECTED_LOBES_PER_FAR_TREE
    if optimized_foliage != expected_optimized_foliage:
        _fail("real-scene LOD foliage count does not match near/far contract")
        return
    var reduction := 1.0 - float(optimized_foliage) / float(maxi(baseline_foliage, 1))
    if reduction < 0.30:
        _fail("real-scene foliage reduction is too small: %.2f%%" % [reduction * 100.0])
        return
    if _tree_batch_count(runtime) != 3:
        _fail("distance LOD changed deterministic three-batch tree renderer")
        return
    var after: Image = await _capture(viewport, AFTER)
    if before == null or after == null:
        _fail("tree LOD A/B capture failed")
        return

    var full_metrics := _diff_metrics(before, after)
    var full_gt3 := float(full_metrics["changed_gt3"])
    var full_gt8 := float(full_metrics["changed_gt8"])
    if full_gt3 > MAX_CHANGED_GT3 or full_gt8 > MAX_CHANGED_GT8:
        _fail("tree LOD changes too much of the player frame: gt3=%.4f%% gt8=%.4f%%" % [full_gt3 * 100.0, full_gt8 * 100.0])
        return

    # Keep the exact same camera and production transforms, but isolate the tree
    # renderer for a diagnostic signal pass. This proves that the LOD actually
    # changes rendered tree pixels without rewarding visible degradation in the
    # normal full-frame acceptance image.
    runtime.set("tree_full_detail_radius_m", float(runtime.get("render_radius_m")))
    runtime.call("_rebuild", SPAWN)
    for _frame: int in range(3):
        await process_frame
    _hide_non_tree_geometry(zone, runtime)
    var signal_before: Image = await _capture(viewport, DIAG_BEFORE)

    runtime.set("tree_full_detail_radius_m", 140.0)
    runtime.call("_rebuild", SPAWN)
    for _frame: int in range(3):
        await process_frame
    _hide_non_tree_geometry(zone, runtime)
    var signal_after: Image = await _capture(viewport, DIAG_AFTER)
    if signal_before == null or signal_after == null:
        _fail("tree-only diagnostic A/B capture failed")
        return

    var signal_metrics := _diff_metrics(signal_before, signal_after)
    var signal_gt3 := float(signal_metrics["changed_gt3"])
    if signal_gt3 < MIN_SIGNAL_CHANGED_GT3:
        _fail("tree-only diagnostic did not prove a measurable rendered LOD delta")
        return

    print("BRUSSELS_TREE_DISTANCE_LOD_VISUAL_METRICS: trees=%d near=%d far=%d foliage=%d->%d reduction=%.2f%% full_gt3=%.4f%% full_gt8=%.4f%% full_bbox=%dx%d signal_gt3=%.4f%% signal_bbox=%dx%d" % [EXPECTED_RENDERED_TREES, near_count, far_count, baseline_foliage, optimized_foliage, reduction * 100.0, full_gt3 * 100.0, full_gt8 * 100.0, int(full_metrics["bbox_width"]), int(full_metrics["bbox_height"]), signal_gt3 * 100.0, int(signal_metrics["bbox_width"]), int(signal_metrics["bbox_height"])])
    print("BRUSSELS_TREE_DISTANCE_LOD_VISUAL_OK: camera_eye=1.65m fov=70 source_positions_unchanged=true batches=3 diagnostic_camera_unchanged=true")
    quit(0)
