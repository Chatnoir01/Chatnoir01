extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const OUTPUT_DIR := "res://artifacts/visual"
const BEFORE_PATH := OUTPUT_DIR + "/midi_fonsny_full_entrance_before.png"
const AFTER_PATH := OUTPUT_DIR + "/midi_fonsny_full_entrance_after.png"
const METRICS_PATH := OUTPUT_DIR + "/midi_fonsny_full_entrance_metrics.json"
const WIDTH := 1280
const HEIGHT := 720
const MIN_CHANGED_OVER_3 := 0.0300
const MIN_CHANGED_OVER_8 := 0.0150
const MIN_BBOX_WIDTH := 700
const MIN_BBOX_HEIGHT := 160
const CAMERA_POSITION := Vector3(-652.0, 1.72, 621.0)
const ENTRANCE := Vector3(-672.2905, 0.0, 615.8035)

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
    var packed := load(MAIN_SCENE) as PackedScene
    if packed == null:
        _fail("main scene missing")
        return
    var world := packed.instantiate()
    get_root().add_child(world)
    await process_frame
    await process_frame
    var mount := get_root().get_node_or_null("MidiArchitecturalConcreteSurfaceRuntime")
    if mount == null or not mount.has_method("fonsny_full_entrance_runtime"):
        _fail("Midi visual mount missing")
        return
    var runtime: Node = mount.fonsny_full_entrance_runtime()
    for _i in range(120):
        if runtime != null and (runtime.built() or runtime.build_failure()):
            break
        await process_frame
    if runtime == null or runtime.build_failure() or not runtime.built():
        _fail("Fonsny full entrance failed to build")
        return
    var replacement := runtime.replacement_root() as Node3D
    if replacement == null:
        _fail("replacement root missing")
        return
    _mask_dynamic_world(world, replacement)
    var camera := Camera3D.new()
    camera.name = "MidiFonsnyFullEntranceWitnessCamera"
    camera.position = CAMERA_POSITION
    camera.fov = 69.0
    world.add_child(camera)
    camera.look_at(ENTRANCE + Vector3(0.0, 5.2, 0.0), Vector3.UP)
    camera.current = true

    runtime.set_replacement_enabled(false)
    var before := await _capture(BEFORE_PATH)
    runtime.set_replacement_enabled(true)
    var after := await _capture(AFTER_PATH)
    if before == null or after == null:
        _fail("capture missing")
        return

    var over3 := 0
    var over8 := 0
    var min_x := WIDTH
    var min_y := HEIGHT
    var max_x := -1
    var max_y := -1
    var total := WIDTH * HEIGHT
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := maxf(absf(a.r - b.r) * 255.0, maxf(absf(a.g - b.g) * 255.0, absf(a.b - b.b) * 255.0))
            if delta > 3.0:
                over3 += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
            if delta > 8.0:
                over8 += 1
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
        "min_over3_ratio": MIN_CHANGED_OVER_3,
        "min_over8_ratio": MIN_CHANGED_OVER_8,
        "min_bbox_width": MIN_BBOX_WIDTH,
        "min_bbox_height": MIN_BBOX_HEIGHT
    }
    var f := FileAccess.open(METRICS_PATH, FileAccess.WRITE)
    if f != null:
        f.store_string(JSON.stringify(metrics, "  "))
    print("MIDI_FONSNY_FULL_ENTRANCE_DELTA ratio3=%.6f ratio8=%.6f bbox=%dx%d" % [ratio3, ratio8, bbox_w, bbox_h])
    if ratio3 < MIN_CHANGED_OVER_3 or ratio8 < MIN_CHANGED_OVER_8 or bbox_w < MIN_BBOX_WIDTH or bbox_h < MIN_BBOX_HEIGHT:
        _fail("locked visual impact gate failed")
        return
    print("MIDI_FONSNY_FULL_ENTRANCE_WITNESS_OK")
    quit(0)

func _mask_dynamic_world(node: Node, protected: Node) -> void:
    if node == protected or protected.is_ancestor_of(node):
        return
    if node is CanvasItem:
        (node as CanvasItem).visible = false
    if node is Node3D:
        var lower := node.name.to_lower()
        for token in ["player", "npc", "pedestrian", "traffic", "vehicle", "ambient", "police"]:
            if token in lower:
                (node as Node3D).visible = false
                break
    for child: Node in node.get_children():
        _mask_dynamic_world(child, protected)

func _capture(path: String) -> Image:
    await process_frame
    await process_frame
    await RenderingServer.frame_post_draw
    var image := get_root().get_viewport().get_texture().get_image()
    if image.save_png(path) != OK:
        return null
    return image

func _fail(message: String) -> void:
    push_error("MIDI_FONSNY_FULL_ENTRANCE_WITNESS_FAIL: " + message)
    quit(1)
