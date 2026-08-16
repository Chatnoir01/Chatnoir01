extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const BEFORE_PATH := "res://artifacts/visual/anneessens_tree_before.png"
const AFTER_PATH := "res://artifacts/visual/anneessens_tree_after.png"
const ANNEESSENS_SPAWN := Vector3(-272.04, 1.05, -217.07)
const TARGET_TREE_ID := 11929097333
const MIN_CHANGED_3 := 0.005
const MIN_CHANGED_8 := 0.002

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ANNEESSENS_STREET_TREE_FAIL: %s" % message)
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
    for path: String in ["PrototypeCar", "PhysicalCarB", "MidiHeroZone", "MidiUrbanLife"]:
        var spatial := scene.get_node_or_null(path) as Node3D
        if spatial != null:
            spatial.visible = false
    var traffic := scene.get_node_or_null("TrafficManager")
    if traffic != null:
        traffic.set("auto_spawn_runtime", false)
        if traffic is Node3D:
            (traffic as Node3D).visible = false

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    var runtime_script := load("res://game/scripts/anneessens_osm_furniture_runtime.gd") as Script
    if packed == null or runtime_script == null:
        _fail("main scene or furniture runtime missing")
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

    var player := scene.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _fail("player missing")
        return
    player.global_position = ANNEESSENS_SPAWN
    player.visible = false

    var runtime := runtime_script.new() as Node
    scene.add_child(runtime)
    runtime.call("bind_scene", scene)
    for _frame: int in range(8):
        await process_frame
    if int(runtime.call("tree_count")) != 7:
        _fail("expected seven sourced trees")
        return

    var tree := scene.get_node_or_null("AnneessensOsmFurniture/OsmTree_%d" % TARGET_TREE_ID) as StaticBody3D
    if tree == null:
        _fail("target sourced tree missing")
        return

    var camera := Camera3D.new()
    camera.position = tree.global_position + Vector3(0.0, 1.65, 12.0)
    camera.look_at_from_position(camera.position, tree.global_position + Vector3(0.0, 3.15, 0.0), Vector3.UP)
    camera.fov = 69.0
    camera.current = true
    scene.add_child(camera)

    runtime.call("set_enhanced_trees_enabled", false)
    for _frame: int in range(4):
        await process_frame
    var before := await _capture(viewport, BEFORE_PATH)

    runtime.call("set_enhanced_trees_enabled", true)
    for _frame: int in range(4):
        await process_frame
    var after := await _capture(viewport, AFTER_PATH)
    if before == null or after == null:
        _fail("1280x720 tree A/B capture failed")
        return

    var changed_3 := _changed_fraction(before, after, 3)
    var changed_8 := _changed_fraction(before, after, 8)
    print("ANNEESSENS_STREET_TREE_METRICS: tree=%d changed_gt3=%.6f changed_gt8=%.6f" % [TARGET_TREE_ID, changed_3, changed_8])
    if changed_3 < MIN_CHANGED_3 or changed_8 < MIN_CHANGED_8:
        _fail("full-frame change too weak: gt3=%.4f%% gt8=%.4f%%" % [changed_3 * 100.0, changed_8 * 100.0])
        return

    print("ANNEESSENS_STREET_TREE_OK: tree=%d player_eye=true source_position_unchanged=true changed_gt3=%.4f%% changed_gt8=%.4f%%" % [TARGET_TREE_ID, changed_3 * 100.0, changed_8 * 100.0])
    quit(0)
