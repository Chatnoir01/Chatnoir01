extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const BEFORE_PATH := "res://artifacts/visual/osm_marking_truth_before.png"
const AFTER_PATH := "res://artifacts/visual/osm_marking_truth_after.png"
const MIDI := Vector2(-668.5, 627.84)
const SEARCH_RADIUS_M := 125.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_MARKING_TRUTH_VISUAL_FAIL: %s" % message)
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

func _eligible_markings(roads_root: Node3D) -> Array[CSGBox3D]:
    var found: Array[CSGBox3D] = []
    for child: Node in roads_root.get_children():
        if not child is CSGBox3D:
            continue
        var dash := child as CSGBox3D
        if not dash.has_meta("marking_truth_family"):
            continue
        var xz := Vector2(dash.global_position.x, dash.global_position.z)
        if xz.distance_to(MIDI) <= SEARCH_RADIUS_M:
            found.append(dash)
    return found

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

    var runtime := root.get_node_or_null("BrusselsOsmMarkingTruthRuntime")
    if runtime == null:
        _fail("marking truth runtime missing")
        return
    for _frame: int in range(300):
        if bool(runtime.call("ready_complete")):
            break
        await process_frame
    if not bool(runtime.call("ready_complete")) or bool(runtime.call("failed")):
        _fail("marking truth runtime did not bind cleanly")
        return

    var roads_root := scene.get_node_or_null("BrusselsOSM/GeneratedRoads") as Node3D
    if roads_root == null:
        _fail("GeneratedRoads missing in production scene")
        return
    var markings := _eligible_markings(roads_root)
    if markings.size() < 3:
        _fail("not enough legitimate generic markings near Midi")
        return

    var centroid := Vector2.ZERO
    var original_geometry: Dictionary = {}
    for dash: CSGBox3D in markings:
        centroid += Vector2(dash.global_position.x, dash.global_position.z)
        original_geometry[dash.get_instance_id()] = {"transform": dash.global_transform, "size": dash.size}
    centroid /= float(markings.size())

    var target_direction := (centroid - MIDI).normalized()
    if target_direction.length_squared() < 0.5:
        target_direction = Vector2(0.0, -1.0)
    var target := MIDI + target_direction * 42.0
    var camera := Camera3D.new()
    camera.position = Vector3(MIDI.x, 1.65, MIDI.y)
    camera.look_at_from_position(camera.position, Vector3(target.x, 0.08, target.y), Vector3.UP)
    camera.fov = 69.0
    camera.current = true
    scene.add_child(camera)

    runtime.call("set_enhanced_enabled", false)
    for _frame: int in range(10):
        await process_frame
    var before := await _capture(viewport, BEFORE_PATH)

    runtime.call("set_enhanced_enabled", true)
    for _frame: int in range(10):
        await process_frame
    var after := await _capture(viewport, AFTER_PATH)
    if before == null or after == null:
        _fail("1280x720 current-vs-candidate capture failed")
        return

    for dash: CSGBox3D in markings:
        var snapshot: Dictionary = original_geometry[dash.get_instance_id()]
        if not dash.global_transform.is_equal_approx(snapshot["transform"]) or not dash.size.is_equal_approx(snapshot["size"]):
            _fail("generic marking geometry changed during visibility-only A/B")
            return
    if not bool(runtime.call("geometry_unchanged")):
        _fail("runtime geometry invariant failed")
        return

    print("BRUSSELS_OSM_MARKING_TRUTH_VISUAL_CAPTURED: anchor=midi nearby_marks=%d total_unsupported_marks=%d eye=1.65m fov=69 baseline=legacy_class_inferred_dashes candidate=unsupported_marks_hidden geometry_unchanged=true" % [markings.size(), int(runtime.call("affected_marking_count"))])
    quit(0)
