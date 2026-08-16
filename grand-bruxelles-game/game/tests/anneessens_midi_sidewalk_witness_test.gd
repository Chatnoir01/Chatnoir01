extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const BEFORE_PATH := "res://artifacts/visual/anneessens_sidewalk_before.png"
const AFTER_PATH := "res://artifacts/visual/anneessens_sidewalk_after.png"
const ANNEESSENS_SPAWN := Vector3(-272.04, 1.05, -217.07)
const ANNEESSENS := Vector2(-272.04, -217.07)
const MIN_CHANGED_3 := 0.008
const MIN_CHANGED_8 := 0.003
const MIN_SIDEWALKS := 4

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ANNEESSENS_MIDI_SIDEWALK_FAIL: %s" % message)
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

func _nearest_road(scene: Node3D) -> CSGBox3D:
    var roads := scene.get_node_or_null("BrusselsOSM/GeneratedRoads")
    if roads == null:
        return null
    var best: CSGBox3D = null
    var best_distance := INF
    for child: Node in roads.get_children():
        if child is CSGBox3D and child.name.begins_with("Road_"):
            var road := child as CSGBox3D
            var distance := Vector2(road.global_position.x, road.global_position.z).distance_to(ANNEESSENS)
            if distance < best_distance:
                best_distance = distance
                best = road
    return best

func _run() -> void:
    var runtime_script := load("res://game/scripts/anneessens_midi_sidewalk_runtime.gd") as Script
    if runtime_script == null:
        _fail("Anneessens Midi sidewalk runtime missing")
        return
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

    for _frame: int in range(90):
        await process_frame

    var ground := scene.get_node_or_null("Ground") as CSGBox3D
    if ground == null or not ground.use_collision:
        _fail("Anneessens visit has no stable ground collision")
        return
    if ANNEESSENS_SPAWN.y < ground.position.y + ground.size.y * 0.5 + 0.5:
        _fail("Anneessens spawn is not safely above ground")
        return

    var road := _nearest_road(scene)
    if road == null or Vector2(road.global_position.x, road.global_position.z).distance_to(ANNEESSENS) > 130.0:
        _fail("no OSM road available near Anneessens spawn")
        return

    var runtime := runtime_script.new()
    scene.add_child(runtime)
    runtime.call("bind_scene", scene)
    await process_frame
    var sidewalk_count := int(runtime.call("diagnostic_sidewalk_count"))
    var collision_count := int(runtime.call("diagnostic_collision_count"))
    if sidewalk_count < MIN_SIDEWALKS:
        _fail("too few Anneessens sidewalks: %d" % sidewalk_count)
        return
    if collision_count != sidewalk_count:
        _fail("every Anneessens sidewalk must be collidable")
        return

    var camera := Camera3D.new()
    camera.position = ANNEESSENS_SPAWN + Vector3(0.0, 1.1, 0.0)
    camera.look_at_from_position(camera.position, road.global_position + Vector3(0.0, 0.15, 0.0), Vector3.UP)
    camera.fov = 69.0
    camera.current = true
    scene.add_child(camera)

    runtime.call("set_sidewalks_enabled", false)
    for _frame: int in range(8):
        await process_frame
    var before := await _capture(viewport, BEFORE_PATH)
    runtime.call("set_sidewalks_enabled", true)
    for _frame: int in range(8):
        await process_frame
    var after := await _capture(viewport, AFTER_PATH)
    if before == null or after == null:
        _fail("1280x720 A/B capture failed")
        return

    var changed_3 := _changed_fraction(before, after, 3)
    var changed_8 := _changed_fraction(before, after, 8)
    print("ANNEESSENS_MIDI_SIDEWALK_METRICS: sidewalks=%d collisions=%d changed_gt3=%.6f changed_gt8=%.6f" % [sidewalk_count, collision_count, changed_3, changed_8])
    if changed_3 < MIN_CHANGED_3 or changed_8 < MIN_CHANGED_8:
        _fail("3s visual gate too weak: gt3=%.4f%% gt8=%.4f%%" % [changed_3 * 100.0, changed_8 * 100.0])
        return
    print("ANNEESSENS_MIDI_SIDEWALK_OK: spawn=stable ground=collidable sidewalks=%d changed_gt3=%.4f%% changed_gt8=%.4f%%" % [sidewalk_count, changed_3 * 100.0, changed_8 * 100.0])
    quit(0)
