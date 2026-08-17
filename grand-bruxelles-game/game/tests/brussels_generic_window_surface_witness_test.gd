extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const BEFORE_PATH := "res://artifacts/visual/generic_window_surface_before.png"
const AFTER_PATH := "res://artifacts/visual/generic_window_surface_after.png"
const BOURSE := Vector2(81.54, -664.58)
const MIN_DISTANCE_M := 45.0
const MAX_DISTANCE_M := 135.0
const MIN_CHANGED_3 := 0.008
const MIN_CHANGED_8 := 0.003
const MIN_BBOX := Vector2i(260, 120)

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_GENERIC_WINDOW_SURFACE_VISUAL_FAIL: %s" % message)
    quit(1)

func _capture(viewport: SubViewport, path: String) -> Image:
    RenderingServer.force_draw()
    await process_frame
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty():
        return null
    var absolute := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    if image.save_png(absolute) != OK:
        return null
    return image

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

func _changed_metrics(before: Image, after: Image, threshold: int) -> Dictionary:
    var result := {"fraction": -1.0, "bbox": Rect2i()}
    if before == null or after == null or before.get_size() != after.get_size():
        return result
    var changed := 0
    var total := before.get_width() * before.get_height()
    var limit := float(threshold) / 255.0
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
    result.fraction = float(changed) / float(total)
    if max_x >= min_x and max_y >= min_y:
        result.bbox = Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
    return result

func _select_window(instance: MultiMeshInstance3D) -> Transform3D:
    var best := Transform3D.IDENTITY
    var best_score := -INF
    var multimesh := instance.multimesh
    for index: int in range(multimesh.instance_count):
        var local := multimesh.get_instance_transform(index)
        var world := instance.global_transform * local
        var point := Vector2(world.origin.x, world.origin.z)
        var distance := point.distance_to(BOURSE)
        if distance < MIN_DISTANCE_M or distance > MAX_DISTANCE_M:
            continue
        if world.origin.y < 4.0 or world.origin.y > 10.8:
            continue
        var width := world.basis.x.length()
        var score := width * 3.0 - absf(distance - 82.0) * 0.02 - absf(world.origin.y - 6.0) * 0.06
        if score > best_score:
            best = world
            best_score = score
    return best

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("production main scene missing")
        return

    var scene := packed.instantiate() as Node3D
    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    viewport.add_child(scene)
    _hide_dynamic(scene)

    var runtime := root.get_node_or_null("BrusselsGenericWindowSurfaceRuntime")
    if runtime == null:
        _fail("production generic-window autoload missing")
        return
    for _frame: int in range(240):
        if bool(runtime.call("ready_complete")):
            break
        await process_frame
    if not bool(runtime.call("ready_complete")) or bool(runtime.call("failed")):
        _fail("generic-window runtime did not bind cleanly")
        return

    var window_instance := scene.get_node_or_null("BrusselsOSM/GeneratedFacadeDetails/CorridorFacadeWindows") as MultiMeshInstance3D
    if window_instance == null or window_instance.multimesh == null:
        _fail("production generic window batch missing")
        return

    var original_count := window_instance.multimesh.instance_count
    var original_transforms: Array[Transform3D] = []
    for index: int in range(original_count):
        original_transforms.append(window_instance.multimesh.get_instance_transform(index))

    var target := _select_window(window_instance)
    if target == Transform3D.IDENTITY:
        _fail("no legitimate generic window witness found outside Bourse hero core")
        return

    var target_xz := Vector2(target.origin.x, target.origin.z)
    var normal3 := target.basis.z.normalized()
    var normal := Vector2(normal3.x, normal3.z)
    if normal.length() < 0.5:
        _fail("invalid generic window facade normal")
        return
    normal = normal.normalized()
    var plus := target_xz + normal * 18.0
    var minus := target_xz - normal * 18.0
    var camera_xz := plus if plus.distance_to(BOURSE) < minus.distance_to(BOURSE) else minus

    var camera := Camera3D.new()
    camera.position = Vector3(camera_xz.x, 1.65, camera_xz.y)
    camera.look_at_from_position(camera.position, Vector3(target.origin.x, clampf(target.origin.y, 5.0, 7.2), target.origin.z), Vector3.UP)
    camera.fov = 67.0
    camera.current = true
    scene.add_child(camera)

    runtime.call("set_enhanced_enabled", false)
    for _frame: int in range(6):
        await process_frame
    var before := await _capture(viewport, BEFORE_PATH)

    runtime.call("set_enhanced_enabled", true)
    for _frame: int in range(6):
        await process_frame
    var after := await _capture(viewport, AFTER_PATH)
    if before == null or after == null:
        _fail("1280x720 generic window A/B capture failed")
        return

    if window_instance.multimesh.instance_count != original_count:
        _fail("window instance count changed during material-only A/B")
        return
    for index: int in range(original_count):
        if not window_instance.multimesh.get_instance_transform(index).is_equal_approx(original_transforms[index]):
            _fail("window transform changed during material-only A/B")
            return

    var gt3 := _changed_metrics(before, after, 3)
    var gt8 := _changed_metrics(before, after, 8)
    var bbox: Rect2i = gt3.bbox
    print("BRUSSELS_GENERIC_WINDOW_SURFACE_VISUAL_METRICS: target_distance_to_bourse=%.2f changed_gt3=%.6f changed_gt8=%.6f bbox=%dx%d" % [target_xz.distance_to(BOURSE), float(gt3.fraction), float(gt8.fraction), bbox.size.x, bbox.size.y])
    if float(gt3.fraction) < MIN_CHANGED_3 or float(gt8.fraction) < MIN_CHANGED_8:
        _fail("full-frame generic window change too weak: gt3=%.4f%% gt8=%.4f%%" % [float(gt3.fraction) * 100.0, float(gt8.fraction) * 100.0])
        return
    if bbox.size.x < MIN_BBOX.x or bbox.size.y < MIN_BBOX.y:
        _fail("generic window change is too spatially narrow: bbox=%dx%d" % [bbox.size.x, bbox.size.y])
        return

    print("BRUSSELS_GENERIC_WINDOW_SURFACE_VISUAL_OK: player_eye_height=1.65m fov=67 instance_count=%d transforms_unchanged=true opening_geometry_claimed=false changed_gt3=%.4f%% changed_gt8=%.4f%% bbox=%dx%d" % [original_count, float(gt3.fraction) * 100.0, float(gt8.fraction) * 100.0, bbox.size.x, bbox.size.y])
    quit(0)
