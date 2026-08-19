extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const BEFORE_PATH := "res://artifacts/visual/brussels_tree_ground_contact_before.png"
const AFTER_PATH := "res://artifacts/visual/brussels_tree_ground_contact_after.png"
const MIN_CHANGED_3 := 0.0025
const MIN_CHANGED_8 := 0.0008
const MIN_BBOX_WIDTH := 420
const MIN_BBOX_HEIGHT := 90

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_TREE_GROUND_CONTACT_VISUAL_FAIL: %s" % message)
    quit(1)

func _hide_canvas(node: Node) -> void:
    if node is CanvasItem:
        (node as CanvasItem).visible = false
    for child: Node in node.get_children():
        _hide_canvas(child)

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
            var d := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
            if d > limit:
                changed += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
    var bbox := Rect2i()
    if changed > 0:
        bbox = Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
    return {"fraction": float(changed) / float(WIDTH * HEIGHT), "bbox": bbox}

func _best_target(positions: Array[Vector3]) -> Vector3:
    var best := positions[0]
    var best_count := -1
    for candidate: Vector3 in positions:
        var count := 0
        for other: Vector3 in positions:
            if candidate.distance_to(other) <= 32.0:
                count += 1
        if count > best_count:
            best = candidate
            best_count = count
    print("BRUSSELS_TREE_GROUND_CONTACT_CLUSTER: neighbours32m=%d target=%s" % [best_count, str(best)])
    return best

func _run() -> void:
    root.size = Vector2i(WIDTH, HEIGHT)
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("production main missing")
        return
    var scene := packed.instantiate() as Node3D
    root.add_child(scene)

    var tree_runtime := root.get_node_or_null("BrusselsCorridorTreeRuntime")
    var ground_runtime := root.get_node_or_null("BrusselsTreeGroundContactRuntime")
    if tree_runtime == null or ground_runtime == null:
        _fail("shared tree runtimes missing")
        return
    tree_runtime.call("bind_scene", scene)
    for _i: int in range(30):
        if bool(tree_runtime.call("ready_complete")) and bool(ground_runtime.call("ready_complete")):
            break
        await process_frame
    if not bool(tree_runtime.call("ready_complete")) or bool(tree_runtime.call("failed")):
        _fail("corridor tree runtime unhealthy")
        return
    if not bool(ground_runtime.call("ready_complete")) or bool(ground_runtime.call("failed")):
        _fail("ground-contact runtime unhealthy")
        return
    if int(ground_runtime.call("instance_count")) != 266 or int(ground_runtime.call("batch_count")) != 1:
        _fail("ground-contact reuse count/batch changed")
        return
    if not bool(tree_runtime.call("source_positions_unchanged")) or int(tree_runtime.call("collision_count")) != 266:
        _fail("tree geometry/collision invariant failed before A/B")
        return

    var positions: Array[Vector3] = tree_runtime.call("source_positions")
    if positions.is_empty():
        _fail("tree positions missing")
        return

    var player := scene.get_node_or_null("Player") as Node3D
    if player != null:
        player.visible = false
    for dynamic_path: String in ["PrototypeCar", "PhysicalCarB", "MidiUrbanLife", "TrafficManager"]:
        var dynamic := scene.get_node_or_null(dynamic_path) as Node3D
        if dynamic != null:
            dynamic.visible = false
    _hide_canvas(root)

    var target := _best_target(positions)
    var camera := Camera3D.new()
    camera.fov = 67.0
    scene.add_child(camera)
    camera.look_at_from_position(target + Vector3(13.0, 1.65, 11.0), target + Vector3(0.0, 1.35, 0.0), Vector3.UP)
    camera.current = true

    ground_runtime.call("set_ground_contact_enabled", false)
    await process_frame
    if bool(ground_runtime.call("ground_contact_enabled")):
        _fail("BEFORE toggle failed")
        return
    var before := await _capture(BEFORE_PATH)
    if before == null:
        _fail("BEFORE capture missing")
        return

    ground_runtime.call("set_ground_contact_enabled", true)
    await process_frame
    if not bool(ground_runtime.call("ground_contact_enabled")):
        _fail("AFTER toggle failed")
        return
    if not bool(tree_runtime.call("source_positions_unchanged")) or int(tree_runtime.call("collision_count")) != 266:
        _fail("tree geometry/collision changed during A/B")
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
    print("BRUSSELS_TREE_GROUND_CONTACT_METRICS: gt3=%.4f%% gt8=%.4f%% bbox=%dx%d trees=266 batches=1 collisions_added=0 source_geometry_changed=false" % [f3 * 100.0, f8 * 100.0, bbox.size.x, bbox.size.y])
    if f3 < MIN_CHANGED_3 or f8 < MIN_CHANGED_8:
        _fail("ground-contact change below predeclared full-frame impact gate")
        return
    if bbox.size.x < MIN_BBOX_WIDTH or bbox.size.y < MIN_BBOX_HEIGHT:
        _fail("ground-contact change too spatially small")
        return

    print("BRUSSELS_TREE_GROUND_CONTACT_VISUAL_OK")
    quit(0)
