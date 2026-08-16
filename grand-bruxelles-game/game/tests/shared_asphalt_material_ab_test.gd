extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const WARMUP_FRAMES := 110
const OUTPUT_DIR := "res://artifacts/qa/shared_asphalt_material_ab"
const BEFORE_PATH := OUTPUT_DIR + "/before_flat.png"
const AFTER_PATH := OUTPUT_DIR + "/after_asphalt.png"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("SHARED_ASPHALT_AB_FAIL: %s" % message)
    quit(1)

func _save_viewport(viewport: SubViewport, path: String) -> Image:
    RenderingServer.force_draw()
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty():
        return null
    var absolute := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    if image.save_png(absolute) != OK:
        return null
    return image

func _delta_metrics(before: Image, after: Image) -> Dictionary:
    if before.get_size() != after.get_size():
        return {}
    var changed_3: int = 0
    var changed_8: int = 0
    var min_x: int = WIDTH
    var min_y: int = HEIGHT
    var max_x: int = -1
    var max_y: int = -1
    const THRESHOLD_3 := 3.0 / 255.0
    const THRESHOLD_8 := 8.0 / 255.0
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta: float = maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
            if delta > THRESHOLD_3:
                changed_3 += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
            if delta > THRESHOLD_8:
                changed_8 += 1
    var total := float(WIDTH * HEIGHT)
    return {
        "changed_3_fraction": float(changed_3) / total,
        "changed_8_fraction": float(changed_8) / total,
        "bbox_width": 0 if max_x < min_x else max_x - min_x + 1,
        "bbox_height": 0 if max_y < min_y else max_y - min_y + 1,
    }

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    if scene == null:
        _fail("main scene did not instantiate")
        return

    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)

    var traffic_manager: Node = scene.get_node_or_null("TrafficManager")
    if traffic_manager != null:
        traffic_manager.set("auto_spawn_runtime", false)
    var prototype_label := scene.get_node_or_null("PrototypeLabel") as CanvasItem
    if prototype_label != null:
        prototype_label.visible = false
    viewport.add_child(scene)

    for _frame: int in range(WARMUP_FRAMES):
        await process_frame

    var asphalt_runtime: Node = scene.get_node_or_null("BrusselsSharedAsphaltRuntime")
    if asphalt_runtime == null:
        _fail("shared asphalt runtime missing from production scene")
        return
    var roads_root: Node = scene.get_node_or_null("BrusselsOSM/GeneratedRoads")
    if roads_root == null:
        _fail("generated road root missing")
        return

    var roads: Array[CSGBox3D] = []
    var production_materials: Array[Material] = []
    var major_count: int = 0
    var local_count: int = 0
    for child: Node in roads_root.get_children():
        if not child.name.begins_with("Road_"):
            continue
        var road := child as CSGBox3D
        if road == null:
            continue
        var material := road.material as StandardMaterial3D
        if material == null:
            _fail("road material missing: %s" % road.name)
            return
        if str(material.get_meta("brussels_material_family", "")) != "shared_asphalt":
            _fail("road did not receive shared asphalt: %s" % road.name)
            return
        if not bool(material.get_meta("procedural_original_asset", false)):
            _fail("asphalt provenance metadata missing")
            return
        if not bool(material.get_meta("source_geometry_unchanged", false)):
            _fail("asphalt changed geometry contract")
            return
        var family := str(material.get_meta("asphalt_road_family", ""))
        if family == "major":
            major_count += 1
        elif family == "local":
            local_count += 1
        else:
            _fail("unknown asphalt road family: %s" % family)
            return
        roads.append(road)
        production_materials.append(material)

    if roads.size() < 250:
        _fail("shared asphalt coverage is too narrow: %d road segments" % roads.size())
        return
    if major_count <= 0 or local_count <= 0:
        _fail("major/local road material distinction was lost")
        return

    scene.process_mode = Node.PROCESS_MODE_DISABLED
    for index: int in range(roads.size()):
        var family := str((production_materials[index] as StandardMaterial3D).get_meta("asphalt_road_family", "local"))
        roads[index].material = asphalt_runtime.call("flat_reference_material", family) as Material
    await process_frame
    await process_frame
    var before := _save_viewport(viewport, BEFORE_PATH)
    if before == null:
        _fail("could not save flat BEFORE frame")
        return

    for index: int in range(roads.size()):
        roads[index].material = production_materials[index]
    await process_frame
    await process_frame
    var after := _save_viewport(viewport, AFTER_PATH)
    if after == null:
        _fail("could not save asphalt AFTER frame")
        return

    var metrics := _delta_metrics(before, after)
    if metrics.is_empty():
        _fail("could not compare A/B frames")
        return
    var changed_3 := float(metrics["changed_3_fraction"])
    var changed_8 := float(metrics["changed_8_fraction"])
    var bbox_width := int(metrics["bbox_width"])
    var bbox_height := int(metrics["bbox_height"])
    print("SHARED_ASPHALT_AB_METRICS: roads=%d major=%d local=%d gt3=%.4f%% gt8=%.4f%% bbox=%dx%d" % [roads.size(), major_count, local_count, changed_3 * 100.0, changed_8 * 100.0, bbox_width, bbox_height])

    if changed_3 < 0.0075:
        _fail("player-frame improvement is too small: %.4f%% >3 RGB" % (changed_3 * 100.0))
        return
    if changed_8 < 0.0025:
        _fail("player-frame strong delta is too small: %.4f%% >8 RGB" % (changed_8 * 100.0))
        return
    if bbox_width < 500 or bbox_height < 120:
        _fail("visible change is too localized: bbox=%dx%d" % [bbox_width, bbox_height])
        return

    print("SHARED_ASPHALT_AB_OK: %s %s" % [BEFORE_PATH, AFTER_PATH])
    viewport.queue_free()
    quit(0)
