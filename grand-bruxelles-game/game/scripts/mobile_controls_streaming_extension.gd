extends "res://game/scripts/mobile_controls.gd"

## Adds the first streamed Brussels district to the existing touch-first CARTE UI.
## The base joystick/camera/gameplay controls remain unchanged.

func _build_travel_panel() -> void:
    _travel_panel = Panel.new()
    _travel_panel.name = "FastTravelPanel"
    _travel_panel.visible = false
    _travel_panel.anchor_left = 0.5
    _travel_panel.anchor_top = 0.5
    _travel_panel.anchor_right = 0.5
    _travel_panel.anchor_bottom = 0.5
    _travel_panel.offset_left = -145.0
    _travel_panel.offset_top = -154.0
    _travel_panel.offset_right = 145.0
    _travel_panel.offset_bottom = 154.0
    _travel_panel.add_theme_stylebox_override("panel", _rounded_style(Color(0.025, 0.035, 0.05, 0.92), Color(0.75, 0.82, 0.88, 0.35), 18, 2))
    add_child(_travel_panel)
    _action_buttons.append(_travel_panel)

    var title := Label.new()
    title.position = Vector2(18, 14)
    title.size = Vector2(254, 30)
    title.text = "DÉPLACEMENT RAPIDE"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 18)
    _travel_panel.add_child(title)

    var midi := _travel_button("MIDI / ZUID", Vector2(18, 58))
    var center := _travel_button("CENTRE / BOURSE", Vector2(150, 58))
    var ixelles := _travel_button("IXELLES / ELSENE", Vector2(18, 128), Vector2(254, 54))
    var cars := _travel_button("TEST AUTO A/B", Vector2(18, 194), Vector2(254, 54))
    var close := _travel_button("FERMER", Vector2(82, 260), Vector2(126, 34))
    _travel_panel.add_child(midi)
    _travel_panel.add_child(center)
    _travel_panel.add_child(ixelles)
    _travel_panel.add_child(cars)
    _travel_panel.add_child(close)
    midi.pressed.connect(_fast_travel.bind("midi"))
    center.pressed.connect(_fast_travel.bind("bourse"))
    ixelles.pressed.connect(_fast_travel.bind("ixelles"))
    cars.pressed.connect(_fast_travel.bind("vehicle_ab"))
    close.pressed.connect(_toggle_travel_panel)

func _fast_travel(destination: String) -> void:
    var key := destination.strip_edges().to_lower()
    if key == "ixelles":
        var streamer := get_node_or_null("../BrusselsWorldStreamer")
        if streamer != null and streamer.has_method("request_ixelles_fast_travel") and player != null:
            streamer.call("request_ixelles_fast_travel", player)
        if _travel_panel != null:
            _travel_panel.visible = false
        return
    super._fast_travel(destination)
