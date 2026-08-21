extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const BEFORE_PATH := "res://artifacts/visual/sidewalk_microtexture_before.png"
const AFTER_PATH := "res://artifacts/visual/sidewalk_microtexture_after.png"
const CONTROL_PATH := "res://artifacts/visual/sidewalk_microtexture_control.png"
const CORRIDOR_ANCHOR := Vector3(-272.04, 0.0, -217.07)
const MIN_CHANGED_3 := 0.0008
const MIN_CHANGED_8 := 0.0003
const MAX_CHANGED_3 := 0.0500
const MIN_BBOX_W := 180
const MIN_BBOX_H := 55
const MIN_CONTROL_CHANGED_8 := 0.0003

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

func _find_witness_sidewalk(roads: Node) -> CSGBox3D:
    var best: CSGBox3D = null
    var best_distance_sq: float = INF
    for child: Node in roads.get_children():
        if not child is CSGBox3D:
            continue
        var sidewalk := child as CSGBox3D
        if str(sidewalk.get_meta("material_family", "")) != "brussels_osm_sidewalk_surface_v1":
            continue
        if not sidewalk.visible or sidewalk.material == null:
            continue
        var delta := sidewalk.global_position - CORRIDOR_ANCHOR
        delta.y = 0.0
        var distance_sq: float = delta.length_squared()
        if distance_sq < best_distance_sq:
            best_distance_sq = distance_sq
            best = sidewalk
    return best

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
    var sidewalk := _find_witness_sidewalk(roads)
    if sidewalk == null:
        _fail("no rendered OSM sidewalk found near corridor anchor")
        return
    var material := sidewalk.material as ShaderMaterial
    if material == null:
        _fail("witness sidewalk does not use shared shader material")
        return

    var authored_strength_variant: Variant = material.get_shader_parameter("micro_grain_strength")
    var dark_variant: Variant = material.get_shader_parameter("dark_color")
    var light_variant: Variant = material.get_shader_parameter("light_color")
    if authored_strength_variant == null or dark_variant == null or light_variant == null:
        _fail("authored sidewalk shader parameters missing")
        return
    var authored_strength: float = float(authored_strength_variant)
    var authored_dark: Color = dark_variant as Color
    var authored_light: Color = light_variant as Color
    if authored_strength <= 0.0:
        _fail("authored micro_grain_strength must be positive")
        return

    var tangent := sidewalk.global_basis.x.normalized()
    var normal := sidewalk.global_basis.z.normalized()
    var length_m: float = sidewalk.size.x * sidewalk.global_basis.x.length()
    var width_m: float = sidewalk.size.z * sidewalk.global_basis.z.length()
    var height_m: float = sidewalk.size.y * sidewalk.global_basis.y.length()
    if length_m < 4.0 or width_m <= 0.0:
        _fail("witness sidewalk dimensions are unsuitable for player-frame proof")
        return
    var surface_center := sidewalk.global_position + Vector3.UP * (height_m * 0.5)
    var lateral_offset: float = minf(width_m * 0.20, 0.35)
    var forward_m: float = clampf(length_m * 0.35, 4.0, 10.0)
    var camera_pos := surface_center + normal * lateral_offset + Vector3.UP * 1.65 - tangent * minf(2.0, length_m * 0.15)
    var look_target := surface_center + normal * lateral_offset + tangent * forward_m + Vector3.UP * 0.10
    var camera := Camera3D.new()
    camera.look_at_from_position(camera_pos, look_target, Vector3.UP)
    camera.fov = 67.0
    camera.current = true
    scene.add_child(camera)
    print("BRUSSELS_SIDEWALK_MICROTEXTURE_WITNESS_TARGET: node=%s anchor_distance=%.3f length=%.3f width=%.3f eye=1.65 fov=67" % [sidewalk.name, Vector2(sidewalk.global_position.x - CORRIDOR_ANCHOR.x, sidewalk.global_position.z - CORRIDOR_ANCHOR.z).length(), length_m, width_m])

    material.set_shader_parameter("micro_grain_strength", 0.0)
    for _frame: int in range(8):
        await process_frame
    var before := await _capture(viewport, BEFORE_PATH)
    if before == null:
        _fail("1280x720 baseline capture failed")
        return

    # Control probe: prove this exact rendered surface and its material reach
    # player-frame pixels before using the microtexture metrics as a gate.
    material.set_shader_parameter("dark_color", Color(1.0, 0.0, 1.0, 1.0))
    material.set_shader_parameter("light_color", Color(1.0, 0.0, 1.0, 1.0))
    for _frame: int in range(8):
        await process_frame
    var control := await _capture(viewport, CONTROL_PATH)
    if control == null:
        _fail("1280x720 control capture failed")
        return
    var control_gt8 := _metrics(before, control, 8)
    var control_changed_8 := float(control_gt8["fraction"])
    var control_bbox_w := int(control_gt8["bbox_w"])
    var control_bbox_h := int(control_gt8["bbox_h"])
    print("BRUSSELS_SIDEWALK_MICROTEXTURE_CONTROL_METRICS: changed_gt8=%.6f bbox=%dx%d sidewalks=%d" % [control_changed_8, control_bbox_w, control_bbox_h, int(runtime.call("applied_sidewalk_count"))])
    material.set_shader_parameter("dark_color", authored_dark)
    material.set_shader_parameter("light_color", authored_light)
    if control_changed_8 < MIN_CONTROL_CHANGED_8:
        _fail("selected rendered sidewalk material does not reach player-frame pixels")
        return

    material.set_shader_parameter("micro_grain_strength", authored_strength)
    for _frame: int in range(8):
        await process_frame
    var after := await _capture(viewport, AFTER_PATH)
    if after == null:
        _fail("1280x720 microtexture capture failed")
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
