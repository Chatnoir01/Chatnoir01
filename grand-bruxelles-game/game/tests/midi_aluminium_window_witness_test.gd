extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const OUTPUT_DIR := "res://artifacts/visual"
const BEFORE_PATH := OUTPUT_DIR + "/midi_aluminium_window_before.png"
const AFTER_PATH := OUTPUT_DIR + "/midi_aluminium_window_after.png"
const WIDTH := 1280
const HEIGHT := 720
const MIN_CHANGED_OVER_3 := 0.015
const MIN_CHANGED_OVER_8 := 0.006
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
            var delta := maxf(absf(a.r - b.r) * 255.0, maxf(absf(a.g - b.g) * 255.0, absf(a.b - b.b) * 255.0))
            if delta > 3.0:
                over3 += 1
            if delta > 8.0:
                over8 += 1
    var ratio3 := float(over3) / float(total)
    var ratio8 := float(over8) / float(total)
    print("MIDI_ALUMINIUM_WINDOW_DELTA over3=%d ratio3=%.6f over8=%d ratio8=%.6f" % [over3, ratio3, over8, ratio8])
    if ratio3 < MIN_CHANGED_OVER_3:
        _fail("normal-distance >3 RGB area below 1.5% predeclared gate")
        return
    if ratio8 < MIN_CHANGED_OVER_8:
        _fail("normal-distance >8 RGB area below 0.6% predeclared recognition gate")
        return
    print("MIDI_ALUMINIUM_WINDOW_WITNESS_OK")
    quit(0)

func _capture(hide_aluminium: bool, path: String) -> Image:
    var packed := load(MAIN_SCENE) as PackedScene
    if packed == null:
        return null
    var world := packed.instantiate()
    get_root().add_child(world)
    await process_frame
    var midi := world.get_node_or_null("MidiHeroZone") as Node3D
    var station := midi.get_node_or_null("BruxellesMidiStation") as Node3D if midi != null else null
    var central := station.get_node_or_null("FonsnyCentral") as Node3D if station != null else null
    if central == null:
        world.queue_free()
        await process_frame
        return null
    if hide_aluminium:
        for block_name: String in ["FonsnyWingSouth", "FonsnyCentral", "FonsnyWingNorth"]:
            var block := station.get_node_or_null(block_name) as Node3D
            if block == null:
                continue
            for node_name: String in ["AluminiumWindowFrames", "AluminiumWindowTransoms", "AluminiumSunshades"]:
                var node := block.get_node_or_null(node_name) as GeometryInstance3D
                if node != null:
                    node.visible = false

    var target := central.global_position + Vector3(0.0, 11.0, 0.0)
    var camera := Camera3D.new()
    camera.name = "MidiAluminiumWindowWitnessCamera"
    camera.position = target + ROAD_SIDE * 32.0 + Vector3(0.0, 1.4, 0.0)
    camera.fov = 62.0
    world.add_child(camera)
    camera.look_at(target, Vector3.UP)
    camera.current = true
    await process_frame
    await RenderingServer.frame_post_draw
    var image := get_root().get_viewport().get_texture().get_image()
    var err := image.save_png(path)
    world.queue_free()
    await process_frame
    return image if err == OK else null

func _fail(message: String) -> void:
    push_error("MIDI_ALUMINIUM_WINDOW_WITNESS_FAIL: " + message)
    quit(1)
