extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const BEFORE_PATH := "res://artifacts/visual/osm_facade_surface_before.png"
const AFTER_PATH := "res://artifacts/visual/osm_facade_surface_after.png"
const ANNEESSENS := Vector2(-272.04, -217.07)
const SEARCH_RADIUS_M := 105.0
const MIN_CHANGED_3 := 0.008
const MIN_CHANGED_8 := 0.003

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_FACADE_SURFACE_VISUAL_FAIL: %s" % message)
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

func _changed_fraction(before: Image, after: Image, threshold: int) -> float:
    if before == null or after == null or before.get_size() != after.get_size():
        return -1.0
    var changed := 0
    var total := before.get_width() * before.get_height()
    var limit := float(threshold) / 255.0
    for y: int in range(before.get_height()):
        for x: int in range(before.get_width()):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            if max(abs(a.r - b.r), max(abs(a.g - b.g), abs(a.b - b.b))) > limit:
                changed += 1
    return float(changed) / float(total)

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

func _polygon_area(points: PackedVector2Array) -> float:
    if points.size() < 3:
        return 0.0
    var sum := 0.0
    for index: int in range(points.size()):
        var a := points[index]
        var b := points[(index + 1) % points.size()]
        sum += a.x * b.y - b.x * a.y
    return absf(sum) * 0.5

func _select_generic_building(root_node: Node3D) -> CSGPolygon3D:
    var best: CSGPolygon3D = null
    var best_score := -INF
    for child: Node in root_node.get_children():
        if not child is CSGPolygon3D or not str(child.name).begins_with("Building_"):
            continue
        var building := child as CSGPolygon3D
        var location := Vector2(building.global_position.x, building.global_position.z)
        var distance := location.distance_to(ANNEESSENS)
        if distance < 18.0 or distance > SEARCH_RADIUS_M:
            continue
        var area := _polygon_area(building.polygon)
        if area < 35.0:
            continue
        var score := area / maxf(distance, 1.0)
        if score > best_score:
            best = building
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

    var runtime := root.get_node_or_null("BrusselsOsmFacadeSurfaceRuntime")
    if runtime == null:
        _fail("production facade-surface autoload missing")
        return
    for _frame: int in range(240):
        if bool(runtime.call("ready_complete")):
            break
        await process_frame
    if not bool(runtime.call("ready_complete")) or bool(runtime.call("failed")):
        _fail("production facade-surface runtime did not bind cleanly")
        return

    var buildings_root := scene.get_node_or_null("BrusselsOSM/GeneratedBuildings") as Node3D
    if buildings_root == null:
        _fail("GeneratedBuildings missing")
        return
    var building := _select_generic_building(buildings_root)
    if building == null:
        _fail("no legitimate generic OSM building found near Anneessens")
        return

    var original_transform := building.global_transform
    var original_polygon := building.polygon.duplicate()
    var original_depth := building.depth
    var building_xz := Vector2(building.global_position.x, building.global_position.z)
    var outward := ANNEESSENS - building_xz
    if outward.length() < 0.01:
        _fail("invalid facade camera direction")
        return
    outward = outward.normalized()
    var camera_distance := clampf(building_xz.distance_to(ANNEESSENS) * 0.48, 16.0, 30.0)
    var camera_xz := building_xz + outward * camera_distance

    var camera := Camera3D.new()
    camera.position = Vector3(camera_xz.x, 1.65, camera_xz.y)
    var target_height := clampf(building.depth * 0.42, 4.0, 8.5)
    camera.look_at_from_position(camera.position, Vector3(building_xz.x, target_height, building_xz.y), Vector3.UP)
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
        _fail("1280x720 production facade A/B capture failed")
        return
    if not building.global_transform.is_equal_approx(original_transform):
        _fail("building transform changed during material-only A/B")
        return
    if building.polygon != original_polygon or not is_equal_approx(building.depth, original_depth):
        _fail("building geometry changed during material-only A/B")
        return

    var changed_3 := _changed_fraction(before, after, 3)
    var changed_8 := _changed_fraction(before, after, 8)
    print("BRUSSELS_OSM_FACADE_SURFACE_VISUAL_METRICS: building=%s distance=%.2f changed_gt3=%.6f changed_gt8=%.6f" % [building.name, camera_distance, changed_3, changed_8])
    if changed_3 < MIN_CHANGED_3 or changed_8 < MIN_CHANGED_8:
        _fail("full-frame facade change too weak: gt3=%.4f%% gt8=%.4f%%" % [changed_3 * 100.0, changed_8 * 100.0])
        return

    print("BRUSSELS_OSM_FACADE_SURFACE_VISUAL_OK: building=%s player_eye_height=1.65m fov=67 geometry_unchanged=true material_identity_claimed=false changed_gt3=%.4f%% changed_gt8=%.4f%%" % [building.name, changed_3 * 100.0, changed_8 * 100.0])
    quit(0)
