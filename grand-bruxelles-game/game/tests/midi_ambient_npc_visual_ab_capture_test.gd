extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const WARMUP_FRAMES := 100
const OUTPUT_DIR := "res://artifacts/qa/midi_ambient_npc_visual_ab"
const BEFORE_PATH := OUTPUT_DIR + "/before.png"
const AFTER_PATH := OUTPUT_DIR + "/after.png"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_AMBIENT_NPC_AB_FAIL: %s" % message)
    quit(1)

func _hide_qa_noise(scene: Node) -> void:
    for node_path: String in ["PrototypeLabel", "ABLabel"]:
        var item := scene.get_node_or_null(node_path) as CanvasItem
        if item != null:
            item.visible = false

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

func _metrics(before: Image, after: Image) -> Dictionary:
    if before == null or after == null or before.get_size() != after.get_size():
        return {}
    var changed_4 := 0
    var changed_12 := 0
    var min_x := WIDTH
    var min_y := HEIGHT
    var max_x := -1
    var max_y := -1
    var t4 := 4.0 / 255.0
    var t12 := 12.0 / 255.0
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var d := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
            if d > t4:
                changed_4 += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
            if d > t12:
                changed_12 += 1
    var total := float(WIDTH * HEIGHT)
    return {
        "changed_4_fraction": float(changed_4) / total,
        "changed_12_fraction": float(changed_12) / total,
        "bbox_width": 0 if max_x < min_x else max_x - min_x + 1,
        "bbox_height": 0 if max_y < min_y else max_y - min_y + 1,
    }

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
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)

    var traffic_manager := scene.get_node_or_null("TrafficManager")
    if traffic_manager != null:
        traffic_manager.set("auto_spawn_runtime", false)
    _hide_qa_noise(scene)
    viewport.add_child(scene)

    for _frame: int in range(WARMUP_FRAMES):
        await process_frame
    _hide_qa_noise(scene)

    var runtime := root.get_node_or_null("MidiAmbientNpcVisualRuntime")
    if runtime == null or not runtime.has_method("bridge_scene") or not runtime.has_method("set_profiled_visuals_enabled"):
        _fail("production visual bridge singleton missing")
        return
    var bridge_result: Dictionary = runtime.call("bridge_scene", scene)
    if int(bridge_result.get("bridged", 0)) + int(bridge_result.get("already", 0)) != 20:
        _fail("production visual bridge did not cover all 20 ambient pedestrians")
        return

    var camera := viewport.get_camera_3d()
    if camera == null:
        _fail("normal gameplay camera missing")
        return

    scene.process_mode = Node.PROCESS_MODE_DISABLED
    runtime.call("set_profiled_visuals_enabled", scene, false)
    await process_frame
    var before := await _capture(viewport, BEFORE_PATH)
    if before == null:
        _fail("could not capture legacy BEFORE")
        return

    runtime.call("set_profiled_visuals_enabled", scene, true)
    await process_frame
    var after := await _capture(viewport, AFTER_PATH)
    if after == null:
        _fail("could not capture production AFTER")
        return

    var metrics := _metrics(before, after)
    if metrics.is_empty():
        _fail("could not compare A/B")
        return
    var changed_4 := float(metrics["changed_4_fraction"])
    var changed_12 := float(metrics["changed_12_fraction"])
    var bbox_width := int(metrics["bbox_width"])
    var bbox_height := int(metrics["bbox_height"])
    print("MIDI_AMBIENT_NPC_AB_METRICS: gt4=%.4f%% gt12=%.4f%% bbox=%dx%d camera=%s" % [changed_4 * 100.0, changed_12 * 100.0, bbox_width, bbox_height, str(camera.global_position)])

    if changed_4 < 0.0015:
        _fail("normal player frame change too small: %.4f%%" % (changed_4 * 100.0))
        return
    if changed_12 < 0.0008:
        _fail("strong normal player frame change too small: %.4f%%" % (changed_12 * 100.0))
        return
    if bbox_width < 260 or bbox_height < 120:
        _fail("crowd improvement too localized in frame: bbox=%dx%d" % [bbox_width, bbox_height])
        return

    print("MIDI_AMBIENT_NPC_AB_OK: %s %s" % [BEFORE_PATH, AFTER_PATH])
    viewport.queue_free()
    quit(0)
