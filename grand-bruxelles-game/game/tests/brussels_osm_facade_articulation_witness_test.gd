extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const BEFORE_PATH := "res://artifacts/visual/osm_facade_articulation_before.png"
const AFTER_PATH := "res://artifacts/visual/osm_facade_articulation_after.png"
const ANNEESSENS := Vector2(-272.04, -217.07)
const SEARCH_RADIUS_M := 105.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_FACADE_ARTICULATION_VISUAL_FAIL: %s" % message)
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

    var base_runtime := root.get_node_or_null("BrusselsOsmFacadeSurfaceRuntime")
    var runtime := root.get_node_or_null("BrusselsOsmFacadeArticulationRuntime")
    if base_runtime == null or runtime == null:
        _fail("facade runtimes missing")
        return
    for _frame: int in range(300):
        if bool(runtime.call("ready_complete")):
            break
        await process_frame
    if not bool(runtime.call("ready_complete")) or bool(runtime.call("failed")):
        _fail("facade articulation runtime did not bind cleanly")
        return
    if not bool(base_runtime.call("enhanced_enabled")):
        _fail("production facade baseline must stay enabled")
        return
    if str(runtime.call("baseline_material_family")) != "brussels_osm_facade_surface_v1":
        _fail("A/B baseline is not current production facade surface")
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
    for _frame: int in range(8):
        await process_frame
    var before := await _capture(viewport, BEFORE_PATH)

    runtime.call("set_enhanced_enabled", true)
    for _frame: int in range(8):
        await process_frame
    var after := await _capture(viewport, AFTER_PATH)
    if before == null or after == null:
        _fail("1280x720 current-vs-candidate capture failed")
        return
    if not building.global_transform.is_equal_approx(original_transform):
        _fail("building transform changed during material-only A/B")
        return
    if building.polygon != original_polygon or not is_equal_approx(building.depth, original_depth):
        _fail("building geometry changed during material-only A/B")
        return
    if not bool(runtime.call("geometry_unchanged")):
        _fail("runtime geometry invariant failed")
        return

    print("BRUSSELS_OSM_FACADE_ARTICULATION_VISUAL_CAPTURED: building=%s distance=%.2f player_eye_height=1.65m fov=67 baseline=brussels_osm_facade_surface_v1 candidate=brussels_osm_facade_articulation_v1 geometry_unchanged=true" % [building.name, camera_distance])
    quit(0)
