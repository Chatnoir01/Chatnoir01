extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const BEFORE_PATH := "res://artifacts/visual/brussels_tree_silhouette_before.png"
const AFTER_PATH := "res://artifacts/visual/brussels_tree_silhouette_after.png"
const MIN_CHANGED_3 := 0.0040
const MIN_CHANGED_8 := 0.0015
const MIN_BBOX_WIDTH := 180
const MIN_BBOX_HEIGHT := 170

const OLD_LIGHT := [0, 4]
const OLD_OFFSETS := [
    Vector3(0.0, 3.35, 0.0),
    Vector3(0.72, 3.18, 0.02),
    Vector3(-0.62, 3.20, 0.38),
    Vector3(0.05, 3.10, -0.72),
    Vector3(0.22, 3.82, 0.22),
    Vector3(-0.38, 3.62, -0.30),
]
const OLD_SCALES := [
    Vector3(1.02, 0.92, 1.08),
    Vector3(0.82, 0.78, 0.88),
    Vector3(0.88, 0.82, 0.78),
    Vector3(0.86, 0.74, 0.92),
    Vector3(0.72, 0.78, 0.70),
    Vector3(0.74, 0.70, 0.82),
]

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_TREE_SILHOUETTE_VISUAL_FAIL: %s" % message)
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

func _old_lobe_transform(base: Vector3, osm_id: int, index: int) -> Transform3D:
    var phase := deg_to_rad(float(abs(osm_id) % 360))
    var jitter := float((abs(osm_id) % 13) - 6) * 0.018
    var offset: Vector3 = OLD_OFFSETS[index]
    var rotated := Vector3(
        offset.x * cos(phase) - offset.z * sin(phase),
        offset.y + jitter,
        offset.x * sin(phase) + offset.z * cos(phase)
    )
    return Transform3D(Basis.IDENTITY.scaled(OLD_SCALES[index] as Vector3), base + rotated)

func _make_batch(name: String, mesh: Mesh, transforms: Array[Transform3D]) -> MultiMeshInstance3D:
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.mesh = mesh
    mm.instance_count = transforms.size()
    for i: int in range(transforms.size()):
        mm.set_instance_transform(i, transforms[i])
    var instance := MultiMeshInstance3D.new()
    instance.name = name
    instance.multimesh = mm
    return instance

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
    print("BRUSSELS_TREE_SILHOUETTE_CLUSTER: neighbours32m=%d target=%s" % [best_count, str(best)])
    return best

func _run() -> void:
    root.size = Vector2i(WIDTH, HEIGHT)
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("production main missing")
        return
    var scene := packed.instantiate() as Node3D
    root.add_child(scene)
    for _i: int in range(120):
        await process_frame

    var runtime := root.get_node_or_null("BrusselsCorridorTreeRuntime")
    if runtime == null:
        _fail("tree runtime autoload missing")
        return
    if not bool(runtime.call("ready_complete")) or bool(runtime.call("failed")):
        _fail("tree runtime did not reach healthy ready state")
        return
    if int(runtime.call("tree_count")) != 266 or int(runtime.call("batch_count")) != 3:
        _fail("source/batch contract changed")
        return
    if not bool(runtime.call("source_positions_unchanged")):
        _fail("source tree positions changed")
        return

    var positions: Array[Vector3] = runtime.call("source_positions")
    var ids: Array[int] = runtime.call("source_ids")
    if positions.size() != ids.size() or positions.is_empty():
        _fail("tree source arrays malformed")
        return

    var current_root := scene.get_node_or_null("BrusselsCorridorTrees") as Node3D
    if current_root == null:
        _fail("production tree root missing")
        return
    var current_dark := current_root.get_node_or_null("TreeFoliageDark") as MultiMeshInstance3D
    var current_light := current_root.get_node_or_null("TreeFoliageLight") as MultiMeshInstance3D
    if current_dark == null or current_light == null or current_dark.multimesh == null or current_light.multimesh == null:
        _fail("production foliage batches missing")
        return

    var old_dark: Array[Transform3D] = []
    var old_light: Array[Transform3D] = []
    for tree_index: int in range(positions.size()):
        for lobe_index: int in range(6):
            var transform := _old_lobe_transform(positions[tree_index], ids[tree_index], lobe_index)
            if lobe_index in OLD_LIGHT:
                old_light.append(transform)
            else:
                old_dark.append(transform)

    var before_root := Node3D.new()
    before_root.name = "LegacyTreeSilhouetteWitness"
    before_root.add_child(_make_batch("LegacyDark", current_dark.multimesh.mesh, old_dark))
    before_root.add_child(_make_batch("LegacyLight", current_light.multimesh.mesh, old_light))
    scene.add_child(before_root)

    current_dark.visible = false
    current_light.visible = false
    var player := scene.get_node_or_null("Player") as Node3D
    if player != null:
        player.visible = false
    for dynamic_path: String in ["PrototypeCar", "PhysicalCarB", "MidiUrbanLife", "TrafficManager"]:
        var dynamic := scene.get_node_or_null(dynamic_path) as Node3D
        if dynamic != null:
            dynamic.visible = false
    _hide_canvas(scene)

    var target := _best_target(positions)
    var camera := Camera3D.new()
    camera.fov = 69.0
    scene.add_child(camera)
    camera.look_at_from_position(target + Vector3(13.0, 1.65, 11.0), target + Vector3(0.0, 3.1, 0.0), Vector3.UP)
    camera.current = true

    var before := await _capture(BEFORE_PATH)
    if before == null:
        _fail("BEFORE capture missing")
        return

    before_root.visible = false
    current_dark.visible = true
    current_light.visible = true
    var after := await _capture(AFTER_PATH)
    if after == null:
        _fail("AFTER capture missing")
        return

    var s3 := _stats(before, after, 3)
    var s8 := _stats(before, after, 8)
    var f3 := float(s3["fraction"])
    var f8 := float(s8["fraction"])
    var bbox := s3["bbox"] as Rect2i
    print("BRUSSELS_TREE_SILHOUETTE_METRICS: gt3=%.4f%% gt8=%.4f%% bbox=%dx%d old_foliage=%d new_foliage=%d batches=3" % [f3 * 100.0, f8 * 100.0, bbox.size.x, bbox.size.y, positions.size() * 6, positions.size() * 8])
    if f3 < MIN_CHANGED_3 or f8 < MIN_CHANGED_8:
        _fail("tree silhouette change below predeclared full-frame impact gate")
        return
    if bbox.size.x < MIN_BBOX_WIDTH or bbox.size.y < MIN_BBOX_HEIGHT:
        _fail("tree silhouette change too spatially small")
        return

    print("BRUSSELS_TREE_SILHOUETTE_VISUAL_OK")
    quit(0)
