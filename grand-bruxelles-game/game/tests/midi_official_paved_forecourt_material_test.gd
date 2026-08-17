extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_OFFICIAL_PAVED_FORECOURT_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("production main scene missing")
        return
    var scene := packed.instantiate()
    var traffic_manager := scene.get_node_or_null("TrafficManager")
    if traffic_manager != null:
        traffic_manager.set("auto_spawn_runtime", false)
    root.add_child(scene)
    current_scene = scene
    var applied := false
    for _frame: int in range(40):
        await process_frame
        var runtime := root.get_node_or_null("MidiOfficialPavedForecourtRuntime")
        if runtime != null and bool(runtime.get("applied")):
            applied = true
            break
    if not applied:
        _fail("forecourt autoload did not apply to current production scene")
        return
    var builder := scene.get_node_or_null("UrbISMidiExact")
    if builder == null:
        _fail("UrbIS Midi exact builder missing")
        return
    if str(builder.surface_family("P", 0.0)) != "paved":
        _fail("official UrbIS P semantics drifted")
        return
    var counts := builder.surface_family_counts() as Dictionary
    if int(counts.get("paved", 0)) <= 0:
        _fail("no official street-level paved surfaces available")
        return
    var paved := builder.get_node_or_null("UrbISStreetSurfaces/ExactPavedAreas") as MeshInstance3D
    if paved == null or paved.mesh == null:
        _fail("ExactPavedAreas mesh missing")
        return
    var material := paved.mesh.surface_get_material(0)
    if not material is ShaderMaterial:
        _fail("official paved areas did not receive authored presentation shader")
        return
    if str(material.get_meta("surface_family", "")) != "urbis_official_paved_area_v1":
        _fail("official paved presentation family metadata missing")
        return
    if bool(material.get_meta("geometry_changed", true)):
        _fail("material lot must not change official geometry")
        return
    if bool(material.get_meta("paving_composition_claimed", true)):
        _fail("authored presentation must not claim surveyed paving composition")
        return
    if bool(material.get_meta("exact_rgb_is_photometric_measurement", true)):
        _fail("authored RGB must not claim photometric measurement")
        return
    print("MIDI_OFFICIAL_PAVED_FORECOURT_OK: paved_count=%d geometry_changed=false composition_claimed=false" % int(counts.get("paved", 0)))
    scene.queue_free()
    quit(0)
