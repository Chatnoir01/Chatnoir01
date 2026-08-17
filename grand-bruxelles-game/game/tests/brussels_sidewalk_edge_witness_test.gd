extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const PROBE_WIDTH := 320
const PROBE_HEIGHT := 180
const BEFORE_PATH := "res://artifacts/visual/sidewalk_edge_before.png"
const AFTER_PATH := "res://artifacts/visual/sidewalk_edge_after.png"
const BOURSE := Vector2(81.54, -664.58)
const SEARCH_RADIUS_M := 220.0
const MIN_BOURSE_DISTANCE_M := 120.0
const MIN_LENGTH_M := 12.0
const MAX_PROBES := 32
const MIN_PROBE_CHANGED := 0.002
const MIN_CHANGED_3 := 0.0025
const MIN_CHANGED_8 := 0.0010
const MIN_BBOX_WIDTH := 400
const MIN_BBOX_HEIGHT := 100

func _initialize() -> void: call_deferred("_run")
func _fail(message: String) -> void: push_error("BRUSSELS_SIDEWALK_EDGE_VISUAL_FAIL: %s" % message); quit(1)

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

func _candidate_sidewalks(roads_root: Node3D) -> Array[CSGBox3D]:
    var candidates: Array[CSGBox3D] = []
    for child: Node in roads_root.get_children():
        if not child is CSGBox3D: continue
        var sidewalk := child as CSGBox3D
        if not _is_sidewalk(sidewalk) or sidewalk.size.z < MIN_LENGTH_M: continue
        var distance := Vector2(sidewalk.global_position.x, sidewalk.global_position.z).distance_to(BOURSE)
        if distance > SEARCH_RADIUS_M or distance < MIN_BOURSE_DISTANCE_M: continue
        candidates.append(sidewalk)
    candidates.sort_custom(func(a: CSGBox3D, b: CSGBox3D) -> bool: return a.size.z > b.size.z)
    return candidates

func _aim_camera(camera: Camera3D, sidewalk: CSGBox3D) -> void:
    var travel := clampf(sidewalk.size.z * 0.34, 6.0, 15.0)
    var look_distance := clampf(sidewalk.size.z * 0.27, 5.0, 13.0)
    camera.look_at_from_position(sidewalk.global_transform * Vector3(0.0, 1.65, travel), sidewalk.global_transform * Vector3(0.0, 0.02, -look_distance), Vector3.UP)
    camera.fov = 67.0

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
            if max(abs(a.r-b.r), max(abs(a.g-b.g), abs(a.b-b.b))) > limit:
                changed += 1; min_x = mini(min_x,x); min_y = mini(min_y,y); max_x = maxi(max_x,x); max_y = maxi(max_y,y)
    var bbox := Rect2i()
    if changed > 0: bbox = Rect2i(min_x,min_y,max_x-min_x+1,max_y-min_y+1)
    return {"fraction": float(changed)/float(before.get_width()*before.get_height()), "bbox": bbox}

func _select_visible(viewport: SubViewport, camera: Camera3D, candidates: Array[CSGBox3D], runtime: Node) -> CSGBox3D:
    viewport.size = Vector2i(PROBE_WIDTH, PROBE_HEIGHT)
    var count := mini(candidates.size(), MAX_PROBES)
    for index: int in range(count):
        var sidewalk := candidates[index]
        _aim_camera(camera, sidewalk)
        runtime.call("set_enhanced_enabled", false); for _frame: int in range(2): await process_frame
        var before := await _grab(viewport)
        runtime.call("set_enhanced_enabled", true); for _frame: int in range(2): await process_frame
        var after := await _grab(viewport)
        var changed := float(_diff_stats(before, after, 3).get("fraction", -1.0))
        if changed >= MIN_PROBE_CHANGED:
            print("BRUSSELS_SIDEWALK_EDGE_PROBE_OK: index=%d length=%.2f width=%.2f bourse_distance=%.2f visible_fraction=%.5f" % [index, sidewalk.size.z, sidewalk.size.x, Vector2(sidewalk.global_position.x, sidewalk.global_position.z).distance_to(BOURSE), changed])
            return sidewalk
    return null

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null: _fail("production main scene missing"); return
    var viewport := SubViewport.new(); viewport.size = Vector2i(PROBE_WIDTH,PROBE_HEIGHT); viewport.own_world_3d = true; viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
    var scene := packed.instantiate() as Node3D; viewport.add_child(scene); _hide_dynamic(scene)
    var runtime := root.get_node_or_null("BrusselsSidewalkEdgeRuntime")
    if runtime == null: _fail("production sidewalk edge autoload missing"); return
    for _frame: int in range(180):
        if scene.find_child("GeneratedRoads", true, false) != null: break
        await process_frame
    runtime.call("bind_scene", scene)
    for _frame: int in range(8): await process_frame
    if bool(runtime.call("failed")) or not bool(runtime.call("ready_complete")): _fail("runtime did not bind cleanly"); return
    if int(runtime.call("sidewalk_count")) != 430 or int(runtime.call("edge_count")) != 430: _fail("production reuse count changed"); return
    if int(runtime.call("batch_count")) != 1 or int(runtime.call("collision_count")) != 0: _fail("performance-cost contract changed"); return
    if not bool(runtime.call("geometry_unchanged")) or not bool(runtime.call("edge_visual_within_sidewalk_envelope")): _fail("geometry invariant failed"); return
    var roads_root := scene.get_node_or_null("BrusselsOSM/GeneratedRoads") as Node3D
    if roads_root == null: _fail("GeneratedRoads missing"); return
    var candidates := _candidate_sidewalks(roads_root)
    if candidates.is_empty(): _fail("no long non-Bourse-owned sidewalk candidates"); return
    var camera := Camera3D.new(); camera.current = true; scene.add_child(camera)
    var sidewalk := await _select_visible(viewport, camera, candidates, runtime)
    if sidewalk == null: _fail("no rendered non-Bourse-owned sidewalk edge found"); return
    var original_transform := sidewalk.global_transform; var original_size := sidewalk.size
    _aim_camera(camera, sidewalk); viewport.size = Vector2i(WIDTH,HEIGHT)
    runtime.call("set_enhanced_enabled", false); for _frame: int in range(5): await process_frame
    var before := await _grab(viewport)
    runtime.call("set_enhanced_enabled", true); for _frame: int in range(5): await process_frame
    var after := await _grab(viewport)
    if before == null or after == null or not _save(before,BEFORE_PATH) or not _save(after,AFTER_PATH): _fail("1280x720 edge A/B capture failed"); return
    if not sidewalk.global_transform.is_equal_approx(original_transform) or not sidewalk.size.is_equal_approx(original_size) or not bool(runtime.call("geometry_unchanged")): _fail("sidewalk geometry changed during A/B"); return
    var stats3 := _diff_stats(before,after,3); var stats8 := _diff_stats(before,after,8)
    var changed3 := float(stats3.get("fraction",-1.0)); var changed8 := float(stats8.get("fraction",-1.0)); var bbox := stats3.get("bbox",Rect2i()) as Rect2i
    print("BRUSSELS_SIDEWALK_EDGE_VISUAL_METRICS: length=%.2f width=%.2f bourse_distance=%.2f changed_gt3=%.6f changed_gt8=%.6f bbox=%dx%d sidewalks=430 edges=430 batches=1 collisions=0" % [sidewalk.size.z, sidewalk.size.x, Vector2(sidewalk.global_position.x,sidewalk.global_position.z).distance_to(BOURSE), changed3, changed8, bbox.size.x, bbox.size.y])
    if changed3 < MIN_CHANGED_3 or changed8 < MIN_CHANGED_8: _fail("screen impact below locked threshold: gt3=%.4f%% gt8=%.4f%%" % [changed3*100.0,changed8*100.0]); return
    if bbox.size.x < MIN_BBOX_WIDTH or bbox.size.y < MIN_BBOX_HEIGHT: _fail("change bbox below locked threshold: %dx%d" % [bbox.size.x,bbox.size.y]); return
    print("BRUSSELS_SIDEWALK_EDGE_VISUAL_OK: player_eye_height=1.65m fov=67 changed_gt3=%.4f%% changed_gt8=%.4f%% bbox=%dx%d geometry_unchanged=true" % [changed3*100.0,changed8*100.0,bbox.size.x,bbox.size.y])
    quit(0)