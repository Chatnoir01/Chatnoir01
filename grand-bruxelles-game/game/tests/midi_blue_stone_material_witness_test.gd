extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const OUTPUT_DIR := "res://artifacts/visual"
const BEFORE_PATH := OUTPUT_DIR + "/midi_blue_stone_before.png"
const AFTER_PATH := OUTPUT_DIR + "/midi_blue_stone_after.png"
const WIDTH := 1280
const HEIGHT := 720
const MIN_CHANGED_OVER_3 := 0.010
const MIN_CHANGED_OVER_8 := 0.0035

const ENTRANCE := Vector3(-672.2905, 0.0, 615.8035)
const ROAD_SIDE := Vector3(0.779, 0.0, 0.627)

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

    var runtime := get_root().get_node_or_null("MidiBlueStoneSurfaceRuntime")
    if runtime == null:
        _fail("autoload missing")
        return
    for _i in range(20):
        if runtime.ready_complete():
            break
        await process_frame
    if not runtime.ready_complete() or runtime.identity_failure():
        _fail("runtime identity/application failed")
        return
    if runtime.applied_surface_count() != 4:
        _fail("expected exactly four pre-existing blue-stone base surfaces")
        return
    var material := runtime.enhanced_material() as ShaderMaterial
    if material == null:
        _fail("enhanced material missing")
        return
    if str(material.get_meta("material_family", "")) != "brussels_source_verified_blue_stone":
        _fail("material family drifted")
        return
    if bool(material.get_meta("geometry_changed", true)):
        _fail("material must not change geometry")
        return
    if bool(material.get_meta("masonry_joints_authored", true)) or bool(material.get_meta("tooling_pattern_authored", true)):
        _fail("material must not invent stone layout/tooling")
        return

    var camera := Camera3D.new()
    camera.name = "MidiBlueStoneWitnessCamera"
    camera.position = ENTRANCE + ROAD_SIDE * 28.0 + Vector3(0.0, 2.6, 0.0)
    camera.fov = 65.0
    world.add_child(camera)
    camera.look_at(ENTRANCE + Vector3(0.0, 3.2, 0.0), Vector3.UP)
    camera.current = true

    runtime.set_enhanced_material_enabled(false)
    var before := await _capture(BEFORE_PATH)
    runtime.set_enhanced_material_enabled(true)
    var after := await _capture(AFTER_PATH)
    if before == null or after == null:
        _fail("capture missing")
        return
    if before.get_width() != WIDTH or before.get_height() != HEIGHT or after.get_width() != WIDTH or after.get_height() != HEIGHT:
        _fail("capture resolution must be 1280x720")
        return

    var over3 := 0
    var over8 := 0
    var total := WIDTH * HEIGHT
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := maxf(
                absf(a.r - b.r) * 255.0,
                maxf(absf(a.g - b.g) * 255.0, absf(a.b - b.b) * 255.0)
            )
            if delta > 3.0:
                over3 += 1
            if delta > 8.0:
                over8 += 1
    var ratio3 := float(over3) / float(total)
    var ratio8 := float(over8) / float(total)
    print("MIDI_BLUE_STONE_DELTA over3=%d ratio3=%.6f over8=%d ratio8=%.6f" % [over3, ratio3, over8, ratio8])
    if ratio3 < MIN_CHANGED_OVER_3:
        _fail("normal-distance >3 RGB area below 1.0% anti-micro gate")
        return
    if ratio8 < MIN_CHANGED_OVER_8:
        _fail("normal-distance >8 RGB area below 0.35% recognition gate")
        return
    print("MIDI_BLUE_STONE_WITNESS_OK")
    quit(0)

func _capture(path: String) -> Image:
    await process_frame
    await RenderingServer.frame_post_draw
    var image := get_root().get_viewport().get_texture().get_image()
    if image.save_png(path) != OK:
        return null
    return image

func _fail(message: String) -> void:
    push_error("MIDI_BLUE_STONE_WITNESS_FAIL: " + message)
    quit(1)
