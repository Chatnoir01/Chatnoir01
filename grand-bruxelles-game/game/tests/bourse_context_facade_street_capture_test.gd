extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const WARMUP_FRAMES := 75
const BOURSE_ANCHOR := Vector2(81.54, -664.58)
const OUTPUT_PATH := "res://artifacts/qa/bourse_context_facade_street.png"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_CONTEXT_FACADE_CAPTURE_FAIL: %s" % message)
    quit(1)

func _hide_generated_labels(node: Node) -> void:
    if node is Label3D:
        (node as Label3D).visible = false
    for child: Node in node.get_children():
        _hide_generated_labels(child)

func _hide_capture_noise(scene: Node) -> void:
    for node_path: String in ["LocationLabel", "MissionLabel", "PrototypeLabel", "MiniMap", "MobileControls", "WalletHUD"]:
        var item := scene.get_node_or_null(node_path) as CanvasItem
        if item != null:
            item.visible = false
    for node_path: String in ["Player", "PrototypeCar", "MidiHeroZone"]:
        var spatial := scene.get_node_or_null(node_path) as Node3D
        if spatial != null:
            spatial.visible = false
    _hide_generated_labels(scene)

func _footprint_centroid(footprint: Array) -> Vector2:
    var total := Vector2.ZERO
    for raw: Variant in footprint:
        total += Vector2(float(raw[0]), float(raw[1]))
    return total / maxf(1.0, float(footprint.size()))

func _select_context_edge(city_builder: Node) -> Dictionary:
    var data_path := str(city_builder.get("data_path"))
    if data_path.is_empty() or not FileAccess.file_exists(data_path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    var replacements: Dictionary = {}
    if city_builder.has_method("_validated_hero_replacements"):
        replacements = city_builder.call("_validated_hero_replacements") as Dictionary

    var best: Dictionary = {}
    var best_score := INF
    for raw_building: Variant in (parsed as Dictionary).get("buildings", []):
        if typeof(raw_building) != TYPE_DICTIONARY:
            continue
        var building := raw_building as Dictionary
        if replacements.has(int(building.get("osm_id", 0))):
            continue
        var height := float(building.get("height", 0.0))
        if height < 9.0:
            continue
        var footprint: Array = building.get("footprint", [])
        if footprint.size() < 3:
            continue
        var centroid := _footprint_centroid(footprint)
        if centroid.distance_to(BOURSE_ANCHOR) > 155.0:
            continue
        for edge_index: int in range(footprint.size()):
            var raw_a: Variant = footprint[edge_index]
            var raw_b: Variant = footprint[(edge_index + 1) % footprint.size()]
            var a := Vector2(float(raw_a[0]), float(raw_a[1]))
            var b := Vector2(float(raw_b[0]), float(raw_b[1]))
            var length := a.distance_to(b)
            if length < 10.0 or length > 26.0:
                continue
            var midpoint := (a + b) * 0.5
            var distance := midpoint.distance_to(BOURSE_ANCHOR)
            if distance < 28.0 or distance > 145.0:
                continue
            var score := distance + absf(length - 16.0) * 1.5
            if score < best_score:
                best_score = score
                best = {
                    "osm_id": int(building.get("osm_id", 0)),
                    "height": height,
                    "centroid": centroid,
                    "midpoint": midpoint,
                    "edge_length": length,
                }
    return best

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    if scene == null:
        _fail("main scene did not instantiate")
        return

    var viewport := SubViewport.new()
    viewport.name = "BourseContextFacadeStreetViewport"
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)

    var traffic_manager := scene.get_node_or_null("TrafficManager")
    if traffic_manager != null:
        traffic_manager.set("auto_spawn_runtime", false)
    _hide_capture_noise(scene)
    viewport.add_child(scene)

    for _frame: int in range(12):
        await process_frame
    var city_builder := scene.get_node_or_null("BrusselsOSM")
    if city_builder == null:
        _fail("production city builder missing")
        return
    var articulation := city_builder.get_node_or_null("ContextFacadeArticulation")
    if articulation == null:
        _fail("production context facade articulation missing")
        return

    var selected := _select_context_edge(city_builder)
    if selected.is_empty():
        _fail("could not select a source-footprint context facade edge")
        return

    var centroid: Vector2 = selected["centroid"]
    var midpoint: Vector2 = selected["midpoint"]
    var outward := (midpoint - centroid).normalized()
    if outward.length_squared() < 0.5:
        _fail("selected facade has invalid outward direction")
        return
    var camera_ground := midpoint + outward * 12.0
    var camera_position := Vector3(camera_ground.x, 1.72, camera_ground.y)
    var target := Vector3(midpoint.x, minf(5.4, float(selected["height"]) * 0.48), midpoint.y)

    var existing_camera := scene.get_viewport().get_camera_3d()
    if existing_camera != null:
        existing_camera.current = false
    var camera := Camera3D.new()
    camera.name = "BourseContextFacadeStreetCamera"
    camera.position = camera_position
    camera.fov = 55.0
    camera.current = true
    scene.add_child(camera)
    camera.look_at(target, Vector3.UP)

    print(
        "BOURSE_CONTEXT_FACADE_CAMERA: osm=%d edge=%.2fm midpoint=%s camera=%s target=%s" %
        [int(selected["osm_id"]), float(selected["edge_length"]), str(midpoint), str(camera_position), str(target)]
    )

    for _frame: int in range(WARMUP_FRAMES):
        await process_frame
    _hide_capture_noise(scene)
    RenderingServer.force_draw()
    await process_frame

    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty():
        _fail("captured viewport is empty")
        return
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        _fail("unexpected capture dimensions")
        return

    var absolute_output := ProjectSettings.globalize_path(OUTPUT_PATH)
    var dir_error := DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
    if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
        _fail("could not create artifact directory")
        return
    var save_error := image.save_png(absolute_output)
    if save_error != OK:
        _fail("could not save capture: %s" % error_string(save_error))
        return

    print("BOURSE_CONTEXT_FACADE_CAPTURE_OK: %s" % OUTPUT_PATH)
    viewport.queue_free()
    quit(0)
