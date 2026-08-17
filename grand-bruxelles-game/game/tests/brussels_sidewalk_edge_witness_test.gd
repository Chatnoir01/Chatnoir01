extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const BEFORE_PATH := "res://artifacts/visual/sidewalk_edge_before.png"
const AFTER_PATH := "res://artifacts/visual/sidewalk_edge_after.png"
const MIN_CHANGED_3 := 0.0025
const MIN_CHANGED_8 := 0.0010
const MIN_BBOX_WIDTH := 400
const MIN_BBOX_HEIGHT := 100
const CLUSTER_RADIUS := 55.0
const CAMERA_DISTANCE := 15.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_SIDEWALK_EDGE_VISUAL_FAIL: %s" % message)
    quit(1)

func _hide_dynamic(scene: Node) -> void:
    for path: String in ["LocationLabel", "MissionLabel", "PrototypeLabel", "MiniMap", "MobileControls", "WalletHUD"]:
        var item := scene.get_node_or_null(path) as CanvasItem
        if item != null: item.visible = false
    for path: String in ["PrototypeCar", "PhysicalCarB", "MidiUrbanLife"]:
        var spatial := scene.get_node_or_null(path) as Node3D
        if spatial != null: spatial.visible = false
    var player := scene.get_node_or_null("Player") as Node3D
    if player != null: player.visible = false
    var traffic := scene.get_node_or_null("TrafficManager")
    if traffic != null:
        traffic.set("auto_spawn_runtime", false)
        if traffic is Node3D: (traffic as Node3D).visible = false

func _is_sidewalk(box: CSGBox3D) -> bool:
    if str(box.name).begins_with("Road_"): return false
    if absf(box.size.y - 0.12) > 0.005: return false
    return absf(box.size.x - 1.85) <= 0.02 or absf(box.size.x - 2.55) <= 0.02

func _sidewalk_positions(scene: Node3D) -> Array:
    var result: Array = []
    var roads := scene.find_child("GeneratedRoads", true, false) as Node3D
    if roads == null: return result
    for child: Node in roads.get_children():
        if child is CSGBox3D and _is_sidewalk(child as CSGBox3D):
            result.append((child as CSGBox3D).global_position)
    return result

func _densest_center(positions: Array) -> Vector3:
    var best := Vector3.ZERO
    var best_count := -1
    for raw_a: Variant in positions:
        var a: Vector3 = raw_a as Vector3
        var count := 0
        var sum := Vector3.ZERO
        for raw_b: Variant in positions:
            var b: Vector3 = raw_b as Vector3
            var dx := a.x - b.x; var dz := a.z - b.z
            if dx * dx + dz * dz <= CLUSTER_RADIUS * CLUSTER_RADIUS:
                count += 1; sum += b
        if count > best_count:
            best_count = count; best = sum / float(maxi(count, 1))
    print("BRUSSELS_SIDEWALK_EDGE_CLUSTER: nearby=%d center=(%.3f,%.3f)" % [best_count, best.x, best.z])
    return best

func _camera_candidates(center: Vector3) -> Array:
    var target := center + Vector3(0.0, 0.10, 0.0)
    return [
        [center + Vector3(CAMERA_DISTANCE, 1.65, 0.0), target],
        [center + Vector3(-CAMERA_DISTANCE, 1.65, 0.0), target],
        [center + Vector3(0.0, 1.65, CAMERA_DISTANCE), target],
        [center + Vector3(0.0, 1.65, -CAMERA_DISTANCE), target],
        [center + Vector3(10.5, 1.65, 10.5), target],
        [center + Vector3(-10.5, 1.65, -10.5), target]
    ]

func _grab(viewport: SubViewport) -> Image:
    RenderingServer.force_draw(); await process_frame
    var image := viewport.get_texture().get_image()
    return image if image != null and not image.is_empty() else null

func _save(image: Image, path: String) -> bool:
    if image == null or image.is_empty(): return false
    var absolute := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    return image.save_png(absolute) == OK

func _diff_stats(before: Image, after: Image, threshold: int) -> Dictionary:
    if before == null or after == null or before.get_size() != after.get_size(): return {"fraction": -1.0, "bbox": Rect2i()}
    var limit := float(threshold) / 255.0
    var changed := 0; var min_x := before.get_width(); var min_y := before.get_height(); var max_x := -1; var max_y := -1
    for y: int in range(before.get_height()):
        for x: int in range(before.get_width()):
            var a := before.get_pixel(x, y); var b := after.get_pixel(x, y)
            if max(abs(a.r - b.r), max(abs(a.g - b.g), abs(a.b - b.b))) > limit:
                changed += 1; min_x = mini(min_x, x); min_y = mini(min_y, y); max_x = maxi(max_x, x); max_y = maxi(max_y, y)
    var bbox := Rect2i()
    if changed > 0: bbox = Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
    return {"fraction": float(changed) / float(before.get_width() * before.get_height()), "bbox": bbox}

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null: _fail("production main scene missing"); return
    var viewport := SubViewport.new(); viewport.size = Vector2i(WIDTH, HEIGHT); viewport.own_world_3d = true; viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
    var scene := packed.instantiate() as Node3D; viewport.add_child(scene); _hide_dynamic(scene)
    for _frame: int in range(18): await process_frame
    var runtime := root.get_node_or_null("BrusselsSidewalkEdgeRuntime")
    if runtime == null: _fail("production sidewalk edge autoload missing"); return
    runtime.call("bind_scene", scene)
    for _frame: int in range(8): await process_frame
    if bool(runtime.call("failed")) or not bool(runtime.call("ready_complete")): _fail("runtime did not bind cleanly"); return
    if int(runtime.call("sidewalk_count")) <= 0 or int(runtime.call("edge_count")) != int(runtime.call("sidewalk_count")) * 2: _fail("runtime reuse counts invalid"); return
    if int(runtime.call("batch_count")) != 1 or int(runtime.call("collision_count")) != 0: _fail("performance-cost contract changed"); return
    if not bool(runtime.call("geometry_unchanged")) or not bool(runtime.call("edge_visual_within_sidewalk_envelope")): _fail("geometry invariant failed"); return
    var positions := _sidewalk_positions(scene)
    if positions.is_empty(): _fail("no production sidewalks available for witness"); return
    var center := _densest_center(positions)
    var camera := Camera3D.new(); camera.current = true; camera.fov = 67.0; scene.add_child(camera)
    var best_before: Image = null; var best_after: Image = null; var best_changed := -1.0; var best_index := -1
    var candidates := _camera_candidates(center)
    for index: int in range(candidates.size()):
        var candidate := candidates[index] as Array
        camera.look_at_from_position(candidate[0] as Vector3, candidate[1] as Vector3, Vector3.UP)
        runtime.call("set_enhanced_enabled", false); for _frame: int in range(3): await process_frame
        var before := await _grab(viewport)
        runtime.call("set_enhanced_enabled", true); for _frame: int in range(3): await process_frame
        var after := await _grab(viewport)
        var fraction := float(_diff_stats(before, after, 3).get("fraction", -1.0))
        if fraction > best_changed: best_changed = fraction; best_before = before; best_after = after; best_index = index
    if best_before == null or best_after == null or best_index < 0: _fail("failed to obtain deterministic player A/B"); return
    if not _save(best_before, BEFORE_PATH) or not _save(best_after, AFTER_PATH): _fail("failed to save A/B evidence"); return
    var stats3 := _diff_stats(best_before, best_after, 3); var stats8 := _diff_stats(best_before, best_after, 8)
    var changed3 := float(stats3.get("fraction", -1.0)); var changed8 := float(stats8.get("fraction", -1.0)); var bbox := stats3.get("bbox", Rect2i()) as Rect2i
    print("BRUSSELS_SIDEWALK_EDGE_VISUAL_METRICS: camera=%d changed_gt3=%.6f changed_gt8=%.6f bbox=%dx%d sidewalks=%d edges=%d batches=1 collisions=0" % [best_index, changed3, changed8, bbox.size.x, bbox.size.y, int(runtime.call("sidewalk_count")), int(runtime.call("edge_count"))])
    if changed3 < MIN_CHANGED_3 or changed8 < MIN_CHANGED_8: _fail("screen impact below locked threshold: gt3=%.4f%% gt8=%.4f%%" % [changed3 * 100.0, changed8 * 100.0]); return
    if bbox.size.x < MIN_BBOX_WIDTH or bbox.size.y < MIN_BBOX_HEIGHT: _fail("change bbox below locked threshold: %dx%d" % [bbox.size.x, bbox.size.y]); return
    if not bool(runtime.call("geometry_unchanged")): _fail("sidewalk geometry changed during witness"); return
    print("BRUSSELS_SIDEWALK_EDGE_VISUAL_OK: player_eye_height=1.65m fov=67 camera=%d changed_gt3=%.4f%% changed_gt8=%.4f%% bbox=%dx%d geometry_unchanged=true" % [best_index, changed3 * 100.0, changed8 * 100.0, bbox.size.x, bbox.size.y])
    quit(0)
