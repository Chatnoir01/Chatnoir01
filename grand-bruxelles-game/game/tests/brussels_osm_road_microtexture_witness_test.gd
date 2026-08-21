extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const BEFORE_PATH := "res://artifacts/visual/road_microtexture_before.png"
const AFTER_PATH := "res://artifacts/visual/road_microtexture_after.png"
const CONTROL_PATH := "res://artifacts/visual/road_microtexture_control.png"
const CORRIDOR_ANCHOR := Vector3(-272.04, 0.0, -217.07)
const MIN_CHANGED_3 := 0.0010
const MIN_CHANGED_8 := 0.0003
const MAX_CHANGED_3 := 0.0800
const MIN_BBOX_W := 220
const MIN_BBOX_CONTROL_COVERAGE := 0.75
const MIN_CONTROL_CHANGED_8 := 0.0005
const MIN_WITNESS_LENGTH_M := 8.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_ROAD_MICROTEXTURE_VISUAL_FAIL: %s" % message)
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
    return {
        "fraction": float(changed) / float(WIDTH * HEIGHT),
        "bbox_w": 0 if max_x < min_x else max_x - min_x + 1,
        "bbox_h": 0 if max_y < min_y else max_y - min_y + 1,
    }

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

func _road_length_m(road: CSGBox3D) -> float:
    return road.size.z * road.global_basis.z.length()

func _road_width_m(road: CSGBox3D) -> float:
    return road.size.x * road.global_basis.x.length()

func _find_witness_road(roads: Node) -> CSGBox3D:
    var best: CSGBox3D = null
    var best_distance_sq: float = INF
    for child: Node in roads.get_children():
        if not child is CSGBox3D or not child.name.begins_with("Road_"):
            continue
        var road := child as CSGBox3D
        if road.material == null or str(road.material.get_meta("material_family", "")) != "brussels_osm_road_surface_v1":
            continue
        if not road.visible or _road_length_m(road) < MIN_WITNESS_LENGTH_M or _road_width_m(road) <= 0.0:
            continue
        var delta := road.global_position - CORRIDOR_ANCHOR
        delta.y = 0.0
        var distance_sq: float = delta.length_squared()
        if distance_sq < best_distance_sq:
            best_distance_sq = distance_sq
            best = road
    return best

func _collect_shared_materials(roads: Node) -> Array[ShaderMaterial]:
    var materials: Array[ShaderMaterial] = []
    var ids := {}
    for child: Node in roads.get_children():
        if not child is CSGBox3D or not child.name.begins_with("Road_"):
            continue
        var road := child as CSGBox3D
        var material := road.material as ShaderMaterial
        if material == null or str(material.get_meta("material_family", "")) != "brussels_osm_road_surface_v1":
            continue
        if not ids.has(material.get_instance_id()):
            ids[material.get_instance_id()] = true
            materials.append(material)
    return materials

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

    var roads := scene.get_node_or_null("BrusselsOSM/GeneratedRoads")
    if roads == null:
        _fail("GeneratedRoads missing")
        return
    var road := _find_witness_road(roads)
    if road == null:
        _fail("no suitable rendered OSM road found near corridor anchor")
        return
    var materials := _collect_shared_materials(roads)
    if materials.is_empty() or materials.size() > 2:
        _fail("shared road material set invalid: %d" % materials.size())
        return

    var strengths: Array[float] = []
    var darks: Array[Color] = []
    var lights: Array[Color] = []
    for material: ShaderMaterial in materials:
        var strength_variant: Variant = material.get_shader_parameter("micro_grain_strength")
        var dark_variant: Variant = material.get_shader_parameter("dark_color")
        var light_variant: Variant = material.get_shader_parameter("light_color")
        if strength_variant == null or dark_variant == null or light_variant == null:
            _fail("authored road shader parameters missing")
            return
        strengths.append(float(strength_variant))
        darks.append(dark_variant as Color)
        lights.append(light_variant as Color)
        if strengths.back() <= 0.0:
            _fail("authored micro_grain_strength must be positive")
            return

    var tangent := road.global_basis.z.normalized()
    var length_m := _road_length_m(road)
    var width_m := _road_width_m(road)
    var height_m := road.size.y * road.global_basis.y.length()
    var surface_center := road.global_position + Vector3.UP * (height_m * 0.5)
    var camera_pos := surface_center - tangent * minf(3.0, length_m * 0.20) + Vector3.UP * 1.65
    var look_target := surface_center + tangent * clampf(length_m * 0.38, 7.0, 18.0) + Vector3.UP * 0.08
    var camera := Camera3D.new()
    camera.look_at_from_position(camera_pos, look_target, Vector3.UP)
    camera.fov = 67.0
    camera.current = true
    scene.add_child(camera)
    print("BRUSSELS_ROAD_MICROTEXTURE_WITNESS_TARGET: node=%s length=%.3f width=%.3f eye=1.65 fov=67 materials=%d" % [road.name, length_m, width_m, materials.size()])

    for material: ShaderMaterial in materials:
        material.set_shader_parameter("micro_grain_strength", 0.0)
    for _frame: int in range(8):
        await process_frame
    var before := await _capture(viewport, BEFORE_PATH)
    if before == null:
        _fail("1280x720 baseline capture failed")
        return

    for index: int in range(materials.size()):
        materials[index].set_shader_parameter("dark_color", Color(1.0, 0.0, 1.0, 1.0))
        materials[index].set_shader_parameter("light_color", Color(1.0, 0.0, 1.0, 1.0))
    for _frame: int in range(8):
        await process_frame
    var control := await _capture(viewport, CONTROL_PATH)
    if control == null:
        _fail("1280x720 control capture failed")
        return
    var control_gt8 := _metrics(before, control, 8)
    var control_bbox_w := int(control_gt8["bbox_w"])
    var control_bbox_h := int(control_gt8["bbox_h"])
    print("BRUSSELS_ROAD_MICROTEXTURE_CONTROL_METRICS: changed_gt8=%.6f bbox=%dx%d" % [float(control_gt8["fraction"]), control_bbox_w, control_bbox_h])
    for index: int in range(materials.size()):
        materials[index].set_shader_parameter("dark_color", darks[index])
        materials[index].set_shader_parameter("light_color", lights[index])
    if float(control_gt8["fraction"]) < MIN_CONTROL_CHANGED_8:
        _fail("selected rendered road materials do not reach player-frame pixels")
        return

    for index: int in range(materials.size()):
        materials[index].set_shader_parameter("micro_grain_strength", strengths[index])
    for _frame: int in range(8):
        await process_frame
    var after := await _capture(viewport, AFTER_PATH)
    if after == null:
        _fail("1280x720 microtexture capture failed")
        return

    var gt3 := _metrics(before, after, 3)
    var gt8 := _metrics(before, after, 8)
    var changed_3 := float(gt3["fraction"])
    var changed_8 := float(gt8["fraction"])
    var bbox_w := int(gt3["bbox_w"])
    var bbox_h := int(gt3["bbox_h"])
    print("BRUSSELS_ROAD_MICROTEXTURE_VISUAL_METRICS: changed_gt3=%.6f changed_gt8=%.6f bbox=%dx%d authored_strength_regular=%.3f" % [changed_3, changed_8, bbox_w, bbox_h, strengths[0]])
    if changed_3 < MIN_CHANGED_3 or changed_8 < MIN_CHANGED_8:
        _fail("non-semantic road microtexture is not player-visible enough")
        return
    if changed_3 > MAX_CHANGED_3:
        _fail("non-semantic road microtexture overpowers the player frame")
        return
    if bbox_w < MIN_BBOX_W:
        _fail("non-semantic road microtexture lacks broad horizontal screen coverage")
        return
    # The control render is the upper bound of pixels this material family can
    # affect with the locked camera. Requiring 80 px of vertical bbox was
    # impossible when the material itself occupies only 46 px vertically.
    # Keep the camera and pixel-delta thresholds frozen; require the actual
    # microtexture to cover at least 75% of the control-material footprint.
    if control_bbox_w <= 0 or control_bbox_h <= 0:
        _fail("road control footprint missing")
        return
    if float(bbox_w) / float(control_bbox_w) < MIN_BBOX_CONTROL_COVERAGE or float(bbox_h) / float(control_bbox_h) < MIN_BBOX_CONTROL_COVERAGE:
        _fail("non-semantic road microtexture does not cover enough of the visible road footprint")
        return
    print("BRUSSELS_ROAD_MICROTEXTURE_VISUAL_OK: eye=1.65m fov=67 changed_gt3=%.4f%% changed_gt8=%.4f%% bbox=%dx%d control_bbox=%dx%d geometry_changed=false composition_claimed=false" % [changed_3 * 100.0, changed_8 * 100.0, bbox_w, bbox_h, control_bbox_w, control_bbox_h])
    quit(0)
