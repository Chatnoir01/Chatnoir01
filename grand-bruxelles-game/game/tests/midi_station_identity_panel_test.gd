extends SceneTree

const MIDI_HERO_SCRIPT := preload("res://game/scripts/midi_hero_zone.gd")
const EXPECTED_FR := "BRUXELLES-MIDI"
const EXPECTED_NL := "BRUSSEL-ZUID"


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("MIDI_STATION_IDENTITY_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var hero := MIDI_HERO_SCRIPT.new()
    root.add_child(hero)
    await process_frame

    var entrance := hero.get_node_or_null("MidiMainEntranceFonsny") as Node3D
    if entrance == null:
        _fail("production Fonsny entrance missing")
        return

    var panel := entrance.get_node_or_null("StationIdentityPanel") as MeshInstance3D
    if panel == null:
        _fail("physical station identity panel missing")
        return
    if not panel.mesh is BoxMesh:
        _fail("identity panel must have a physical backing mesh")
        return
    var panel_size := (panel.mesh as BoxMesh).size
    if panel_size.z < 8.0 or panel_size.y < 1.0:
        _fail("identity panel is too small to be a meaningful station-scale cue")
        return

    var fr := entrance.get_node_or_null("StationIdentityPanel/StationIdentityFR") as Label3D
    var nl := entrance.get_node_or_null("StationIdentityPanel/StationIdentityNL") as Label3D
    if fr == null or nl == null:
        _fail("bilingual station identity labels missing")
        return
    if fr.text != EXPECTED_FR or nl.text != EXPECTED_NL:
        _fail("bilingual station names drifted")
        return
    if fr.billboard != BaseMaterial3D.BILLBOARD_DISABLED or nl.billboard != BaseMaterial3D.BILLBOARD_DISABLED:
        _fail("station identity must be physically mounted, not a floating billboard")
        return

    if str(panel.get_meta("source_station_identity", "")) != "SNCB/NMBS Bruxelles-Midi / Brussel-Zuid":
        _fail("official station identity provenance marker missing")
        return
    if bool(panel.get_meta("surveyed_panel_dimensions", true)):
        _fail("authored panel dimensions must not be claimed as surveyed")
        return
    if bool(panel.get_meta("sncb_logo_artwork_embedded", true)):
        _fail("no SNCB/NMBS logo artwork may be embedded")
        return

    if entrance.get_node_or_null("StationName") != null:
        _fail("legacy floating station-name billboard must be removed")
        return

    print("MIDI_STATION_IDENTITY_OK: physical bilingual panel present and provenance-bounded")
    quit(0)
