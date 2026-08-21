extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const BEFORE_PATH := "res://artifacts/visual/sidewalk_microtexture_before.png"
const AFTER_PATH := "res://artifacts/visual/sidewalk_microtexture_after.png"
const CAMERA_POS := Vector3(-272.04, 1.65, -217.07)
const LOOK_TARGET := Vector3(-260.0, 0.10, -208.0)
const MIN_CHANGED_3 := 0.0008
const MIN_CHANGED_8 := 0.0003
const MAX_CHANGED_3 := 0.0500
const MIN_BBOX_W := 180
const MIN_BBOX_H := 55

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_SIDEWALK_MICROTEXTURE_VISUAL_FAIL: %s" % message)
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

func _metrics(before: Image, after: Image, threshold: int) -> Dictionary:
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
            if max(abs(a.r - b.r), max(abs(a.g - b.g), abs(a.b - b.b))) > limit:
                changed += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
    var bbox_w := 0 if max_x < min_x else max_x - min_x + 1
    var bbox_h := 0 if max_y < min_y else max_y - min_y + 1
    return {"fraction": float(changed) / float(WIDTH * HEIGHT), "bbox_w": bbox_w, "bbox_h": bbox_h}

func _hide_dynamic(scene: Node) -> void:
    for path: String in ["LocationLabel", "MissionLabel", "PrototypeLabel", "MiniMap", "MobileControls"]:
        var item := scene.get_node_or_null(path) as CanvasItem
        if item != null:
            item.visible = false
    for path: String in ["Player", "PrototypeCar", "PhysicalCarB", "MidiHeroZone", "MidiUrbanLife"]:
        var spatial := scene.get_node_or_null(path) as Node3D
        if spatial != null:
            spatial.visible = false
    var traffic := scene.get_node_or_null("TrafficManager")
    if traffic != null:
        traffic.set("auto_spawn_runtime", false)
        if traffic is Node3D:
            (traffic as Node3D).visible = false

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene missing")
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

    for _frame: int in range(120):
        await process_frame
    var runtime := root.get_node_or_null("BrusselsOsmSidewalkSurfaceRuntime")
    if runtime == null:
        _fail("shared sidewalk surface autoload missing")
        return
    if not bool(runtime.call("ready_complete")) or bool(runtime.call("failed")):
        _fail("shared sidewalk surface runtime did not become ready")
        return
    if int(runtime.call("applied_sidewalk_count")) < 100:
        _fail("too few shared sidewalk surfaces for corridor proof")
        return
    if not bool(runtime.call("geometry_unchanged")):
        _fail("sidewalk geometry changed before witness")
        return

    var roads := scene.get_node_or_null("BrusselsOSM/GeneratedRoads")
    if roads == null:
        _fail("GeneratedRoads missing")
        return
    var material: ShaderMaterial = null
    for child: Node in roads.get_children():
        if child is CSGBox3D and str(child.get_meta("material_family", "")) == "brussels_osm_sidewalk_surface_v1":
            material = (child as CSGBox3D).material as ShaderMaterial
            if material != null:
                break
    if material == null:
        _fail("shared sidewalk material not found on generated sidewalk")
        return

    var authored_strength_variant := material.get_shader_parameter("micro_grain_strength")
    if authored_strength_variant == null:
        _fail("authored micro_grain_strength missing")
        return
    var authored_strength := float(authored_strength_variant)
    if authored_strength <= 0.0:
        _fail("authored micro_grain_strength must be positive")
        return

    var camera := Camera3D.new()
    camera.position = CAMERA_POS
    camera.look_at_from_position(CAMERA_POS, LOOK_TARGET, Vector3.UP)
    camera.fov = 67.0
    camera.current = true
    scene.add_child(camera)

    material.set_shader_parameter("micro_grain_strength", 0.0)
    for _frame: int in range(8):
        await process_frame
    var before := await _capture(viewport, BEFORE_PATH)
    material.set_shader_parameter("micro_grain_strength", authored_strength)
    for _frame: int in range(8):
        await process_frame
    var after := await _capture(viewport, AFTER_PATH)
    if before == null or after == null:
        _fail("1280x720 A/B capture failed")
        return
    if not bool(runtime.call("geometry_unchanged")):
        _fail("material A/B modified sidewalk geometry")
        return

    var gt3 := _metrics(before, after, 3)
    var gt8 := _metrics(before, after, 8)
    var changed_3 := float(gt3["fraction"])
    var changed_8 := float(gt8["fraction"])
    var bbox_w := int(gt3["bbox_w"])
    var bbox_h := int(gt3["bbox_h"])
    print("BRUSSELS_SIDEWALK_MICROTEXTURE_VISUAL_METRICS: changed_gt3=%.6f changed_gt8=%.6f bbox=%dx%d sidewalks=%d authored_strength=%.3f" % [changed_3, changed_8, bbox_w, bbox_h, int(runtime.call("applied_sidewalk_count")), authored_strength])
    if changed_3 < MIN_CHANGED_3 or changed_8 < MIN_CHANGED_8:
        _fail("non-semantic microtexture is not player-visible enough")
        return
    if changed_3 > MAX_CHANGED_3:
        _fail("non-semantic microtexture overpowers the player frame")
        return
    if bbox_w < MIN_BBOX_W or bbox_h < MIN_BBOX_H:
        _fail("non-semantic microtexture lacks broad screen coverage")
        return
    print("BRUSSELS_SIDEWALK_MICROTEXTURE_VISUAL_OK: eye=1.65m fov=67 changed_gt3=%.4f%% changed_gt8=%.4f%% bbox=%dx%d authored_strength=%.3f geometry_changed=false paving_dimensions_claimed=false" % [changed_3 * 100.0, changed_8 * 100.0, bbox_w, bbox_h, authored_strength])
    quit(0)
