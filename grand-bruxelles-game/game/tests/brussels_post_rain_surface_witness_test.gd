extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const OUTPUT_DIR := "res://artifacts/visual"
const WIDTH := 1280
const HEIGHT := 720
const MIN_CHANGED_OVER_3 := 0.025
const MIN_CHANGED_OVER_8 := 0.010

const MIDI_ENTRANCE := Vector3(-672.2905, 0.0, 615.8035)
const MIDI_ROAD_SIDE := Vector3(0.779, 0.0, 0.627)
const BOURSE_CAMERA_POSITION := Vector3(101.90921495304792, 1.68, -738.3896080011874)
const BOURSE_CAMERA_ROTATION := Vector3(0.0, -135.21993255901, 0.0)
const BOURSE_HORIZONTAL_FOV := 63.65489315334623

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
    var captures := {
        "midi_before": await _capture("midi", false, OUTPUT_DIR + "/post_rain_midi_before.png"),
        "midi_after": await _capture("midi", true, OUTPUT_DIR + "/post_rain_midi_after.png"),
        "bourse_before": await _capture("bourse", false, OUTPUT_DIR + "/post_rain_bourse_before.png"),
        "bourse_after": await _capture("bourse", true, OUTPUT_DIR + "/post_rain_bourse_after.png"),
    }
    for key: String in captures:
        var image: Image = captures[key]
        if image == null or image.is_empty():
            _fail("capture missing: %s" % key)
            return
        if image.get_width() != WIDTH or image.get_height() != HEIGHT:
            _fail("capture must be 1280x720: %s" % key)
            return

    if not _measure("MIDI", captures["midi_before"], captures["midi_after"]):
        return
    if not _measure("BOURSE", captures["bourse_before"], captures["bourse_after"]):
        return
    print("BRUSSELS_POST_RAIN_WITNESS_OK")
    quit(0)

func _horizontal_to_vertical_fov(horizontal_degrees: float, aspect: float) -> float:
    return rad_to_deg(2.0 * atan(tan(deg_to_rad(horizontal_degrees) * 0.5) / aspect))

func _configure_wetness(world: Node, enabled: bool) -> void:
    var value := 0.62 if enabled else 0.0
    var midi := world.get_node_or_null("UrbISMidiExact")
    if midi != null:
        midi.set("post_rain_wetness", value)
    var bourse := world.get_node_or_null("UrbISBourseSurfaceContext")
    if bourse != null:
        bourse.set("post_rain_wetness", value)

func _hide_noise(node: Node) -> void:
    if node is Label3D:
        (node as Label3D).visible = false
    for child: Node in node.get_children():
        _hide_noise(child)

func _capture(location: String, wet: bool, path: String) -> Image:
    var packed := load(MAIN_SCENE) as PackedScene
    if packed == null:
        return null
    var world := packed.instantiate()
    if world == null:
        return null
    _configure_wetness(world, wet)
    var traffic := world.get_node_or_null("TrafficManager")
    if traffic != null:
        traffic.set("auto_spawn_runtime", false)
    get_root().add_child(world)
    await process_frame
    _hide_noise(world)

    var existing := get_root().get_viewport().get_camera_3d()
    if existing != null:
        existing.current = false
    var camera := Camera3D.new()
    camera.name = "PostRainWitnessCamera"
    if location == "midi":
        camera.position = MIDI_ENTRANCE + MIDI_ROAD_SIDE * 28.0 + Vector3(0.0, 2.6, 0.0)
        camera.fov = 65.0
        world.add_child(camera)
        camera.look_at(MIDI_ENTRANCE + Vector3(0.0, 2.0, 0.0), Vector3.UP)
    else:
        camera.position = BOURSE_CAMERA_POSITION
        camera.rotation_degrees = BOURSE_CAMERA_ROTATION
        camera.keep_aspect = Camera3D.KEEP_HEIGHT
        camera.fov = _horizontal_to_vertical_fov(BOURSE_HORIZONTAL_FOV, float(WIDTH) / float(HEIGHT))
        world.add_child(camera)
    camera.current = true

    for _frame: int in range(8):
        await process_frame
    await RenderingServer.frame_post_draw
    var image := get_root().get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        world.queue_free()
        await process_frame
        return null
    var error := image.save_png(path)
    world.queue_free()
    await process_frame
    if error != OK:
        return null
    return image

func _measure(label: String, before: Image, after: Image) -> bool:
    var over3 := 0
    var over8 := 0
    var total := WIDTH * HEIGHT
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) * 255.0
            if delta > 3.0:
                over3 += 1
            if delta > 8.0:
                over8 += 1
    var ratio3 := float(over3) / float(total)
    var ratio8 := float(over8) / float(total)
    print("BRUSSELS_POST_RAIN_%s_DELTA over3=%d ratio3=%.6f over8=%d ratio8=%.6f" % [label, over3, ratio3, over8, ratio8])
    if ratio3 < MIN_CHANGED_OVER_3:
        _fail("%s >3 RGB area below 2.5%% anti-micro gate" % label)
        return false
    if ratio8 < MIN_CHANGED_OVER_8:
        _fail("%s >8 RGB area below 1.0%% recognition gate" % label)
        return false
    return true

func _fail(message: String) -> void:
    push_error("BRUSSELS_POST_RAIN_WITNESS_FAIL: " + message)
    quit(1)
