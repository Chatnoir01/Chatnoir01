extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const ANNEESSENS_SPAWN := Vector3(-272.04, 1.05, -217.07)
const ANNEESSENS := Vector2(-272.04, -217.07)
const WAIT_FRAMES := 180

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ANNEESSENS_PLAYER_VIEW_CAPTURE_FAIL: %s" % message)
    quit(1)

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

func _visible_furniture_witness_count(scene: Node3D, camera: Camera3D) -> int:
    var furniture_root := scene.get_node_or_null("AnneessensOsmFurniture") as Node3D
    if furniture_root == null or not furniture_root.is_inside_tree() or not furniture_root.visible:
        return 0
    var visible_count := 0
    for child: Node in furniture_root.get_children():
        if not child is Node3D or not child.is_in_group("osm_environment_furniture"):
            continue
        var spatial := child as Node3D
        # Use a representative crown-height point rather than the ground pivot so
        # the proof matches what can actually contribute pixels to the player frame.
        if camera.is_position_in_frustum(spatial.global_position + Vector3(0.0, 1.5, 0.0)):
            visible_count += 1
    return visible_count

func _run() -> void:
    var output_path := OS.get_environment("ANNEESSENS_CAPTURE_PATH")
    if output_path.is_empty():
        output_path = "res://artifacts/visual/anneessens_player_view.png"

    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene missing")
        return
    var scene := packed.instantiate() as Node3D
    if scene == null:
        _fail("main scene did not instantiate")
        return

    # Player-view evidence must exercise the production authority topology, not a
    # preview/tool SubViewport. Keep the deterministic 1280x720 render target,
    # but mount the canonical Main directly under SceneTree.root and mark it as
    # current_scene exactly as a normal project launch does.
    root.size = Vector2i(WIDTH, HEIGHT)
    root.add_child(scene)
    current_scene = scene
    if scene.get_parent() != root or current_scene != scene:
        _fail("canonical Main did not acquire authoritative root/current_scene topology")
        return
    _hide_dynamic(scene)

    # Exercise the production activation authority with the existing canonical
    # Main/Player. Visibility remains disabled for deterministic evidence, but the
    # authoritative node identity and coordinates are real and must drive runtime
    # activation before the capture wait begins.
    var player := scene.get_node_or_null("Player") as Node3D
    if player == null or not player.is_inside_tree():
        _fail("canonical Main/Player unavailable for Anneessens activation witness")
        return
    player.global_position = ANNEESSENS_SPAWN

    for _frame: int in range(WAIT_FRAMES):
        await process_frame

    var ground := scene.get_node_or_null("Ground") as CSGBox3D
    if ground == null or not ground.use_collision:
        _fail("canonical Ground collision unavailable")
        return
    var road := _nearest_road(scene)
    if road == null:
        _fail("no OSM road near Anneessens")
        return
    var road_distance := Vector2(road.global_position.x, road.global_position.z).distance_to(ANNEESSENS)
    if road_distance > 130.0:
        _fail("nearest OSM road too far: %.3f m" % road_distance)
        return

    var camera := Camera3D.new()
    camera.position = ANNEESSENS_SPAWN + Vector3(0.0, 1.1, 0.0)
    camera.look_at_from_position(camera.position, road.global_position + Vector3(0.0, 0.15, 0.0), Vector3.UP)
    camera.fov = 69.0
    camera.current = true
    scene.add_child(camera)

    for _frame: int in range(12):
        await process_frame

    # A numerically valid screenshot is not visual evidence for this change unless
    # source-owned Anneessens furniture can actually contribute pixels to the fixed
    # player frame. Fail closed instead of accepting an occluded/blank A/B.
    var visible_furniture_witnesses := _visible_furniture_witness_count(scene, camera)
    if visible_furniture_witnesses <= 0:
        _fail("fixed player frame contains no in-frustum Anneessens OSM furniture witness")
        return

    RenderingServer.force_draw()
    await process_frame
    var image := root.get_texture().get_image()
    if image == null or image.is_empty() or image.get_size() != Vector2i(WIDTH, HEIGHT):
        _fail("1280x720 root player-view capture unavailable")
        return

    var absolute := ProjectSettings.globalize_path(output_path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    if image.save_png(absolute) != OK:
        _fail("could not save capture")
        return

    print("ANNEESSENS_PLAYER_VIEW_CAPTURE_OK: output=%s size=%dx%d spawn=(%.3f,%.3f,%.3f) road=%s road_pos=(%.3f,%.3f,%.3f) road_distance=%.3f fov=%.1f furniture_witnesses=%d authority=root_current_scene camera_changed=false source_geometry_changed=false threshold_changed=false visual_acceptance=false jouable_authorized=false" % [output_path, WIDTH, HEIGHT, camera.position.x, camera.position.y, camera.position.z, road.name, road.global_position.x, road.global_position.y, road.global_position.z, road_distance, camera.fov, visible_furniture_witnesses])
    quit(0)
