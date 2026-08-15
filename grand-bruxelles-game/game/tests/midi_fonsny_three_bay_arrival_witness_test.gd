extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const BASE_MIDI_SCRIPT := "res://game/scripts/midi_hero_zone_materials.gd"
const OUTPUT_DIR := "res://artifacts/visual"
const BEFORE_PATH := OUTPUT_DIR + "/midi_fonsny_three_bay_before.png"
const AFTER_PATH := OUTPUT_DIR + "/midi_fonsny_three_bay_after.png"
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
    var min_x := WIDTH
    var min_y := HEIGHT
    var max_x := -1
    var max_y := -1
    var total := WIDTH * HEIGHT
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
    var ratio3 := float(over3) / float(total)
    var ratio8 := float(over8) / float(total)
    print("MIDI_FONSNY_THREE_BAY_DELTA over3=%d ratio3=%.6f over8=%d ratio8=%.6f bbox=(%d,%d)-(%d,%d)" % [over3, ratio3, over8, ratio8, min_x, min_y, max_x, max_y])
    if ratio3 < MIN_CHANGED_OVER_3:
        _fail("normal-player >3 RGB area below 2.0% predeclared anti-micro gate")
        return
    if ratio8 < MIN_CHANGED_OVER_8:
        _fail("normal-player >8 RGB area below 0.7% predeclared recognition gate")
        return
    print("MIDI_FONSNY_THREE_BAY_WITNESS_OK")
    quit(0)

func _capture(use_base_arrival: bool, path: String) -> Image:
    var packed := load(MAIN_SCENE) as PackedScene
    if packed == null:
        return null
    var world := packed.instantiate()
    var midi := world.get_node_or_null("MidiHeroZone") as Node3D
    if midi == null:
        world.free()
        return null
    if use_base_arrival:
        midi.set_script(load(BASE_MIDI_SCRIPT))
    get_root().add_child(world)
    await process_frame

    var camera := Camera3D.new()
    camera.name = "MidiFonsnyArrivalWitnessCamera"
    camera.position = ENTRANCE + ROAD_SIDE * 28.0 + Vector3(0.0, 2.70, 0.0)
    camera.fov = 69.0
    world.add_child(camera)
    camera.look_at(ENTRANCE + Vector3(0.0, 3.0, 0.0), Vector3.UP)
    camera.current = true
    await process_frame
    await RenderingServer.frame_post_draw
    var image := get_root().get_viewport().get_texture().get_image()
    var err := image.save_png(path)
    world.queue_free()
    await process_frame
    return image if err == OK else null

func _fail(message: String) -> void:
    push_error("MIDI_FONSNY_THREE_BAY_WITNESS_FAIL: " + message)
    quit(1)
