extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const SOURCE_PATH := "res://data/qa/midi_fonsny_crosswalk_ortho2023.json"
const CONTROLLER_PATH := NodePath("/root/MidiArrivalPlanimetry")

func _init() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_ARRIVAL_PLANIMETRY_FAIL: " + message)
    quit(1)

func _run() -> void:
    if not FileAccess.file_exists(SOURCE_PATH):
        _fail("source JSON missing")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("source JSON invalid")
        return
    var data := parsed as Dictionary
    if bool(data.get("runtime_approved", true)):
        _fail("Ortho2023 derived geometry must remain blocked until reuse is verified")
        return
    var source: Dictionary = data.get("source", {})
    var render: Dictionary = data.get("render", {})
    if str(source.get("provider", "")) != "Paradigm / Brussels-Capital Region":
        _fail("unexpected source provider")
        return
    if str(source.get("layer", "")) != "urbisgrid:Ortho2023":
        _fail("unexpected orthophoto layer")
        return
    if absf(float(source.get("pixel_size_m", 0.0)) - 0.125) > 0.0001:
        _fail("source pixel size drifted")
        return
    if int(render.get("rect_count", 0)) != 209:
        _fail("source-derived marking rectangle count drifted")
        return
    if absf(float(render.get("paint_area_m2", 0.0)) - 27.625) > 0.001:
        _fail("source-derived marking area drifted")
        return

    var packed := load(MAIN_SCENE) as PackedScene
    if packed == null:
        _fail("main scene missing")
        return
    var world := packed.instantiate()
    root.add_child(world)
    current_scene = world
    await process_frame
    await process_frame
    await process_frame

    var controller := root.get_node_or_null(CONTROLLER_PATH)
    if controller == null:
        _fail("autoload controller missing")
        return
    var attempts := 0
    while not bool(controller.get("visual_built")) and attempts < 30:
        await process_frame
        attempts += 1
    if not bool(controller.get("visual_built")):
        _fail("controller did not mount")
        return

    var hero := world.get_node_or_null("MidiHeroZone") as Node3D
    var exact := world.get_node_or_null("UrbISMidiExact") as Node3D
    if hero == null or exact == null:
        _fail("production Midi nodes missing")
        return
    var forecourt := hero.get_node_or_null("FonsnyStationForecourt") as GeometryInstance3D
    var official := hero.get_node_or_null("OfficialFonsnyCrosswalkOrtho2023") as MeshInstance3D
    if forecourt == null or official == null:
        _fail("baseline/source arrival geometry missing")
        return
    if forecourt.visible:
        _fail("authored forecourt slab must be hidden in source mode")
        return
    if not official.visible:
        _fail("source-derived crossing must be visible in source mode")
        return
    if int(official.get_meta("source_rect_count", -1)) != 209:
        _fail("runtime source rectangle metadata drifted")
        return
    if absf(float(official.get_meta("source_paint_area_m2", 0.0)) - 27.625) > 0.001:
        _fail("runtime source area metadata drifted")
        return
    for stripe_index: int in range(10):
        var stripe := hero.get_node_or_null("Crosswalk_%02d" % stripe_index) as GeometryInstance3D
        if stripe == null or stripe.visible:
            _fail("generic crossing baseline not retained/hidden")
            return

    controller.call("set_arrival_planimetry_enabled", false)
    if not forecourt.visible or official.visible:
        _fail("same-world baseline toggle failed")
        return
    for stripe_index: int in range(10):
        var stripe := hero.get_node("Crosswalk_%02d" % stripe_index) as GeometryInstance3D
        if not stripe.visible:
            _fail("same-world generic crossing baseline failed")
            return

    print("MIDI_ARRIVAL_PLANIMETRY_OK source_rects=209 paint_area_m2=27.625 official_street_surfaces_preserved=true runtime_approved=false")
    quit(0)
