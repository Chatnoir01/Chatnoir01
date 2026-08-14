extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const BASE_MIDI_SCRIPT := "res://game/scripts/midi_hero_zone.gd"
const OUTPUT_DIR := "res://artifacts/visual"
const BEFORE_PATH := OUTPUT_DIR + "/midi_concrete_glassblock_before.png"
const AFTER_PATH := OUTPUT_DIR + "/midi_concrete_glassblock_after.png"
const WIDTH := 1280
const HEIGHT := 720
const MIN_CHANGED_OVER_3 := 0.020
const MIN_CHANGED_OVER_8 := 0.007

const ENTRANCE := Vector3(-672.2905, 0.0, 615.8035)
const ROAD_SIDE := Vector3(0.779, 0.0, 0.627)

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
    var before := await _capture(true, BEFORE_PATH)
    var after := await _capture(false, AFTER_PATH)
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
            var dr := absf(a.r - b.r) * 255.0
            var dg := absf(a.g - b.g) * 255.0
            var db := absf(a.b - b.b) * 255.0
            var delta := maxf(dr, maxf(dg, db))
            if delta > 3.0:
                over3 += 1
            if delta > 8.0:
                over8 += 1
    var ratio3 := float(over3) / float(total)
    var ratio8 := float(over8) / float(total)
    print("MIDI_CONCRETE_GLASSBLOCK_DELTA over3=%d ratio3=%.6f over8=%d ratio8=%.6f" % [over3, ratio3, over8, ratio8])
    if ratio3 < MIN_CHANGED_OVER_3:
        _fail("normal-distance >3 RGB area below 2.0% anti-micro gate")
        return
    if ratio8 < MIN_CHANGED_OVER_8:
        _fail("normal-distance >8 RGB area below 0.7% recognition gate")
        return
    print("MIDI_CONCRETE_GLASSBLOCK_WITNESS_OK")
    quit(0)

func _capture(use_base_materials: bool, path: String) -> Image:
    var packed := load(MAIN_SCENE) as PackedScene
    if packed == null:
        return null
    var world := packed.instantiate()
    var midi := world.get_node_or_null("MidiHeroZone") as Node3D
    if midi == null:
        world.free()
        return null
    if use_base_materials:
        midi.set_script(load(BASE_MIDI_SCRIPT))
    get_root().add_child(world)
    await process_frame

    var camera := Camera3D.new()
    camera.name = "MidiMaterialWitnessCamera"
    camera.position = ENTRANCE + ROAD_SIDE * 28.0 + Vector3(0.0, 2.6, 0.0)
    camera.fov = 65.0
    world.add_child(camera)
    camera.look_at(ENTRANCE + Vector3(0.0, 3.2, 0.0), Vector3.UP)
    camera.current = true
    await process_frame
    await RenderingServer.frame_post_draw
    var image := get_root().get_viewport().get_texture().get_image()
    var err := image.save_png(path)
    if err != OK:
        world.queue_free()
        await process_frame
        return null
    world.queue_free()
    await process_frame
    return image

func _fail(message: String) -> void:
    push_error("MIDI_CONCRETE_GLASSBLOCK_WITNESS_FAIL: " + message)
    quit(1)
