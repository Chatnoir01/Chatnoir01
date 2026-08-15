extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var packed := load(MAIN_SCENE) as PackedScene
    if packed == null:
        _fail("main scene must load")
        return
    var world := packed.instantiate()
    get_root().add_child(world)
    await process_frame

    var midi := world.get_node_or_null("MidiHeroZone") as Node3D
    if midi == null:
        _fail("MidiHeroZone must exist in runtime")
        return

    var wayfinding := midi.get_node_or_null("MidiMobilityWayfinding") as Node3D
    if wayfinding == null:
        _fail("Midi forecourt needs a visible multimodal wayfinding anchor")
        return

    for label_name: String in ["WayfindingRail", "WayfindingUrbanTransit", "WayfindingStreetModes"]:
        var label := wayfinding.get_node_or_null(label_name) as Label3D
        if label == null or label.text.strip_edges().is_empty():
            _fail("missing readable wayfinding label: " + label_name)
            return

    var racks := midi.get_node_or_null("MidiBikeRackCluster") as Node3D
    if racks == null or racks.get_child_count() < 5:
        _fail("station arrival needs a deterministic bike-rack cluster")
        return

    var taxi := midi.get_node_or_null("MidiTaxiRankMarker") as Node3D
    if taxi == null:
        _fail("station arrival needs a street-mode/taxi marker")
        return

    var station_entrance := midi.get_node_or_null("MidiMainEntranceFonsny") as Node3D
    if station_entrance == null:
        _fail("existing Fonsny entrance must remain intact")
        return

    print("MIDI_MULTIMODAL_ARRIVAL_OK")
    world.queue_free()
    await process_frame
    quit(0)

func _fail(message: String) -> void:
    push_error("MIDI_MULTIMODAL_ARRIVAL_FAIL: " + message)
    quit(1)
