extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const OUTPUT_DIR := "res://artifacts/visual"
const CONTEXT_PATH := OUTPUT_DIR + "/midi_multimodal_arrival_context.png"
const CLOSE_PATH := OUTPUT_DIR + "/midi_multimodal_arrival_close.png"
const WIDTH := 1280
const HEIGHT := 720
const MIDI := Vector3(-668.5, 0.0, 627.84)
const FONSNY_AXIS := Vector3(-0.627, 0.0, 0.779)
const STATION_SIDE := Vector3(-0.779, 0.0, -0.627)
const ROAD_SIDE := Vector3(0.779, 0.0, 0.627)
const ENTRANCE := Vector3(-672.2905, 0.0, 615.8035)

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

    var camera := Camera3D.new()
    camera.name = "MidiMultimodalWitnessCamera"
    camera.fov = 65.0
    world.add_child(camera)
    camera.current = true

    # Broad station context using the existing proven Fonsny QA framing.
    camera.position = ENTRANCE + ROAD_SIDE * 28.0 + Vector3(0.0, 2.6, 0.0)
    camera.look_at(ENTRANCE + Vector3(0.0, 3.2, 0.0), Vector3.UP)
    if not await _save_view(camera, CONTEXT_PATH):
        _fail("failed to save context witness")
        return

    # Pedestrian-distance view centered on the actual wayfinding anchor.
    var wayfinding_position := MIDI + STATION_SIDE * 7.4 + FONSNY_AXIS * 9.0
    camera.position = wayfinding_position + ROAD_SIDE * 18.0 + FONSNY_AXIS * -2.0 + Vector3(0.0, 2.45, 0.0)
    camera.look_at(wayfinding_position + Vector3(0.0, 2.25, 0.0), Vector3.UP)
    if not await _save_view(camera, CLOSE_PATH):
        _fail("failed to save close witness")
        return

    print("MIDI_MULTIMODAL_WITNESS_OK: context+close (%dx%d)" % [WIDTH, HEIGHT])
    world.queue_free()
    await process_frame
    quit(0)

func _save_view(camera: Camera3D, path: String) -> bool:
    camera.current = true
    await process_frame
    await RenderingServer.frame_post_draw
    var image := get_root().get_viewport().get_texture().get_image()
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        return false
    return image.save_png(path) == OK

func _fail(message: String) -> void:
    push_error("MIDI_MULTIMODAL_WITNESS_FAIL: " + message)
    quit(1)
