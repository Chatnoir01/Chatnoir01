extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const BEFORE_PATH := "res://artifacts/visual/bollards_before.png"
const AFTER_PATH := "res://artifacts/visual/bollards_after.png"
const MIN_CHANGED_3 := 0.008
const MIN_CHANGED_8 := 0.004
const MIN_BBOX_WIDTH := 220
const MIN_BBOX_HEIGHT := 100

const CAMERA_CANDIDATES := [
    [Vector3(-127.0, 1.65, -391.5), Vector3(-132.0, 0.50, -406.0)],
    [Vector3(-124.0, 1.65, -394.0), Vector3(-133.0, 0.48, -408.0)],
    [Vector3(-130.5, 1.65, -391.0), Vector3(-134.0, 0.50, -407.5)],
    [Vector3(-123.0, 1.65, -405.0), Vector3(-133.0, 0.48, -407.0)]
]

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_BOLLARD_VISUAL_FAIL: %s" % message)
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

func _diff_stats(before: Image, after: Image, threshold: int) -> Dictionary:
    if before == null or after == null or before.get_size() != after.get_size():
        return {"fraction": -1.0, "bbox": Rect2i()}
    var limit := float(threshold) / 255.0
    var changed := 0
    var min_x := before.get_width()
    var min_y := before.get_height()
    var max_x := -1
    var max_y := -1
    for y: int in range(before.get_height()):
        for x: int in range(before.get_width()):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            if max(abs(a.r - b.r), max(abs(a.g - b.g), abs(a.b - b.b))) > limit:
                changed += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
    var bbox := Rect2i()
    if changed > 0:
        bbox = Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
    return {"fraction": float(changed) / float(before.get_width() * before.get_height()), "bbox": bbox}

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

    var runtime := root.get_node_or_null("BrusselsBollardRuntime")
    if runtime == null:
        _fail("production bollard autoload missing")
        return
    runtime.call("bind_scene", scene)
    for _frame: int in range(12):
        await process_frame
    if not bool(runtime.call("ready_complete")) or bool(runtime.call("failed")):
        _fail("production bollard runtime did not bind cleanly")
        return
    if not bool(runtime.call("source_positions_unchanged")):
        _fail("source positions changed before visual witness")
        return

    var camera := Camera3D.new()
    camera.current = true
    scene.add_child(camera)

    var best_before: Image = null
    var best_after: Image = null
    var best_changed := -1.0
    var best_index := -1

    for index: int in range(CAMERA_CANDIDATES.size()):
        _set_camera(camera, CAMERA_CANDIDATES[index] as Array)
        runtime.call("set_visual_enabled", false)
        for _frame: int in range(4):
            await process_frame
        var before := await _grab(viewport)
        runtime.call("set_visual_enabled", true)
        for _frame: int in range(4):
            await process_frame
        var after := await _grab(viewport)
        var stats := _diff_stats(before, after, 3)
        var fraction := float(stats.get("fraction", -1.0))
        if fraction > best_changed:
            best_changed = fraction
            best_before = before
            best_after = after
            best_index = index

    if best_before == null or best_after == null or best_index < 0:
        _fail("failed to obtain deterministic player-eye A/B")
        return
    if not _save(best_before, BEFORE_PATH) or not _save(best_after, AFTER_PATH):
        _fail("failed to save A/B evidence")
        return

    var stats3 := _diff_stats(best_before, best_after, 3)
    var stats8 := _diff_stats(best_before, best_after, 8)
    var changed3 := float(stats3.get("fraction", -1.0))
    var changed8 := float(stats8.get("fraction", -1.0))
    var bbox := stats3.get("bbox", Rect2i()) as Rect2i
    print("BRUSSELS_BOLLARD_VISUAL_METRICS: camera=%d changed_gt3=%.6f changed_gt8=%.6f bbox=%dx%d points=%d batches=%d" % [best_index, changed3, changed8, bbox.size.x, bbox.size.y, int(runtime.call("point_count")), int(runtime.call("visual_batch_count"))])

    if changed3 < MIN_CHANGED_3 or changed8 < MIN_CHANGED_8:
        _fail("full-frame bollard impact too weak: gt3=%.4f%% gt8=%.4f%%" % [changed3 * 100.0, changed8 * 100.0])
        return
    if bbox.size.x < MIN_BBOX_WIDTH or bbox.size.y < MIN_BBOX_HEIGHT:
        _fail("bollard change bbox too small: %dx%d" % [bbox.size.x, bbox.size.y])
        return
    if not bool(runtime.call("source_positions_unchanged")):
        _fail("source positions changed during A/B")
        return

    print("BRUSSELS_BOLLARD_VISUAL_OK: player_eye_height=1.65m fov=67 camera=%d source_positions_unchanged=true changed_gt3=%.4f%% changed_gt8=%.4f%% bbox=%dx%d" % [best_index, changed3 * 100.0, changed8 * 100.0, bbox.size.x, bbox.size.y])
    quit(0)
