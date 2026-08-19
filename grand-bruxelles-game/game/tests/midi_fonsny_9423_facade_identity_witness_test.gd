extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const OUT := "res://artifacts/visual"
const BEFORE := OUT + "/midi_fonsny_9423_facade_before.png"
const AFTER := OUT + "/midi_fonsny_9423_facade_after.png"
const METRICS := OUT + "/midi_fonsny_9423_facade_metrics.json"
const WIDTH := 1280
const HEIGHT := 720
const CAMERA_POSITION := Vector3(-652.0, 1.72, 621.0)
const ENTRANCE := Vector3(-672.2905, 0.0, 615.8035)
const MIN_OVER3 := 0.0300
const MIN_OVER8 := 0.0150
const MIN_BBOX_W := 700
const MIN_BBOX_H := 220

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
    var packed := load(MAIN_SCENE) as PackedScene
    if packed == null:
        _fail("main scene missing")
        return
    var world := packed.instantiate()
    get_root().add_child(world)
    var runtime: Node = null
    for _frame: int in range(300):
        runtime = get_root().get_node_or_null("MidiFonsny9423FacadeIdentityRuntime")
        if runtime != null and bool(runtime.call("ready_complete")):
            break
        await process_frame
    if runtime == null or bool(runtime.call("failed")):
        _fail("registry runtime failed")
        return
    if int(runtime.call("window_count")) < 300:
        _fail("too few existing windows covered")
        return
    if int(runtime.call("vertical_bay_count")) != 2 or int(runtime.call("bow_segment_count")) != 14:
        _fail("vertical identity contract incomplete")
        return
    if int(runtime.call("collision_count_added")) != 0:
        _fail("candidate must not add collision")
        return
    var central := world.get_node_or_null("MidiHeroZone/BruxellesMidiStation/FonsnyCentral") as Node3D
    if central == null:
        _fail("FonsnyCentral missing")
        return
    var legacy_frame := central.get_node_or_null("VerticalGlassTowerFrame") as MeshInstance3D
    var legacy_glass := central.get_node_or_null("VerticalGlassTower") as MeshInstance3D
    if legacy_frame == null or legacy_glass == null:
        _fail("legacy single vertical bay missing")
        return
    _mask_dynamic(get_root())
    var leaked_canvas := _visible_canvas_count(get_root())
    if leaked_canvas > 0:
        _fail("visible Canvas UI leaked into locked witness: %d" % leaked_canvas)
        return
    print("MIDI_FONSNY_9423_FACADE_UI_CLEAN: visible_canvas=%d" % leaked_canvas)
    var camera := Camera3D.new()
    camera.name = "MidiFonsny9423FacadeWitnessCamera"
    camera.position = CAMERA_POSITION
    camera.fov = 69.0
    world.add_child(camera)
    camera.look_at(ENTRANCE + Vector3(0.0, 5.2, 0.0), Vector3.UP)
    camera.current = true
    world.process_mode = Node.PROCESS_MODE_DISABLED

    runtime.call("set_identity_enabled", false)
    if not legacy_frame.visible or not legacy_glass.visible:
        _fail("BEFORE must restore legacy single vertical bay")
        return
    var before := await _capture(BEFORE)
    runtime.call("set_identity_enabled", true)
    if legacy_frame.visible or legacy_glass.visible:
        _fail("AFTER must supersede legacy single vertical bay")
        return
    var after := await _capture(AFTER)
    if before == null or after == null:
        _fail("A/B capture missing")
        return
    if before.get_width() != WIDTH or before.get_height() != HEIGHT or after.get_width() != WIDTH or after.get_height() != HEIGHT:
        _fail("capture resolution changed")
        return

    var over3 := 0
    var over8 := 0
    var min_x := WIDTH
    var min_y := HEIGHT
    var max_x := -1
    var max_y := -1
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) * 255.0
            if delta > 3.0:
                over3 += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
            if delta > 8.0:
                over8 += 1
    var total := WIDTH * HEIGHT
    var ratio3 := float(over3) / float(total)
    var ratio8 := float(over8) / float(total)
    var bbox_w := 0 if max_x < min_x else max_x - min_x + 1
    var bbox_h := 0 if max_y < min_y else max_y - min_y + 1
    var metrics := {
        "width": WIDTH,
        "height": HEIGHT,
        "camera": [CAMERA_POSITION.x, CAMERA_POSITION.y, CAMERA_POSITION.z],
        "fov": 69.0,
        "over3_pixels": over3,
        "over3_ratio": ratio3,
        "over8_pixels": over8,
        "over8_ratio": ratio8,
        "bbox_width": bbox_w,
        "bbox_height": bbox_h,
        "min_over3_ratio": MIN_OVER3,
        "min_over8_ratio": MIN_OVER8,
        "min_bbox_width": MIN_BBOX_W,
        "min_bbox_height": MIN_BBOX_H,
        "window_count": int(runtime.call("window_count")),
        "vertical_bays": int(runtime.call("vertical_bay_count")),
        "bow_segments": int(runtime.call("bow_segment_count"))
    }
    var file := FileAccess.open(METRICS, FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify(metrics, "  "))
    print("MIDI_FONSNY_9423_FACADE_METRICS: ratio3=%.6f ratio8=%.6f bbox=%dx%d windows=%d vertical_bays=%d" % [ratio3, ratio8, bbox_w, bbox_h, int(runtime.call("window_count")), int(runtime.call("vertical_bay_count"))])
    if ratio3 < MIN_OVER3 or ratio8 < MIN_OVER8 or bbox_w < MIN_BBOX_W or bbox_h < MIN_BBOX_H:
        _fail("locked broad player-eye gate failed")
        return
    print("MIDI_FONSNY_9423_FACADE_OK")
    quit(0)

func _mask_dynamic(node: Node) -> void:
    if node is CanvasItem:
        (node as CanvasItem).visible = false
    if node is Node3D:
        var lower := str(node.name).to_lower()
        for token: String in ["player", "npc", "pedestrian", "traffic", "vehicle", "ambient", "police"]:
            if token in lower:
                (node as Node3D).visible = false
                break
    for child: Node in node.get_children():
        _mask_dynamic(child)

func _visible_canvas_count(node: Node) -> int:
    var count := 0
    if node is CanvasLayer:
        if (node as CanvasLayer).visible:
            count += 1
    elif node is CanvasItem:
        if (node as CanvasItem).is_visible_in_tree():
            count += 1
    for child: Node in node.get_children():
        count += _visible_canvas_count(child)
    return count

func _capture(path: String) -> Image:
    await process_frame
    await process_frame
    await RenderingServer.frame_post_draw
    var image := get_root().get_viewport().get_texture().get_image()
    if image == null or image.is_empty() or image.save_png(path) != OK:
        return null
    return image

func _fail(message: String) -> void:
    push_error("MIDI_FONSNY_9423_FACADE_FAIL: " + message)
    quit(1)
