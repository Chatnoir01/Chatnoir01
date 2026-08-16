extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const IDENTITY_PATH := "res://data/visual/midi_architectural_concrete_material_identity.json"
const OUTPUT_DIR := "res://artifacts/visual"
const BEFORE_PATH := OUTPUT_DIR + "/midi_concrete_before.png"
const AFTER_PATH := OUTPUT_DIR + "/midi_concrete_after.png"
const WIDTH := 1280
const HEIGHT := 720
const MIN_CHANGED_OVER_3 := 0.0125
const MIN_CHANGED_OVER_8 := 0.0040

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

    var runtime := get_root().get_node_or_null("MidiArchitecturalConcreteSurfaceRuntime")
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
    if runtime.applied_surface_count() != 74:
        _fail("expected exactly 74 pre-existing source-designated concrete surfaces")
        return

    var parsed_identity: Variant = JSON.parse_string(FileAccess.get_file_as_string(IDENTITY_PATH))
    if typeof(parsed_identity) != TYPE_DICTIONARY:
        _fail("material identity contract invalid")
        return
    var candidate := parsed_identity as Dictionary
    if bool(runtime.call("_runtime_identity_allowed", candidate)):
        _fail("candidate must remain fail-closed before reviewed runtime approval")
        return
    var approved := candidate.duplicate(true)
    var approved_contract := approved.get("presentation_contract", {}) as Dictionary
    approved_contract["runtime_approved"] = true
    approved["presentation_contract"] = approved_contract
    if not bool(runtime.call("_runtime_identity_allowed", approved)):
        _fail("explicitly approved source contract must pass runtime guard")
        return

    var material := runtime.enhanced_material() as ShaderMaterial
    if material == null:
        _fail("candidate material missing")
        return
    if str(material.get_meta("material_family", "")) != "brussels_source_verified_architectural_concrete":
        _fail("material family drifted")
        return
    if bool(material.get_meta("geometry_changed", true)):
        _fail("material must not change geometry")
        return
    if bool(material.get_meta("formwork_pattern_authored", true)) or bool(material.get_meta("aggregate_scale_claimed", true)):
        _fail("material must not invent formwork or aggregate scale")
        return

    var camera := Camera3D.new()
    camera.name = "MidiConcreteWitnessCamera"
    camera.position = ENTRANCE + ROAD_SIDE * 28.0 + Vector3(0.0, 2.6, 0.0)
    camera.fov = 65.0
    world.add_child(camera)
    camera.look_at(ENTRANCE + Vector3(0.0, 6.5, 0.0), Vector3.UP)
    camera.current = true

    runtime.set_enhanced_material_enabled(false)
    var before := await _capture(BEFORE_PATH)
    runtime.apply_candidate_for_validation()
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
            var delta := maxf(absf(a.r - b.r) * 255.0, maxf(absf(a.g - b.g) * 255.0, absf(a.b - b.b) * 255.0))
            if delta > 3.0:
                over3 += 1
            if delta > 8.0:
                over8 += 1
    var ratio3 := float(over3) / float(total)
    var ratio8 := float(over8) / float(total)
    print("MIDI_CONCRETE_DELTA over3=%d ratio3=%.6f over8=%d ratio8=%.6f" % [over3, ratio3, over8, ratio8])
    if ratio3 < MIN_CHANGED_OVER_3:
        _fail("normal-distance >3 RGB area below 1.25% anti-micro gate")
        return
    if ratio8 < MIN_CHANGED_OVER_8:
        _fail("normal-distance >8 RGB area below 0.40% recognition gate")
        return
    print("MIDI_CONCRETE_WITNESS_OK")
    quit(0)

func _capture(path: String) -> Image:
    await process_frame
    await RenderingServer.frame_post_draw
    var image := get_root().get_viewport().get_texture().get_image()
    if image.save_png(path) != OK:
        return null
    return image

func _fail(message: String) -> void:
    push_error("MIDI_CONCRETE_WITNESS_FAIL: " + message)
    quit(1)
