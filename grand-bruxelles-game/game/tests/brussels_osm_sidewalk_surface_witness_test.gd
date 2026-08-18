extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const PROBE_WIDTH := 320
const PROBE_HEIGHT := 180
const BEFORE_PATH := "res://artifacts/visual/osm_sidewalk_surface_before.png"
const AFTER_PATH := "res://artifacts/visual/osm_sidewalk_surface_after.png"
const EDGE_BEFORE_PATH := "res://artifacts/visual/sidewalk_edge_before.png"
const EDGE_AFTER_PATH := "res://artifacts/visual/sidewalk_edge_after.png"
const BOURSE := Vector2(81.54, -664.58)
const SEARCH_RADIUS_M := 220.0
const MIN_LENGTH_M := 12.0
const MAX_PROBES := 32
const MIN_PROBE_CHANGED := 0.008
const MIN_CHANGED_3 := 0.06
const MIN_CHANGED_8 := 0.03
const EDGE_MIN_BOURSE_DISTANCE_M := 120.0
const EDGE_MIN_PROBE_CHANGED := 0.002
const EDGE_MIN_CHANGED_3 := 0.0025
const EDGE_MIN_CHANGED_8 := 0.0010
const EDGE_MIN_BBOX_WIDTH := 400
const EDGE_MIN_BBOX_HEIGHT := 100

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_SIDEWALK_SURFACE_VISUAL_FAIL: %s" % message)
    quit(1)

func _grab(viewport: SubViewport) -> Image:
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

func _changed_fraction(before: Image, after: Image, threshold: int) -> float:
    return float(_diff_stats(before, after, threshold).get("fraction", -1.0))

func _diff_stats(before: Image, after: Image, threshold: int) -> Dictionary:
    if before == null or after == null or before.get_size() != after.get_size():
        return {"fraction": -1.0, "bbox": Rect2i()}
    var changed := 0
    var total := before.get_width() * before.get_height()
    var limit := float(threshold) / 255.0
    var min_x := before.get_width()
    var min_y := before.get_height()
    var max_x := -1
    var max_y := -1
    for y: int in range(before.get_height()):
        for x: int in range(before.get_width()):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            if max(abs(a.r - b.r), max(abs(a.g - b.g), abs(a.b - b.b))) > limit:
                changed += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
    var bbox := Rect2i()
    if changed > 0:
        bbox = Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
    return {"fraction": float(changed) / float(total), "bbox": bbox}

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

func _is_sidewalk(box: CSGBox3D) -> bool:
    if str(box.name).begins_with("Road_"):
        return false
    if absf(box.size.y - 0.12) > 0.005:
        return false
    return absf(box.size.x - 1.85) <= 0.02 or absf(box.size.x - 2.55) <= 0.02

func _candidate_sidewalks(roads_root: Node3D, minimum_bourse_distance: float = 0.0) -> Array[CSGBox3D]:
    var candidates: Array[CSGBox3D] = []
    for child: Node in roads_root.get_children():
        if not child is CSGBox3D:
            continue
        var sidewalk := child as CSGBox3D
        if not _is_sidewalk(sidewalk) or sidewalk.size.z < MIN_LENGTH_M:
            continue
        var midpoint := Vector2(sidewalk.global_position.x, sidewalk.global_position.z)
        var distance := midpoint.distance_to(BOURSE)
        if distance > SEARCH_RADIUS_M or distance < minimum_bourse_distance:
            continue
        candidates.append(sidewalk)
    candidates.sort_custom(func(a: CSGBox3D, b: CSGBox3D) -> bool: return a.size.z > b.size.z)
    return candidates

func _aim_camera(camera: Camera3D, sidewalk: CSGBox3D) -> void:
    var travel := clampf(sidewalk.size.z * 0.34, 6.0, 15.0)
    var look_distance := clampf(sidewalk.size.z * 0.27, 5.0, 13.0)
    var camera_position := sidewalk.global_transform * Vector3(0.0, 1.65, travel)
    var target := sidewalk.global_transform * Vector3(0.0, 0.02, -look_distance)
    camera.look_at_from_position(camera_position, target, Vector3.UP)
    camera.fov = 67.0

func _probe_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(1.0, 0.0, 0.85, 1.0)
    material.emission_enabled = true
    material.emission = Color(1.0, 0.0, 0.85, 1.0)
    material.emission_energy_multiplier = 3.0
    material.roughness = 1.0
    return material

func _select_rendered_sidewalk(viewport: SubViewport, camera: Camera3D, candidates: Array[CSGBox3D], runtime: Node) -> CSGBox3D:
    viewport.size = Vector2i(PROBE_WIDTH, PROBE_HEIGHT)
    runtime.call("set_enhanced_enabled", false)
    var probe := _probe_material()
    var count := mini(candidates.size(), MAX_PROBES)
    for index: int in range(count):
        var sidewalk := candidates[index]
        _aim_camera(camera, sidewalk)
        for _frame: int in range(2):
            await process_frame
        var legacy := sidewalk.material
        var baseline := await _grab(viewport)
        sidewalk.material = probe
        for _frame: int in range(2):
            await process_frame
        var highlighted := await _grab(viewport)
        sidewalk.material = legacy
        var changed := _changed_fraction(baseline, highlighted, 12)
        if changed >= MIN_PROBE_CHANGED:
            print("BRUSSELS_OSM_SIDEWALK_SURFACE_PROBE_OK: index=%d length=%.2f width=%.2f bourse_distance=%.2f visible_fraction=%.5f" % [index, sidewalk.size.z, sidewalk.size.x, Vector2(sidewalk.global_position.x, sidewalk.global_position.z).distance_to(BOURSE), changed])
            return sidewalk
    return null

func _select_edge_sidewalk(viewport: SubViewport, camera: Camera3D, candidates: Array[CSGBox3D], edge_runtime: Node) -> CSGBox3D:
    viewport.size = Vector2i(PROBE_WIDTH, PROBE_HEIGHT)
    var count := mini(candidates.size(), MAX_PROBES)
    for index: int in range(count):
        var sidewalk := candidates[index]
        _aim_camera(camera, sidewalk)
        edge_runtime.call("set_enhanced_enabled", false)
        for _frame: int in range(2):
            await process_frame
        var before := await _grab(viewport)
        edge_runtime.call("set_enhanced_enabled", true)
        for _frame: int in range(2):
            await process_frame
        var after := await _grab(viewport)
        var changed := _changed_fraction(before, after, 3)
        if changed >= EDGE_MIN_PROBE_CHANGED:
            print("BRUSSELS_SIDEWALK_EDGE_PROBE_OK: index=%d length=%.2f width=%.2f bourse_distance=%.2f visible_fraction=%.5f" % [index, sidewalk.size.z, sidewalk.size.x, Vector2(sidewalk.global_position.x, sidewalk.global_position.z).distance_to(BOURSE), changed])
            return sidewalk
    return null

func _run_edge_gate(scene: Node3D, viewport: SubViewport, camera: Camera3D, roads_root: Node3D) -> bool:
    var edge_runtime := root.get_node_or_null("BrusselsSidewalkEdgeRuntime")
    if edge_runtime == null:
        _fail("sidewalk edge autoload missing")
        return false
    edge_runtime.call("bind_scene", scene)
    for _frame: int in range(8):
        await process_frame
    if bool(edge_runtime.call("failed")) or not bool(edge_runtime.call("ready_complete")):
        _fail("sidewalk edge runtime did not bind cleanly")
        return false
    if int(edge_runtime.call("sidewalk_count")) != 430 or int(edge_runtime.call("edge_count")) != 430:
        _fail("sidewalk edge production reuse count changed")
        return false
    if int(edge_runtime.call("batch_count")) != 1 or int(edge_runtime.call("collision_count")) != 0:
        _fail("sidewalk edge performance-cost contract changed")
        return false
    if not bool(edge_runtime.call("geometry_unchanged")) or not bool(edge_runtime.call("edge_visual_within_sidewalk_envelope")):
        _fail("sidewalk edge geometry/envelope invariant failed")
        return false

    var candidates := _candidate_sidewalks(roads_root, EDGE_MIN_BOURSE_DISTANCE_M)
    if candidates.is_empty():
        _fail("no non-Bourse-owned sidewalk edge candidates")
        return false
    var sidewalk := await _select_edge_sidewalk(viewport, camera, candidates, edge_runtime)
    if sidewalk == null:
        _fail("no rendered non-Bourse-owned sidewalk edge found")
        return false

    var original_transform := sidewalk.global_transform
    var original_size := sidewalk.size
    _aim_camera(camera, sidewalk)
    viewport.size = Vector2i(WIDTH, HEIGHT)
    edge_runtime.call("set_enhanced_enabled", false)
    for _frame: int in range(5):
        await process_frame
    var before := await _grab(viewport)
    edge_runtime.call("set_enhanced_enabled", true)
    for _frame: int in range(5):
        await process_frame
    var after := await _grab(viewport)
    if before == null or after == null:
        _fail("sidewalk edge 1280x720 A/B capture failed")
        return false
    if not _save(before, EDGE_BEFORE_PATH) or not _save(after, EDGE_AFTER_PATH):
        _fail("sidewalk edge evidence save failed")
        return false
    if not sidewalk.global_transform.is_equal_approx(original_transform) or not sidewalk.size.is_equal_approx(original_size) or not bool(edge_runtime.call("geometry_unchanged")):
        _fail("sidewalk geometry changed during edge A/B")
        return false

    var stats3 := _diff_stats(before, after, 3)
    var stats8 := _diff_stats(before, after, 8)
    var changed3 := float(stats3.get("fraction", -1.0))
    var changed8 := float(stats8.get("fraction", -1.0))
    var bbox := stats3.get("bbox", Rect2i()) as Rect2i
    print("BRUSSELS_SIDEWALK_EDGE_VISUAL_METRICS: length=%.2f width=%.2f bourse_distance=%.2f changed_gt3=%.6f changed_gt8=%.6f bbox=%dx%d sidewalks=430 edges=430 batches=1 collisions=0" % [sidewalk.size.z, sidewalk.size.x, Vector2(sidewalk.global_position.x, sidewalk.global_position.z).distance_to(BOURSE), changed3, changed8, bbox.size.x, bbox.size.y])
    if changed3 < EDGE_MIN_CHANGED_3 or changed8 < EDGE_MIN_CHANGED_8:
        _fail("sidewalk edge screen impact below locked threshold: gt3=%.4f%% gt8=%.4f%%" % [changed3 * 100.0, changed8 * 100.0])
        return false
    if bbox.size.x < EDGE_MIN_BBOX_WIDTH or bbox.size.y < EDGE_MIN_BBOX_HEIGHT:
        _fail("sidewalk edge change bbox below locked threshold: %dx%d" % [bbox.size.x, bbox.size.y])
        return false

    # The existing workflow uploads these two paths. Mirror the edge A/B there
    # only after the historical sidewalk-surface gate has already passed, so the
    # artifact for this PR is the human-reviewable new candidate while the logs
    # retain the pre-existing surface metrics.
    if not _save(before, BEFORE_PATH) or not _save(after, AFTER_PATH):
        _fail("sidewalk edge review artifact mirror failed")
        return false
    print("BRUSSELS_SIDEWALK_EDGE_VISUAL_OK: player_eye_height=1.65m fov=67 changed_gt3=%.4f%% changed_gt8=%.4f%% bbox=%dx%d geometry_unchanged=true source_height_claimed=false" % [changed3 * 100.0, changed8 * 100.0, bbox.size.x, bbox.size.y])
    return true

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("production main scene missing")
        return

    var scene := packed.instantiate() as Node3D
    var viewport := SubViewport.new()
    viewport.size = Vector2i(PROBE_WIDTH, PROBE_HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    viewport.add_child(scene)
    _hide_dynamic(scene)

    var runtime := root.get_node_or_null("BrusselsOsmSidewalkSurfaceRuntime")
    if runtime == null:
        _fail("production sidewalk-surface autoload missing")
        return
    for _frame: int in range(180):
        if bool(runtime.call("ready_complete")):
            break
        await process_frame
    if not bool(runtime.call("ready_complete")) or bool(runtime.call("failed")):
        _fail("production sidewalk-surface runtime did not bind cleanly")
        return
    for _frame: int in range(12):
        await process_frame

    var roads_root := scene.get_node_or_null("BrusselsOSM/GeneratedRoads") as Node3D
    if roads_root == null:
        _fail("GeneratedRoads missing")
        return
    var candidates := _candidate_sidewalks(roads_root)
    if candidates.is_empty():
        _fail("no legitimate long generated sidewalk candidates near Bourse")
        return

    var camera := Camera3D.new()
    camera.current = true
    scene.add_child(camera)
    var sidewalk := await _select_rendered_sidewalk(viewport, camera, candidates, runtime)
    if sidewalk == null:
        _fail("no actually rendered Bourse-context sidewalk found after probing top candidates")
        return

    var original_transform := sidewalk.global_transform
    var original_size := sidewalk.size
    _aim_camera(camera, sidewalk)
    viewport.size = Vector2i(WIDTH, HEIGHT)

    runtime.call("set_enhanced_enabled", false)
    for _frame: int in range(5):
        await process_frame
    var before := await _grab(viewport)

    runtime.call("set_enhanced_enabled", true)
    for _frame: int in range(5):
        await process_frame
    var after := await _grab(viewport)
    if before == null or after == null or not _save(before, BEFORE_PATH) or not _save(after, AFTER_PATH):
        _fail("1280x720 production sidewalk A/B capture failed")
        return
    if not sidewalk.global_transform.is_equal_approx(original_transform) or not sidewalk.size.is_equal_approx(original_size):
        _fail("sidewalk geometry changed during material-only A/B")
        return
    if not bool(runtime.call("geometry_unchanged")):
        _fail("runtime geometry invariant failed")
        return

    var changed_3 := _changed_fraction(before, after, 3)
    var changed_8 := _changed_fraction(before, after, 8)
    print("BRUSSELS_OSM_SIDEWALK_SURFACE_VISUAL_METRICS: length=%.2f width=%.2f bourse_distance=%.2f changed_gt3=%.6f changed_gt8=%.6f" % [sidewalk.size.z, sidewalk.size.x, Vector2(sidewalk.global_position.x, sidewalk.global_position.z).distance_to(BOURSE), changed_3, changed_8])
    if changed_3 < MIN_CHANGED_3 or changed_8 < MIN_CHANGED_8:
        _fail("full-frame sidewalk change too weak: gt3=%.4f%% gt8=%.4f%%" % [changed_3 * 100.0, changed_8 * 100.0])
        return
    print("BRUSSELS_OSM_SIDEWALK_SURFACE_VISUAL_OK: player_eye_height=1.65m fov=67 source_position_unchanged=true geometry_unchanged=true changed_gt3=%.4f%% changed_gt8=%.4f%%" % [changed_3 * 100.0, changed_8 * 100.0])

    runtime.call("set_enhanced_enabled", true)
    if not await _run_edge_gate(scene, viewport, camera, roads_root):
        return
    quit(0)
