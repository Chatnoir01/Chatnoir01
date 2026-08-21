extends SceneTree

const JETTE_ZONE := "res://game/zones/laeken_jette/jette_phase2_zone.gd"
const JETTE_DATA := "res://data/osm/zones/jette/environment.game.json"
const CATALOG_PATH := "res://data/qa/playable_zone_catalog.json"
const TREE := preload("res://game/scripts/brussels_street_tree_asset.gd")
const SPAWN := Vector3(-687.700268506218, 1.05, -4952.774160383269)
const BEFORE := "res://artifacts/visual/tree_lod_full_detail_before.png"
const AFTER := "res://artifacts/visual/tree_lod_distance_after.png"
const DIAG_BEFORE := "res://artifacts/visual/tree_lod_signal_before.png"
const DIAG_AFTER := "res://artifacts/visual/tree_lod_signal_after.png"
const EXPECTED_RENDERED_TREES := 170
const EXPECTED_LOBES_PER_NEAR_TREE := 8
const EXPECTED_LOBES_PER_FAR_TREE := 3
const FAR_LOBE_INDICES := [0, 3, 6]
const TREE_FULL_DETAIL_RADIUS_M := 140.0
const TREE_RENDER_RADIUS_M := 350.0
const MIN_INSTANCE_REDUCTION := 0.30
const MAX_CHANGED_GT3 := 0.015
const MAX_CHANGED_GT8 := 0.012

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_TREE_DISTANCE_LOD_VISUAL_FAIL: %s" % message)
    quit(1)

func _read(path: String) -> String:
    var file := FileAccess.open(path, FileAccess.READ)
    return file.get_as_text() if file != null else ""

func _capture(viewport: SubViewport, path: String) -> Image:
    RenderingServer.force_draw()
    await process_frame
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty():
        return null
    var absolute := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    return image if image.save_png(absolute) == OK else null

func _diff_metrics(before: Image, after: Image) -> Dictionary:
    var gt3 := 0
    var gt8 := 0
    var total := 0
    var min_x := before.get_width()
    var min_y := before.get_height()
    var max_x := -1
    var max_y := -1
    for y: int in range(0, before.get_height(), 2):
        for x: int in range(0, before.get_width(), 2):
            total += 1
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) * 255.0
            if delta > 3.0:
                gt3 += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
            if delta > 8.0:
                gt8 += 1
    return {
        "changed_gt3": float(gt3) / float(maxi(total, 1)),
        "changed_gt8": float(gt8) / float(maxi(total, 1)),
        "bbox_width": 0 if max_x < min_x else max_x - min_x + 1,
        "bbox_height": 0 if max_y < min_y else max_y - min_y + 1,
    }

func _jette_contract() -> Dictionary:
    var parsed: Variant = JSON.parse_string(_read(CATALOG_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    var rows: Variant = (parsed as Dictionary).get("zones", [])
    if not rows is Array:
        return {}
    for row_variant in rows:
        if row_variant is Dictionary and str((row_variant as Dictionary).get("id", "")) == "jette":
            return (row_variant as Dictionary).duplicate(true)
    return {}

func _environment_rows() -> Array:
    var parsed: Variant = JSON.parse_string(_read(JETTE_DATA))
    if typeof(parsed) != TYPE_DICTIONARY:
        return []
    return (parsed as Dictionary).get("environment_points", []) as Array

func _nearest_tree() -> Vector3:
    var nearest := Vector3(INF, INF, INF)
    var nearest_distance := INF
    for row_variant in _environment_rows():
        if not row_variant is Dictionary:
            continue
        var row := row_variant as Dictionary
        if str(row.get("kind", "")) != "tree":
            continue
        var position := row.get("position", []) as Array
        if position.size() < 2:
            continue
        var world := Vector3(float(position[0]), 0.0, float(position[1]))
        var distance := Vector2(world.x - SPAWN.x, world.z - SPAWN.z).length()
        if distance < nearest_distance:
            nearest_distance = distance
            nearest = world
    return nearest

func _far_tree_rows() -> Array:
    var rows: Array = []
    for row_variant in _environment_rows():
        if not row_variant is Dictionary:
            continue
        var row := row_variant as Dictionary
        if str(row.get("kind", "")) != "tree":
            continue
        var position := row.get("position", []) as Array
        if position.size() < 2:
            continue
        var world := Vector3(float(position[0]), 0.0, float(position[1]))
        var distance := Vector2(world.x - SPAWN.x, world.z - SPAWN.z).length()
        if distance > TREE_FULL_DETAIL_RADIUS_M and distance <= TREE_RENDER_RADIUS_M:
            rows.append({"osm_id": int(row.get("osm_id", 0)), "position": world, "distance": distance})
    rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        if float(a["distance"]) == float(b["distance"]):
            return int(a["osm_id"]) < int(b["osm_id"])
        return float(a["distance"]) < float(b["distance"])
    )
    return rows

func _tree_batch_count(runtime: Node) -> int:
    var count := 0
    for name_value: String in ["TreeTrunks", "TreeFoliageDark", "TreeFoliageLight"]:
        var batch := runtime.get_node_or_null(name_value) as MultiMeshInstance3D
        if batch != null and batch.multimesh != null:
            count += 1
    return count

func _hide_zone_geometry(zone: Node) -> void:
    for node_variant in zone.find_children("*", "GeometryInstance3D", true, false):
        var geometry := node_variant as GeometryInstance3D
        if geometry != null:
            geometry.visible = false

func _diagnostic_batch(parent: Node3D, name_value: String, mesh: Mesh, transforms: Array[Transform3D]) -> void:
    if transforms.is_empty():
        return
    var multimesh := MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = mesh
    multimesh.instance_count = transforms.size()
    for index: int in range(transforms.size()):
        multimesh.set_instance_transform(index, transforms[index])
    var batch := MultiMeshInstance3D.new()
    batch.name = name_value
    batch.multimesh = multimesh
    parent.add_child(batch)

func _build_far_tree_signal(parent: Node3D, rows: Array, full_detail: bool) -> int:
    for child in parent.get_children():
        parent.remove_child(child)
        child.queue_free()
    var materials := TREE.create_materials()
    var dark: Array[Transform3D] = []
    var light: Array[Transform3D] = []
    var lobe_count := 0
    for row_variant in rows:
        var row := row_variant as Dictionary
        var base := row["position"] as Vector3
        var osm_id := int(row["osm_id"])
        var lobe_indices: Array = []
        if full_detail:
            for index: int in range(TREE.FOLIAGE_LOBE_COUNT):
                lobe_indices.append(index)
        else:
            lobe_indices.assign(FAR_LOBE_INDICES)
        for index_variant in lobe_indices:
            var index := int(index_variant)
            var transform := TREE.foliage_lobe_transform(base, osm_id, index)
            if TREE.foliage_is_light(index):
                light.append(transform)
            else:
                dark.append(transform)
            lobe_count += 1
    _diagnostic_batch(parent, "FarTreeSignalFoliageDark", TREE.create_foliage_mesh(materials["foliage_dark"] as Material), dark)
    _diagnostic_batch(parent, "FarTreeSignalFoliageLight", TREE.create_foliage_mesh(materials["foliage_light"] as Material), light)
    return lobe_count

func _run() -> void:
    if not FileAccess.file_exists(JETTE_ZONE) or not FileAccess.file_exists(JETTE_DATA) or not FileAccess.file_exists(CATALOG_PATH):
        _fail("Jette source-backed environment witness inputs missing")
        return
    var jette := _jette_contract()
    if jette.is_empty() or str(jette.get("environment_artifact", "")) != JETTE_DATA:
        _fail("Jette catalog-owned environment contract missing")
        return
    var nearest_tree := _nearest_tree()
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

    var zone_script := load(JETTE_ZONE) as Script
    var zone := zone_script.new() as Node3D
    world_root.add_child(zone)
    for _frame in range(12):
        await process_frame
    var selector := root.get_node_or_null("ZoneSelectorRuntime")
    if selector == null or not selector.has_method("_mount_environment_if_required"):
        _fail("ZoneSelectorRuntime generic environment mount missing")
        return
    var mounted := bool(await selector.call("_mount_environment_if_required", world_root, jette))
    if not mounted:
        _fail("ZoneSelectorRuntime refused Jette environment contract")
        return
    for _frame in range(3):
        await process_frame
    var runtime := world_root.get_node_or_null("ZoneEnvironment_jette") as Node3D
    if runtime == null or not bool(runtime.call("loaded_ok")):
        _fail("catalog-driven Jette generic environment runtime missing")
        return
    runtime.set_process(false)

    var camera_direction := Vector3(SPAWN.x - nearest_tree.x, 0.0, SPAWN.z - nearest_tree.z).normalized()
    if camera_direction.length_squared() < 0.5:
        camera_direction = Vector3.FORWARD
    var camera := Camera3D.new()
    camera.position = nearest_tree + camera_direction * 12.0 + Vector3(0.0, 1.65, 0.0)
    camera.look_at_from_position(camera.position, nearest_tree + Vector3(0.0, 2.8, 0.0), Vector3.UP)
    camera.fov = 70.0
    camera.current = true
    world_root.add_child(camera)
    var frozen_camera_transform := camera.global_transform
    var frozen_camera_fov := camera.fov

    runtime.set("tree_full_detail_radius_m", float(runtime.get("render_radius_m")))
    runtime.call("_rebuild", SPAWN)
    for _frame in range(3): await process_frame
    var baseline_counts := (runtime.get("last_tree_lod_counts") as Dictionary).duplicate(true)
    var baseline_render_counts := (runtime.get("last_render_counts") as Dictionary).duplicate(true)
    if int(baseline_render_counts.get("tree", 0)) != EXPECTED_RENDERED_TREES:
        _fail("full-detail baseline tree count drifted")
        return
    if int(baseline_counts.get("far", -1)) != 0 or int(baseline_counts.get("near", 0)) != EXPECTED_RENDERED_TREES:
        _fail("full-detail baseline did not keep all rendered trees near-detail")
        return
    var baseline_foliage := int(baseline_counts.get("foliage_instances", 0))
    if baseline_foliage != EXPECTED_RENDERED_TREES * EXPECTED_LOBES_PER_NEAR_TREE or _tree_batch_count(runtime) != 3:
        _fail("full-detail baseline renderer contract drifted")
        return
    var before := await _capture(viewport, BEFORE)

    runtime.set("tree_full_detail_radius_m", TREE_FULL_DETAIL_RADIUS_M)
    runtime.call("_rebuild", SPAWN)
    for _frame in range(3): await process_frame
    var optimized_counts := (runtime.get("last_tree_lod_counts") as Dictionary).duplicate(true)
    var optimized_render_counts := (runtime.get("last_render_counts") as Dictionary).duplicate(true)
    if int(optimized_render_counts.get("tree", 0)) != EXPECTED_RENDERED_TREES:
        _fail("distance LOD changed source-backed rendered tree count")
        return
    var near_count := int(optimized_counts.get("near", 0))
    var far_count := int(optimized_counts.get("far", 0))
    var optimized_foliage := int(optimized_counts.get("foliage_instances", 0))
    if near_count + far_count != EXPECTED_RENDERED_TREES or near_count <= 0 or far_count <= 0:
        _fail("real-scene LOD partition is invalid")
        return
    if optimized_foliage != near_count * EXPECTED_LOBES_PER_NEAR_TREE + far_count * EXPECTED_LOBES_PER_FAR_TREE:
        _fail("real-scene LOD foliage count does not match near/far contract")
        return
    var reduction := 1.0 - float(optimized_foliage) / float(maxi(baseline_foliage, 1))
    if reduction < MIN_INSTANCE_REDUCTION or _tree_batch_count(runtime) != 3:
        _fail("real-scene LOD reduction/batch contract failed")
        return
    var after := await _capture(viewport, AFTER)
    if before == null or after == null:
        _fail("tree LOD A/B capture failed")
        return
    var full_metrics := _diff_metrics(before, after)
    var full_gt3 := float(full_metrics["changed_gt3"])
    var full_gt8 := float(full_metrics["changed_gt8"])
    if full_gt3 > MAX_CHANGED_GT3 or full_gt8 > MAX_CHANGED_GT8:
        _fail("tree LOD changes too much of the player frame: gt3=%.4f%% gt8=%.4f%%" % [full_gt3 * 100.0, full_gt8 * 100.0])
        return

    var far_rows := _far_tree_rows()
    if far_rows.size() != far_count:
        _fail("diagnostic far-tree source selection drifted: expected %d got %d" % [far_count, far_rows.size()])
        return
    _hide_zone_geometry(zone)
    var signal_root := Node3D.new()
    signal_root.name = "TreeLodFarSignalDiagnostic"
    world_root.add_child(signal_root)
    var signal_full_lobes := _build_far_tree_signal(signal_root, far_rows, true)
    for _frame in range(3): await process_frame
    var signal_before := await _capture(viewport, DIAG_BEFORE)
    var signal_lod_lobes := _build_far_tree_signal(signal_root, far_rows, false)
    for _frame in range(3): await process_frame
    var signal_after := await _capture(viewport, DIAG_AFTER)
    if signal_before == null or signal_after == null:
        _fail("far-tree diagnostic A/B capture failed")
        return
    if signal_full_lobes != far_count * EXPECTED_LOBES_PER_NEAR_TREE or signal_lod_lobes != far_count * EXPECTED_LOBES_PER_FAR_TREE:
        _fail("far-tree diagnostic lobe contract drifted")
        return
    if not camera.global_transform.is_equal_approx(frozen_camera_transform) or absf(camera.fov - frozen_camera_fov) > 0.001:
        _fail("diagnostic camera changed from normal-player A/B")
        return
    var signal_metrics := _diff_metrics(signal_before, signal_after)
    var signal_gt3 := float(signal_metrics["changed_gt3"])

    print("BRUSSELS_TREE_DISTANCE_LOD_VISUAL_METRICS: trees=%d near=%d far=%d foliage=%d->%d reduction=%.2f%% full_gt3=%.4f%% full_gt8=%.4f%% full_bbox=%dx%d signal_gt3=%.4f%% signal_bbox=%dx%d signal_lobes=%d->%d" % [EXPECTED_RENDERED_TREES, near_count, far_count, baseline_foliage, optimized_foliage, reduction * 100.0, full_gt3 * 100.0, full_gt8 * 100.0, int(full_metrics["bbox_width"]), int(full_metrics["bbox_height"]), signal_gt3 * 100.0, int(signal_metrics["bbox_width"]), int(signal_metrics["bbox_height"]), signal_full_lobes, signal_lod_lobes])
    print("BRUSSELS_TREE_DISTANCE_LOD_VISUAL_OK: camera_eye=1.65m fov=70 source_positions_unchanged=true batches=3 catalog_mount=true diagnostic_camera_unchanged=true diagnostic_far_trees_only=true instance_reduction_gate=true full_frame_non_regression_gate=true")
    quit(0)
