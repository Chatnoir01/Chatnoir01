extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const BEFORE_PATH := "res://artifacts/visual/osm_sidewalk_surface_before.png"
const AFTER_PATH := "res://artifacts/visual/osm_sidewalk_surface_after.png"
const MIDI := Vector2(-668.5, 627.84)
const MIN_RADIUS_M := 250.0
const SEARCH_RADIUS_M := 300.0
const MIN_CHANGED_3 := 0.06
const MIN_CHANGED_8 := 0.03

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_SIDEWALK_SURFACE_VISUAL_FAIL: %s" % message)
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

func _is_sidewalk(box: CSGBox3D) -> bool:
    if str(box.name).begins_with("Road_"):
        return false
    if absf(box.size.y - 0.12) > 0.005:
        return false
    return absf(box.size.x - 1.85) <= 0.02 or absf(box.size.x - 2.55) <= 0.02

func _select_midi_sidewalk(roads_root: Node3D) -> CSGBox3D:
    var best: CSGBox3D = null
    var best_length := 0.0
    for child: Node in roads_root.get_children():
        if not child is CSGBox3D:
            continue
        var sidewalk := child as CSGBox3D
        if not _is_sidewalk(sidewalk):
            continue
        if not sidewalk.visible or not sidewalk.is_visible_in_tree():
            continue
        var midpoint := Vector2(sidewalk.global_position.x, sidewalk.global_position.z)
        var distance := midpoint.distance_to(MIDI)
        if distance < MIN_RADIUS_M or distance > SEARCH_RADIUS_M:
            continue
        if sidewalk.size.z < 14.0:
            continue
        if sidewalk.size.z > best_length:
            best = sidewalk
            best_length = sidewalk.size.z
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
    var sidewalk := _select_midi_sidewalk(roads_root)
    if sidewalk == null:
        _fail("no visible long generated sidewalk found in outer Midi detail ring")
        return

    var original_transform := sidewalk.global_transform
    var original_size := sidewalk.size
    var travel := clampf(sidewalk.size.z * 0.34, 6.0, 15.0)
    var look_distance := clampf(sidewalk.size.z * 0.27, 5.0, 13.0)
    var camera := Camera3D.new()
    camera.position = sidewalk.global_transform * Vector3(0.0, 1.65, travel)
    var target := sidewalk.global_transform * Vector3(0.0, 0.02, -look_distance)
    camera.look_at_from_position(camera.position, target, Vector3.UP)
    camera.fov = 67.0
    camera.current = true
    scene.add_child(camera)

    runtime.call("set_enhanced_enabled", false)
    for _frame: int in range(5):
        await process_frame
    var before := await _capture(viewport, BEFORE_PATH)

    runtime.call("set_enhanced_enabled", true)
    for _frame: int in range(5):
        await process_frame
    var after := await _capture(viewport, AFTER_PATH)
    if before == null or after == null:
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
    print("BRUSSELS_OSM_SIDEWALK_SURFACE_VISUAL_METRICS: sidewalk=%s length=%.2f width=%.2f midi_distance=%.2f changed_gt3=%.6f changed_gt8=%.6f" % [sidewalk.name, sidewalk.size.z, sidewalk.size.x, Vector2(sidewalk.global_position.x, sidewalk.global_position.z).distance_to(MIDI), changed_3, changed_8])
    if changed_3 < MIN_CHANGED_3 or changed_8 < MIN_CHANGED_8:
        _fail("full-frame sidewalk change too weak: gt3=%.4f%% gt8=%.4f%%" % [changed_3 * 100.0, changed_8 * 100.0])
        return

    print("BRUSSELS_OSM_SIDEWALK_SURFACE_VISUAL_OK: player_eye_height=1.65m fov=67 source_position_unchanged=true geometry_unchanged=true changed_gt3=%.4f%% changed_gt8=%.4f%%" % [changed_3 * 100.0, changed_8 * 100.0])
    quit(0)
