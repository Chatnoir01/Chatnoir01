extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const BEFORE_PATH := "res://artifacts/visual/shared_road_paint_before.png"
const AFTER_PATH := "res://artifacts/visual/shared_road_paint_after.png"
const MIN_MARKINGS := 12
const MIN_CHANGED_3 := 0.0008
const MIN_CHANGED_8 := 0.00035
const MIN_BBOX_WIDTH := 280
const MIN_BBOX_HEIGHT := 75

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("SHARED_BRUSSELS_ROAD_PAINT_VISUAL_FAIL: %s" % message)
    quit(1)

func _hide_canvas(node: Node) -> void:
    if node is CanvasItem:
        (node as CanvasItem).visible = false
    for child: Node in node.get_children():
        _hide_canvas(child)

func _freeze(scene: Node3D) -> void:
    var traffic := scene.get_node_or_null("TrafficManager")
    if traffic != null:
        traffic.set_process(false)
        traffic.set_physics_process(false)
        if traffic is Node3D:
            (traffic as Node3D).visible = false
    for path: String in ["PrototypeCar", "PhysicalCarB", "MidiUrbanLife"]:
        var node := scene.get_node_or_null(path)
        if node != null:
            node.set_process(false)
            node.set_physics_process(false)
            if node is Node3D:
                (node as Node3D).visible = false
    var player := scene.get_node_or_null("Player")
    if player != null:
        player.set_process(false)
        player.set_physics_process(false)
    _hide_canvas(scene)

func _capture(path: String) -> Image:
    RenderingServer.force_draw()
    await process_frame
    await RenderingServer.frame_post_draw
    var image := root.get_texture().get_image()
    if image == null or image.is_empty() or image.get_size() != Vector2i(WIDTH, HEIGHT):
        return null
    var absolute := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    if image.save_png(absolute) != OK:
        return null
    return image

func _geometry_snapshot(runtime: Node) -> Dictionary:
    var snapshot := {}
    var targets: Array = runtime.get("_targets")
    for target: Variant in targets:
        if not target is CSGBox3D:
            continue
        var dash := target as CSGBox3D
        snapshot[dash.get_instance_id()] = {
            "transform": dash.global_transform,
            "size": dash.size,
        }
    return snapshot

func _assert_geometry_unchanged(runtime: Node, before: Dictionary) -> bool:
    var targets: Array = runtime.get("_targets")
    if targets.size() != before.size():
        _fail("target count changed during A/B")
        return false
    for target: Variant in targets:
        if not target is CSGBox3D:
            _fail("non-CSG target entered road-paint set")
            return false
        var dash := target as CSGBox3D
        var id := dash.get_instance_id()
        if not before.has(id):
            _fail("road-paint target identity changed")
            return false
        var expected: Dictionary = before[id]
        if dash.global_transform != expected["transform"]:
            _fail("road-paint target transform changed")
            return false
        if dash.size != expected["size"]:
            _fail("road-paint target size changed")
            return false
        if bool(dash.get_meta("geometry_changed_by_road_paint_runtime", true)):
            _fail("target metadata reports geometry mutation")
            return false
    return true

func _stats(before: Image, after: Image, threshold: int) -> Dictionary:
    var changed := 0
    var min_x := WIDTH
    var min_y := HEIGHT
    var max_x := -1
    var max_y := -1
    var limit := float(threshold) / 255.0
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
            if delta > limit:
                changed += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
    var bbox := Rect2i()
    if changed > 0:
        bbox = Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
    return {"fraction": float(changed) / float(WIDTH * HEIGHT), "bbox": bbox}

func _run() -> void:
    root.size = Vector2i(WIDTH, HEIGHT)
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("production main missing")
        return
    var scene := packed.instantiate() as Node3D
    root.add_child(scene)

    var runtime := root.get_node_or_null("BrusselsSharedRoadPaintRuntime")
    if runtime == null:
        _fail("shared road-paint autoload missing")
        return
    for _i: int in range(240):
        await process_frame
        if bool(runtime.call("ready_complete")):
            break
    if not bool(runtime.call("ready_complete")):
        _fail("road-paint runtime did not settle")
        return
    if bool(runtime.call("failed")):
        _fail("road-paint runtime reported failure")
        return
    var count := int(runtime.call("applied_marking_count"))
    if count < MIN_MARKINGS:
        _fail("too few generic lane dashes for reusable visible lot: %d" % count)
        return

    _freeze(scene)
    var geometry := _geometry_snapshot(runtime)
    if geometry.size() != count:
        _fail("geometry snapshot does not cover all targets")
        return

    runtime.call("set_enhanced_enabled", false)
    for _i: int in range(4):
        await process_frame
    var before := await _capture(BEFORE_PATH)
    if before == null:
        _fail("BEFORE capture missing")
        return

    runtime.call("set_enhanced_enabled", true)
    for _i: int in range(4):
        await process_frame
    if not _assert_geometry_unchanged(runtime, geometry):
        return
    var after := await _capture(AFTER_PATH)
    if after == null:
        _fail("AFTER capture missing")
        return

    var s3 := _stats(before, after, 3)
    var s8 := _stats(before, after, 8)
    var f3 := float(s3["fraction"])
    var f8 := float(s8["fraction"])
    var bbox := s3["bbox"] as Rect2i
    print("SHARED_BRUSSELS_ROAD_PAINT_METRICS: markings=%d gt3=%.4f%% gt8=%.4f%% bbox=%dx%d" % [count, f3 * 100.0, f8 * 100.0, bbox.size.x, bbox.size.y])
    if f3 < MIN_CHANGED_3 or f8 < MIN_CHANGED_8:
        _fail("material change is below predeclared normal-player pixel-impact gate")
        return
    if bbox.size.x < MIN_BBOX_WIDTH or bbox.size.y < MIN_BBOX_HEIGHT:
        _fail("material change does not span enough of the normal-player frame")
        return

    print("SHARED_BRUSSELS_ROAD_PAINT_VISUAL_OK")
    quit(0)
