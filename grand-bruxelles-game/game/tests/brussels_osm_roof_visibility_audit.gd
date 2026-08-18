extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const EYE := Vector3(-272.04, 1.65, -217.07)
const YAW_DEGREES := 180.0
const FOV := 67.0
const MIN_CHANGED_8 := 0.0050
const MIN_BBOX_WIDTH := 300
const MIN_BBOX_HEIGHT := 90
const BEFORE_PATH := "res://artifacts/visual/osm_roof_visibility_before.png"
const OVERLAY_PATH := "res://artifacts/visual/osm_roof_visibility_overlay.png"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_ROOF_VISIBILITY_FAIL: %s" % message)
    quit(1)

func _hide_dynamics(scene: Node) -> void:
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

func _capture(viewport: SubViewport) -> Image:
    RenderingServer.force_draw()
    await process_frame
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty():
        return null
    return image

func _save(image: Image, path: String) -> bool:
    if image == null or image.is_empty():
        return false
    var absolute := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    return image.save_png(absolute) == OK

func _diff(before: Image, after: Image, threshold: int) -> Dictionary:
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
            if max(absf(a.r - b.r), max(absf(a.g - b.g), absf(a.b - b.b))) > limit:
                changed += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
    var bbox := Rect2i()
    if changed > 0:
        bbox = Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
    return {
        "fraction": float(changed) / float(before.get_width() * before.get_height()),
        "bbox": bbox,
    }

func _overlay_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(1.0, 0.0, 0.85, 1.0)
    material.roughness = 1.0
    material.metallic = 0.0
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    return material

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
    _hide_dynamics(scene)

    var buildings_root: Node3D = null
    for _frame: int in range(240):
        await process_frame
        buildings_root = scene.find_child("GeneratedBuildings", true, false) as Node3D
        if buildings_root != null:
            break
    if buildings_root == null:
        _fail("GeneratedBuildings missing")
        return

    var roofs: Array[CSGPolygon3D] = []
    var originals: Dictionary = {}
    var transforms: Dictionary = {}
    var polygons: Dictionary = {}
    var depths: Dictionary = {}
    for child: Node in buildings_root.get_children():
        if child is CSGPolygon3D and str(child.name).begins_with("Roof_"):
            var roof := child as CSGPolygon3D
            roofs.append(roof)
            var id := roof.get_instance_id()
            originals[id] = roof.material
            transforms[id] = roof.global_transform
            polygons[id] = roof.polygon
            depths[id] = roof.depth
    if roofs.size() != 139:
        _fail("generic roof count changed: %d" % roofs.size())
        return

    var camera := Camera3D.new()
    camera.name = "RoofVisibilityAuditCamera"
    camera.global_position = EYE
    camera.rotation_degrees.y = YAW_DEGREES
    camera.fov = FOV
    camera.current = true
    scene.add_child(camera)
    for _frame: int in range(5):
        await process_frame

    var before := await _capture(viewport)
    if before == null or not _save(before, BEFORE_PATH):
        _fail("baseline capture failed")
        return

    var overlay := _overlay_material()
    for roof: CSGPolygon3D in roofs:
        roof.material = overlay
    for _frame: int in range(5):
        await process_frame
    var after := await _capture(viewport)
    if after == null or not _save(after, OVERLAY_PATH):
        _fail("overlay capture failed")
        return

    for roof: CSGPolygon3D in roofs:
        var id := roof.get_instance_id()
        roof.material = originals[id] as Material
        if not roof.global_transform.is_equal_approx(transforms[id] as Transform3D):
            _fail("roof transform changed: %s" % roof.name)
            return
        if not roof.polygon == polygons[id]:
            _fail("roof polygon changed: %s" % roof.name)
            return
        if not is_equal_approx(roof.depth, float(depths[id])):
            _fail("roof depth changed: %s" % roof.name)
            return

    var stats := _diff(before, after, 8)
    var fraction := float(stats.get("fraction", -1.0))
    var bbox := stats.get("bbox", Rect2i()) as Rect2i
    print("BRUSSELS_OSM_ROOF_VISIBILITY_METRICS: roofs=%d eye=(%.2f,%.2f,%.2f) yaw=%.1f fov=%.1f changed_gt8=%.6f bbox=%dx%d geometry_unchanged=true" % [roofs.size(), EYE.x, EYE.y, EYE.z, YAW_DEGREES, FOV, fraction, bbox.size.x, bbox.size.y])
    if fraction < MIN_CHANGED_8:
        _fail("normal-player roof coverage below locked floor: %.4f%% < %.4f%%" % [fraction * 100.0, MIN_CHANGED_8 * 100.0])
        return
    if bbox.size.x < MIN_BBOX_WIDTH or bbox.size.y < MIN_BBOX_HEIGHT:
        _fail("roof visibility bbox below locked floor: %dx%d" % [bbox.size.x, bbox.size.y])
        return

    print("BRUSSELS_OSM_ROOF_VISIBILITY_OK: canonical_anneessens_eye=true roofs=%d changed_gt8=%.4f%% bbox=%dx%d runtime_authorized=false" % [roofs.size(), fraction * 100.0, bbox.size.x, bbox.size.y])
    quit(0)
