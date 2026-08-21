extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const BEFORE_PATH := "res://artifacts/visual/corridor_tree_lod_full_detail_before.png"
const AFTER_PATH := "res://artifacts/visual/corridor_tree_lod_distance_after.png"
const FULL_DETAIL_RADIUS_M := 100000.0
const PRODUCTION_RADIUS_M := 140.0
const MIN_INSTANCE_REDUCTION := 0.30
const MAX_CHANGED_GT3 := 0.015
const MAX_CHANGED_GT8 := 0.012

# Existing legitimate corridor player-eye cameras from the shipped shared street-lamp witness.
const CAMERA_CANDIDATES := [
    [Vector3(-132.0, 1.65, -416.0), Vector3(-151.0, 2.60, -433.0)],
    [Vector3(-136.0, 1.65, -420.0), Vector3(-157.0, 2.70, -435.0)],
    [Vector3(-141.0, 1.65, -413.0), Vector3(-155.0, 2.55, -432.0)],
    [Vector3(-129.0, 1.65, -428.0), Vector3(-154.0, 2.70, -434.0)]
]

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_CORRIDOR_TREE_LOD_VISUAL_FAIL: %s" % message)
    quit(1)

func _hide_dynamic(scene: Node) -> void:
    for path: String in ["LocationLabel", "MissionLabel", "PrototypeLabel", "MiniMap", "MobileControls", "WalletHUD"]:
        var item := scene.get_node_or_null(path) as CanvasItem
        if item != null:
            item.visible = false
    for path: String in ["PrototypeCar", "PhysicalCarB", "MidiUrbanLife"]:
        var spatial := scene.get_node_or_null(path) as Node3D
        if spatial != null:
            spatial.visible = false
    var player := scene.get_node_or_null("Player") as Node3D
    if player != null:
        player.visible = false
    var traffic := scene.get_node_or_null("TrafficManager")
    if traffic != null:
        traffic.set("auto_spawn_runtime", false)
        if traffic is Node3D:
            (traffic as Node3D).visible = false

func _grab(viewport: SubViewport) -> Image:
    RenderingServer.force_draw()
    await process_frame
    var image := viewport.get_texture().get_image()
    return image if image != null and not image.is_empty() else null

func _save(image: Image, path: String) -> bool:
    if image == null or image.is_empty():
        return false
    var absolute := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    return image.save_png(absolute) == OK

func _diff_metrics(before: Image, after: Image) -> Dictionary:
    if before == null or after == null or before.get_size() != after.get_size():
        return {"changed_gt3": -1.0, "changed_gt8": -1.0, "bbox_width": 0, "bbox_height": 0}
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

func _set_camera(camera: Camera3D, candidate: Array) -> void:
    camera.fov = 67.0
    camera.look_at_from_position(candidate[0] as Vector3, candidate[1] as Vector3, Vector3.UP)

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("production main scene missing")
        return
    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    var scene := packed.instantiate() as Node3D
    viewport.add_child(scene)
    _hide_dynamic(scene)

    var runtime := root.get_node_or_null("BrusselsCorridorTreeRuntime")
    if runtime == null:
        _fail("production corridor tree autoload missing")
        return
    runtime.call("bind_scene", scene)
    for _frame: int in range(12):
        await process_frame
    runtime.set_process(false)
    if not bool(runtime.call("ready_complete")) or bool(runtime.call("failed")):
        _fail("production corridor tree runtime did not bind cleanly")
        return
    if int(runtime.call("tree_count")) != 266 or int(runtime.call("collision_count")) != 266 or int(runtime.call("batch_count")) != 3:
        _fail("corridor tree source/collision/batch contract drifted")
        return
    if not bool(runtime.call("source_positions_unchanged")):
        _fail("source positions changed before visual witness")
        return

    var best_index := -1
    var best_reduction := -1.0
    var best_near := 0
    var best_far := 0
    var best_foliage := 0
    var baseline_foliage := 266 * 8
    for index: int in range(CAMERA_CANDIDATES.size()):
        var anchor := (CAMERA_CANDIDATES[index] as Array)[0] as Vector3
        runtime.set("tree_full_detail_radius_m", PRODUCTION_RADIUS_M)
        runtime.call("rebuild_visual_batches_for_anchor", anchor)
        var near_count := int(runtime.call("near_tree_count"))
        var far_count := int(runtime.call("far_tree_count"))
        var foliage := int(runtime.call("foliage_instance_count"))
        if not bool(runtime.call("lod_active")) or near_count <= 0 or far_count <= 0:
            continue
        var reduction := 1.0 - float(foliage) / float(baseline_foliage)
        if reduction > best_reduction:
            best_reduction = reduction
            best_index = index
            best_near = near_count
            best_far = far_count
            best_foliage = foliage

    if best_index < 0 or best_reduction < MIN_INSTANCE_REDUCTION:
        _fail("no legitimate corridor camera produced a valid >=30% LOD partition")
        return

    var camera := Camera3D.new()
    camera.current = true
    scene.add_child(camera)
    _set_camera(camera, CAMERA_CANDIDATES[best_index] as Array)
    var frozen_transform := camera.global_transform
    var frozen_fov := camera.fov
    var anchor := (CAMERA_CANDIDATES[best_index] as Array)[0] as Vector3

    runtime.set("tree_full_detail_radius_m", FULL_DETAIL_RADIUS_M)
    runtime.call("rebuild_visual_batches_for_anchor", anchor)
    for _frame: int in range(4): await process_frame
    var before := await _grab(viewport)
    var full_near := int(runtime.call("near_tree_count"))
    var full_far := int(runtime.call("far_tree_count"))
    var full_foliage := int(runtime.call("foliage_instance_count"))
    if full_near != 266 or full_far != 0 or full_foliage != baseline_foliage:
        _fail("full-detail baseline contract drifted")
        return

    runtime.set("tree_full_detail_radius_m", PRODUCTION_RADIUS_M)
    runtime.call("rebuild_visual_batches_for_anchor", anchor)
    for _frame: int in range(4): await process_frame
    var after := await _grab(viewport)
    if before == null or after == null:
        _fail("corridor tree LOD A/B capture failed")
        return
    if not camera.global_transform.is_equal_approx(frozen_transform) or absf(camera.fov - frozen_fov) > 0.001:
        _fail("camera changed during corridor tree LOD A/B")
        return
    if int(runtime.call("near_tree_count")) != best_near or int(runtime.call("far_tree_count")) != best_far or int(runtime.call("foliage_instance_count")) != best_foliage:
        _fail("production LOD partition changed between selection and capture")
        return
    if not bool(runtime.call("source_positions_unchanged")):
        _fail("source positions changed during LOD A/B")
        return

    var metrics := _diff_metrics(before, after)
    var changed3 := float(metrics["changed_gt3"])
    var changed8 := float(metrics["changed_gt8"])
    if changed3 > MAX_CHANGED_GT3 or changed8 > MAX_CHANGED_GT8:
        _fail("corridor tree LOD damages too much of player frame: gt3=%.4f%% gt8=%.4f%%" % [changed3 * 100.0, changed8 * 100.0])
        return
    if not _save(before, BEFORE_PATH) or not _save(after, AFTER_PATH):
        _fail("failed to save corridor tree LOD A/B")
        return

    print("BRUSSELS_CORRIDOR_TREE_LOD_VISUAL_METRICS: camera=%d trees=266 near=%d far=%d foliage=%d->%d reduction=%.2f%% changed_gt3=%.4f%% changed_gt8=%.4f%% bbox=%dx%d" % [best_index, best_near, best_far, baseline_foliage, best_foliage, best_reduction * 100.0, changed3 * 100.0, changed8 * 100.0, int(metrics["bbox_width"]), int(metrics["bbox_height"])])
    print("BRUSSELS_CORRIDOR_TREE_LOD_VISUAL_OK: player_eye_height=1.65m fov=67 source_positions_unchanged=true collisions=266 batches=3")
    quit(0)
