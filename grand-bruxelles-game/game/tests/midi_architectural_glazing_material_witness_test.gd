extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const IDENTITY_PATH := "res://data/visual/midi_architectural_glazing_material_identity.json"
const OUTPUT_DIR := "res://artifacts/visual"
const BEFORE_PATH := OUTPUT_DIR + "/midi_glazing_before.png"
const AFTER_PATH := OUTPUT_DIR + "/midi_glazing_after.png"
const WIDTH := 1280
const HEIGHT := 720
const MIN_CHANGED_OVER_3 := 0.02
const MIN_CHANGED_OVER_8 := 0.0075
const EXPECTED_SURFACES := 340

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

    var runtime := get_root().get_node_or_null("MidiArchitecturalGlazingSurfaceRuntime")
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
    if runtime.applied_surface_count() != EXPECTED_SURFACES:
        _fail("expected exactly %d pre-existing glazing surfaces, got %d" % [EXPECTED_SURFACES, runtime.applied_surface_count()])
        return

    var parsed_identity: Variant = JSON.parse_string(FileAccess.get_file_as_string(IDENTITY_PATH))
    if typeof(parsed_identity) != TYPE_DICTIONARY:
        _fail("material identity contract invalid")
        return
    var approved := (parsed_identity as Dictionary).duplicate(true)
    var approved_contract := approved.get("presentation_contract", {}) as Dictionary
    approved_contract["runtime_approved"] = true
    approved["presentation_contract"] = approved_contract
    if not bool(runtime.call("_runtime_identity_allowed", approved)):
        _fail("explicitly approved source contract must pass runtime guard")
        return
    var unapproved := approved.duplicate(true)
    var unapproved_contract := unapproved.get("presentation_contract", {}) as Dictionary
    unapproved_contract["runtime_approved"] = false
    unapproved["presentation_contract"] = unapproved_contract
    if bool(runtime.call("_runtime_identity_allowed", unapproved)):
        _fail("runtime guard must reject source contract when runtime_approved=false")
        return

    runtime.set_enhanced_material_enabled(false)
    runtime.set("_identity", unapproved)
    runtime.set_enhanced_material_enabled(true)
    if runtime.enhanced_material_enabled():
        _fail("runtime_approved=false bypassed by set_enhanced_material_enabled(true)")
        return
    runtime.set("_identity", approved)
    runtime.set_enhanced_material_enabled(true)
    if not runtime.enhanced_material_enabled():
        _fail("approved identity could not re-enable glazing after authorization guard")
        return

    var material := runtime.enhanced_material() as ShaderMaterial
    if material == null:
        _fail("candidate material missing")
        return
    if str(material.get_meta("material_family", "")) != "brussels_source_verified_architectural_glazing":
        _fail("material family drifted")
        return
    if bool(material.get_meta("geometry_changed", true)):
        _fail("material must not change geometry")
        return
    if bool(material.get_meta("pane_layout_authored", true)) or bool(material.get_meta("exact_reflectance_claimed", true)):
        _fail("material must not invent pane layout or measured reflectance")
        return

    var camera := Camera3D.new()
    camera.name = "MidiGlazingWitnessCamera"
    camera.position = ENTRANCE + ROAD_SIDE * 28.0 + Vector3(0.0, 2.6, 0.0)
    camera.fov = 65.0
    world.add_child(camera)
    camera.look_at(ENTRANCE + Vector3(0.0, 7.5, 0.0), Vector3.UP)
    camera.current = true

    paused = true
    await process_frame
    await RenderingServer.frame_post_draw

    runtime.set_enhanced_material_enabled(false)
    var before := await _capture(BEFORE_PATH)
    var control := await _capture("")
    if before == null or control == null:
        _fail("capture missing")
        return
    var control_over3 := _count_pixels_over_delta(before, control, 3.0)
    if control_over3 != 0:
        _fail("frozen A/B control drifted by %d pixels above 3 RGB; dynamic state is not deterministic" % control_over3)
        return

    runtime.set_enhanced_material_enabled(true)
    var after := await _capture(AFTER_PATH)
    if after == null:
        _fail("capture missing")
        return
    if before.get_width() != WIDTH or before.get_height() != HEIGHT or after.get_width() != WIDTH or after.get_height() != HEIGHT:
        _fail("capture resolution must be 1280x720")
        return

    var over3 := _count_pixels_over_delta(before, after, 3.0)
    var over8 := _count_pixels_over_delta(before, after, 8.0)
    var total := WIDTH * HEIGHT
    var ratio3 := float(over3) / float(total)
    var ratio8 := float(over8) / float(total)
    print("MIDI_GLAZING_CONTROL frozen=true over3=%d" % control_over3)
    print("MIDI_GLAZING_DELTA over3=%d ratio3=%.6f over8=%d ratio8=%.6f" % [over3, ratio3, over8, ratio8])
    if ratio3 < MIN_CHANGED_OVER_3:
        _fail("normal-distance >3 RGB area below 2.00% anti-micro gate")
        return
    if ratio8 < MIN_CHANGED_OVER_8:
        _fail("normal-distance >8 RGB area below 0.75% recognition gate")
        return
    print("MIDI_GLAZING_WITNESS_OK")
    quit(0)

func _count_pixels_over_delta(a: Image, b: Image, threshold: float) -> int:
    if a == null or b == null or a.get_size() != b.get_size():
        return WIDTH * HEIGHT
    var changed := 0
    for y: int in range(a.get_height()):
        for x: int in range(a.get_width()):
            var pa := a.get_pixel(x, y)
            var pb := b.get_pixel(x, y)
            var delta := maxf(absf(pa.r - pb.r) * 255.0, maxf(absf(pa.g - pb.g) * 255.0, absf(pa.b - pb.b) * 255.0))
            if delta > threshold:
                changed += 1
    return changed

func _capture(path: String) -> Image:
    await process_frame
    await RenderingServer.frame_post_draw
    var image := get_root().get_viewport().get_texture().get_image()
    if not path.is_empty() and image.save_png(path) != OK:
        return null
    return image

func _fail(message: String) -> void:
    push_error("MIDI_GLAZING_WITNESS_FAIL: " + message)
    quit(1)
