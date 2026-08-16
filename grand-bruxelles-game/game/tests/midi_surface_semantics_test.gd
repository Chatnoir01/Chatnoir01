extends SceneTree

const RUNTIME_PATH := "res://data/urbis/midi/midi_runtime.game.json"


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("production main scene did not load")
        return
    var scene := packed.instantiate()
    var traffic_manager := scene.get_node_or_null("TrafficManager")
    if traffic_manager != null:
        traffic_manager.set("auto_spawn_runtime", false)
    root.add_child(scene)
    await process_frame
    var builder := scene.get_node_or_null("UrbISMidiExact")
    if builder == null:
        _fail("production UrbIS Midi builder is missing")
        return
    var expectations := {
        "S": "road",
        "I": "road",
        "IC": "road",
        "SC": "road",
        "C": "road",
        "K": "road",
        "M": "island",
        "SW": "sidewalk",
        "P": "paved",
    }
    for surface_type: String in expectations:
        var actual := str(builder.surface_family(surface_type, 0.0))
        if actual != expectations[surface_type]:
            _fail("%s mapped to %s instead of %s" % [surface_type, actual, expectations[surface_type]])
            return
    if str(builder.surface_family("MS", -1.0)) != "hidden_level":
        _fail("underground metro station must not be rendered at street level")
        return
    if str(builder.surface_family("S", -1.0)) != "hidden_level":
        _fail("underground road surface must not be rendered at street level")
        return
    var counts := builder.surface_family_counts() as Dictionary
    if int(counts.get("hidden_level", -1)) != 8:
        _fail("production scene must hide the eight non-surface-level polygons")
        return
    if int(counts.get("road", 0)) <= 300 or int(counts.get("sidewalk", 0)) <= 500:
        _fail("production official road/sidewalk coverage is unexpectedly narrow")
        return

    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RUNTIME_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("production Midi runtime is invalid")
        return
    var runtime := parsed as Dictionary
    if str(runtime.get("accuracy", {}).get("street_surface_levels", "")) != "official_urbis":
        _fail("production runtime does not declare official surface levels")
        return
    var metro_level: Variant = null
    for surface: Dictionary in runtime.get("street_surfaces", []):
        if str(surface.get("id", "")) == "https://databrussels.be/id/streetsurface/38558":
            metro_level = surface.get("level")
            break
    if metro_level == null or not is_equal_approx(float(metro_level), -1.0):
        _fail("Gare du Midi metro footprint lost its official LVL=-1")
        return

    print("MIDI_SURFACE_SEMANTICS_OK")
    scene.queue_free()
    quit(0)


func _fail(message: String) -> void:
    push_error("MIDI_SURFACE_SEMANTICS_FAIL: %s" % message)
    quit(1)
