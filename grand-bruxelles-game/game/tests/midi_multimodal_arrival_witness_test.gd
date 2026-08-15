extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const OUTPUT_DIR := "res://artifacts/visual"
const OUTPUT_PATH := OUTPUT_DIR + "/midi_multimodal_arrival_after.png"
const WIDTH := 1280
const HEIGHT := 720
const ENTRANCE := Vector3(-672.2905, 0.0, 615.8035)
const ROAD_SIDE := Vector3(0.779, 0.0, 0.627)

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
    var packed := load(MAIN_SCENE) as PackedScene
    if packed == null:
        _fail("main scene must load")
        return
    var world := packed.instantiate()
    get_root().add_child(world)
    await process_frame

    var midi := world.get_node_or_null("MidiHeroZone") as Node3D
    if midi == null or midi.get_node_or_null("MidiMobilityWayfinding") == null:
        _fail("multimodal runtime must exist before capture")
        return

    # Reuse the proven unobstructed Fonsny witness framing already used by
    # the station material QA instead of inventing a camera inside geometry.
    var camera := Camera3D.new()
    camera.name = "MidiMultimodalWitnessCamera"
    camera.position = ENTRANCE + ROAD_SIDE * 28.0 + Vector3(0.0, 2.6, 0.0)
    camera.fov = 65.0
    world.add_child(camera)
    camera.look_at(ENTRANCE + Vector3(0.0, 3.2, 0.0), Vector3.UP)
    camera.current = true
    await process_frame
    await RenderingServer.frame_post_draw

    var image := get_root().get_viewport().get_texture().get_image()
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        _fail("capture resolution must be 1280x720")
        return
    if image.save_png(OUTPUT_PATH) != OK:
        _fail("failed to save witness PNG")
        return

    print("MIDI_MULTIMODAL_WITNESS_OK: %s (%dx%d)" % [OUTPUT_PATH, WIDTH, HEIGHT])
    world.queue_free()
    await process_frame
    quit(0)

func _fail(message: String) -> void:
    push_error("MIDI_MULTIMODAL_WITNESS_FAIL: " + message)
    quit(1)
