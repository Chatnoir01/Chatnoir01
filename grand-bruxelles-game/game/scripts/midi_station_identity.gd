extends Node

const SOURCE_PATH := "res://data/visual/midi_station_identity.json"
const FRENCH_NAME := "BRUXELLES-MIDI"
const DUTCH_NAME := "BRUSSEL-ZUID"

var _entrance: Node3D
var _legacy_label: Label3D
var _fr_label: Label3D
var _nl_label: Label3D
var _attached := false

func _ready() -> void:
    call_deferred("_attach_when_ready")

func _attach_when_ready() -> void:
    for _attempt: int in range(30):
        var main := get_tree().root.get_node_or_null("Main")
        if main != null:
            var hero := main.get_node_or_null("MidiHeroZone")
            if hero != null:
                var entrance := hero.get_node_or_null("MidiMainEntranceFonsny") as Node3D
                if entrance != null:
                    _attach_to_entrance(entrance)
                    return
        await get_tree().process_frame
    push_warning("MIDI_STATION_IDENTITY_WAIT: Fonsny entrance not available")

func _attach_to_entrance(entrance: Node3D) -> void:
    if _attached:
        return
    _entrance = entrance
    _legacy_label = entrance.get_node_or_null("StationName") as Label3D

    _fr_label = _make_identity_label("StationNameFR", FRENCH_NAME, 3.55)
    _nl_label = _make_identity_label("StationNameNL", DUTCH_NAME, 1.95)
    entrance.add_child(_fr_label)
    entrance.add_child(_nl_label)

    entrance.set_meta("station_identity_source", SOURCE_PATH)
    entrance.set_meta("station_identity_text_source_backed", true)
    entrance.set_meta("station_identity_geometry_changed", false)
    entrance.set_meta("station_identity_new_material_claim", false)
    entrance.set_meta("station_identity_runtime_approved", false)
    entrance.set_meta("station_identity_realism_complete", false)
    _attached = true
    set_station_identity_visible(true)
    print("MIDI_STATION_IDENTITY_READY: Bruxelles-Midi / Brussel-Zuid on existing Fonsny entrance")

func _make_identity_label(node_name: String, text_value: String, local_y: float) -> Label3D:
    var label := Label3D.new()
    label.name = node_name
    label.text = text_value
    label.font_size = 92
    label.outline_size = 10
    label.pixel_size = 0.018
    label.modulate = Color(0.96, 0.96, 0.92, 1.0)
    label.outline_modulate = Color(0.035, 0.055, 0.075, 0.98)
    label.position = Vector3(-15.30, local_y, -0.6)
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.no_depth_test = false
    return label

func set_station_identity_visible(enabled: bool) -> void:
    if not _attached:
        return
    _fr_label.visible = enabled
    _nl_label.visible = enabled
    if _legacy_label != null:
        _legacy_label.visible = not enabled

func station_identity_visible() -> bool:
    return _attached and _fr_label != null and _nl_label != null and _fr_label.visible and _nl_label.visible

func station_identity_attached() -> bool:
    return _attached
