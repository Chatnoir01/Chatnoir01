extends Control

## Touch-first controller for Grand Bruxelles.
## Everything is drawn with Godot Controls/StyleBoxes: no PNG dependency.

var forward_pressed: bool = false
var backward_pressed: bool = false
var left_pressed: bool = false
var right_pressed: bool = false
var sprint_pressed: bool = false
var jump_pressed: bool = false
var movement_vector: Vector2 = Vector2.ZERO

@onready var player: CharacterBody3D = get_node("../Player")

const STICK_SIZE := 156.0
const STICK_KNOB_SIZE := 66.0
const STICK_RADIUS := 58.0
const STICK_DEADZONE := 0.12
const TOUCH_LOOK_X := 0.0043
const TOUCH_LOOK_Y := 0.0035
const NEW_GAME_CONFIRM_MS := 3000

var _stick_base: Panel
var _stick_knob: Panel
var _actions: Control
var _travel_panel: Panel
var _game_panel: Panel
var _game_status: Label
var _new_game_button: Button
var _action_buttons: Array[Control] = []
var _stick_touch_id: int = -1
var _look_touch_id: int = -1
var _vehicle_view_index: int = 0
var _new_game_armed_until_ms: int = 0


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    visible = DisplayServer.is_touchscreen_available() or OS.has_feature("web")
    if not visible:
        return
    _build_controls()
    set_process_input(true)


func _process(_delta: float) -> void:
    if _game_panel != null and _game_panel.visible:
        _refresh_game_panel()
    if _new_game_button != null and _new_game_armed_until_ms > 0 and Time.get_ticks_msec() > _new_game_armed_until_ms:
        _new_game_armed_until_ms = 0
        _new_game_button.text = "NOUVELLE PARTIE"


func _build_controls() -> void:
    if _actions != null:
        return
    _stick_base = Panel.new()
    _stick_base.name = "AnalogStickBase"
    _stick_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _stick_base.anchor_top = 1.0
    _stick_base.anchor_bottom = 1.0
    _stick_base.offset_left = 28.0
    _stick_base.offset_top = -196.0
    _stick_base.offset_right = 28.0 + STICK_SIZE
    _stick_base.offset_bottom = -40.0
    _stick_base.add_theme_stylebox_override("panel", _circle_style(Color(0.05, 0.07, 0.09, 0.46), Color(0.86, 0.91, 0.95, 0.38), 2))
    add_child(_stick_base)

    _stick_knob = Panel.new()
    _stick_knob.name = "AnalogStickKnob"
    _stick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _stick_knob.size = Vector2(STICK_KNOB_SIZE, STICK_KNOB_SIZE)
    _stick_knob.add_theme_stylebox_override("panel", _circle_style(Color(0.86, 0.91, 0.95, 0.58), Color(1.0, 1.0, 1.0, 0.72), 2))
    _stick_base.add_child(_stick_knob)
    _reset_stick_knob()

    _actions = Control.new()
    _actions.name = "Actions"
    _actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _actions.anchor_left = 1.0
    _actions.anchor_top = 1.0
    _actions.anchor_right = 1.0
    _actions.anchor_bottom = 1.0
    _actions.offset_left = -300.0
    _actions.offset_top = -246.0
    _actions.offset_right = -18.0
    _actions.offset_bottom = -18.0
    add_child(_actions)

    var interact := _make_button("ENTRER", Vector2(176, 24), Vector2(92, 78))
    var jump := _make_button("SAUT", Vector2(78, 126), Vector2(82, 72))
    var sprint := _make_button("COURIR", Vector2(176, 126), Vector2(92, 72))
    var view := _make_button("VUE", Vector2(0, 40), Vector2(68, 62))
    var game := _make_button("PARTIE", Vector2(78, 40), Vector2(82, 62))
    var travel := _make_button("CARTE", Vector2(0, 132), Vector2(68, 62))
    for button: Button in [interact, jump, sprint, view, game, travel]:
        _actions.add_child(button)
        _action_buttons.append(button)

    interact.pressed.connect(_interact)
    _bind_hold(jump, "jump_pressed")
    _bind_hold(sprint, "sprint_pressed")
    view.pressed.connect(_cycle_view)
    game.pressed.connect(_toggle_game_panel)
    travel.pressed.connect(_toggle_travel_panel)
    _build_travel_panel()
    _build_game_panel()


func _build_travel_panel() -> void:
    _travel_panel = Panel.new()
    _travel_panel.name = "FastTravelPanel"
    _travel_panel.visible = false
    _travel_panel.anchor_left = 0.5
    _travel_panel.anchor_top = 0.5
    _travel_panel.anchor_right = 0.5
    _travel_panel.anchor_bottom = 0.5
    _travel_panel.offset_left = -145.0
    _travel_panel.offset_top = -118.0
    _travel_panel.offset_right = 145.0
    _travel_panel.offset_bottom = 118.0
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
    var cars := _travel_button("TEST AUTO A/B", Vector2(18, 128), Vector2(254, 54))
    var close := _travel_button("FERMER", Vector2(82, 190), Vector2(126, 34))
    _travel_panel.add_child(midi)
    _travel_panel.add_child(center)
    _travel_panel.add_child(cars)
    _travel_panel.add_child(close)
    midi.pressed.connect(_fast_travel.bind("midi"))
    center.pressed.connect(_fast_travel.bind("bourse"))
    cars.pressed.connect(_fast_travel.bind("vehicle_ab"))
    close.pressed.connect(_toggle_travel_panel)


func _build_game_panel() -> void:
    _game_panel = Panel.new()
    _game_panel.name = "GameplayPanel"
    _game_panel.visible = false
    _game_panel.anchor_left = 0.5
    _game_panel.anchor_top = 0.5
    _game_panel.anchor_right = 0.5
    _game_panel.anchor_bottom = 0.5
    _game_panel.offset_left = -180.0
    _game_panel.offset_top = -164.0
    _game_panel.offset_right = 180.0
    _game_panel.offset_bottom = 164.0
    _game_panel.add_theme_stylebox_override("panel", _rounded_style(Color(0.025, 0.035, 0.05, 0.95), Color(0.75, 0.82, 0.88, 0.38), 18, 2))
    add_child(_game_panel)
    _action_buttons.append(_game_panel)

    var title := Label.new()
    title.position = Vector2(18, 14)
    title.size = Vector2(324, 30)
    title.text = "PARTIE & MISSION"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 19)
    _game_panel.add_child(title)

    _game_status = Label.new()
    _game_status.name = "MissionStatus"
    _game_status.position = Vector2(20, 50)
    _game_status.size = Vector2(320, 92)
    _game_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _game_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _game_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _game_status.add_theme_font_size_override("font_size", 14)
    _game_panel.add_child(_game_status)

    var save := _travel_button("SAUVEGARDER", Vector2(20, 154), Vector2(152, 54))
    var load_game := _travel_button("CHARGER", Vector2(188, 154), Vector2(152, 54))
    _new_game_button = _travel_button("NOUVELLE PARTIE", Vector2(20, 220), Vector2(320, 54))
    var close := _travel_button("FERMER", Vector2(102, 286), Vector2(156, 34))
    _game_panel.add_child(save)
    _game_panel.add_child(load_game)
    _game_panel.add_child(_new_game_button)
    _game_panel.add_child(close)
    save.pressed.connect(quick_save_from_ui)
    load_game.pressed.connect(quick_load_from_ui)
    _new_game_button.pressed.connect(_request_new_game)
    close.pressed.connect(_toggle_game_panel)


func _refresh_game_panel() -> void:
    if _game_status == null:
        return
    var mission_label := get_node_or_null("../MissionLabel") as Label
    var wallet_label := get_node_or_null("../WalletLabel") as Label
    var mission_text := mission_label.text if mission_label != null else "Mission indisponible"
    var wallet_text := wallet_label.text if wallet_label != null else ""
    _game_status.text = "%s\nSOLDE · %s" % [mission_text, wallet_text]


func _circle_style(fill: Color, border: Color, width: int) -> StyleBoxFlat:
    return _rounded_style(fill, border, 999, width)


func _rounded_style(fill: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = fill
    style.border_color = border
    style.set_border_width_all(width)
    style.corner_radius_top_left = radius
    style.corner_radius_top_right = radius
    style.corner_radius_bottom_left = radius
    style.corner_radius_bottom_right = radius
    return style


func _make_button(label: String, pos: Vector2, button_size: Vector2) -> Button:
    var button := Button.new()
    button.text = label
    button.position = pos
    button.size = button_size
    button.custom_minimum_size = button_size
    button.focus_mode = Control.FOCUS_NONE
    button.add_theme_font_size_override("font_size", 15)
    button.add_theme_stylebox_override("normal", _rounded_style(Color(0.05, 0.07, 0.09, 0.60), Color(0.88, 0.92, 0.95, 0.40), 22, 2))
    button.add_theme_stylebox_override("pressed", _rounded_style(Color(0.22, 0.35, 0.48, 0.82), Color(1.0, 1.0, 1.0, 0.72), 22, 2))
    return button


func _travel_button(label: String, pos: Vector2, button_size: Vector2 = Vector2(122, 54)) -> Button:
    var button := _make_button(label, pos, button_size)
    button.add_theme_font_size_override("font_size", 13)
    return button


func _bind_hold(button: Button, property_name: String) -> void:
    button.button_down.connect(_set_hold.bind(property_name, true))
    button.button_up.connect(_set_hold.bind(property_name, false))
    button.mouse_exited.connect(_release_if_needed.bind(property_name))


func _set_hold(property_name: String, pressed: bool) -> void:
    set(property_name, pressed)


func _release_if_needed(property_name: String) -> void:
    set(property_name, false)


func _input(event: InputEvent) -> void:
    if not visible:
        return
    if event is InputEventScreenTouch:
        var touch := event as InputEventScreenTouch
        if not touch.pressed:
            if touch.index == _stick_touch_id:
                _release_stick()
            if touch.index == _look_touch_id:
                _look_touch_id = -1
            return
        if _modal_panel_open():
            return
        if _stick_touch_id < 0 and _stick_capture_rect().has_point(touch.position):
            _stick_touch_id = touch.index
            _update_stick(touch.position)
            return
        if _look_touch_id < 0 and touch.position.x > get_viewport_rect().size.x * 0.36 and not _point_over_actions(touch.position):
            _look_touch_id = touch.index
            return

    if event is InputEventScreenDrag:
        var drag := event as InputEventScreenDrag
        if drag.index == _stick_touch_id:
            _update_stick(drag.position)
        elif drag.index == _look_touch_id:
            _apply_touch_look(drag.relative)


func _modal_panel_open() -> bool:
    return (_travel_panel != null and _travel_panel.visible) or (_game_panel != null and _game_panel.visible)


func _stick_capture_rect() -> Rect2:
    if _stick_base == null:
        return Rect2()
    return _stick_base.get_global_rect().grow(28.0)


func _update_stick(screen_position: Vector2) -> void:
    var rect := _stick_base.get_global_rect()
    var center := rect.get_center()
    var delta := screen_position - center
    var clamped := delta.limit_length(STICK_RADIUS)
    var normalized := clamped / STICK_RADIUS
    if normalized.length() < STICK_DEADZONE:
        normalized = Vector2.ZERO
    movement_vector = normalized
    _stick_knob.position = Vector2(STICK_SIZE * 0.5 - STICK_KNOB_SIZE * 0.5, STICK_SIZE * 0.5 - STICK_KNOB_SIZE * 0.5) + clamped
    _sync_legacy_direction_flags()


func _release_stick() -> void:
    _stick_touch_id = -1
    movement_vector = Vector2.ZERO
    _sync_legacy_direction_flags()
    _reset_stick_knob()


func _reset_stick_knob() -> void:
    if _stick_knob == null:
        return
    _stick_knob.position = Vector2(STICK_SIZE * 0.5 - STICK_KNOB_SIZE * 0.5, STICK_SIZE * 0.5 - STICK_KNOB_SIZE * 0.5)


func _sync_legacy_direction_flags() -> void:
    left_pressed = movement_vector.x < -0.22
    right_pressed = movement_vector.x > 0.22
    forward_pressed = movement_vector.y < -0.22
    backward_pressed = movement_vector.y > 0.22


func get_movement_vector() -> Vector2:
    return movement_vector


func _point_over_actions(point: Vector2) -> bool:
    for control: Control in _action_buttons:
        if control.visible and control.get_global_rect().has_point(point):
            return true
    return false


func _apply_touch_look(relative: Vector2) -> void:
    var driven_vehicle := _driven_vehicle()
    if driven_vehicle != null:
        var pivot := driven_vehicle.get_node_or_null("CameraPivot") as Node3D
        if pivot != null:
            pivot.rotate_y(-relative.x * TOUCH_LOOK_X)
            pivot.rotate_x(-relative.y * TOUCH_LOOK_Y)
            pivot.rotation.y = clampf(pivot.rotation.y, -1.55, 1.55)
            pivot.rotation.x = clampf(pivot.rotation.x, deg_to_rad(-34.0), deg_to_rad(24.0))
        return
    if player == null:
        return
    player.rotate_y(-relative.x * TOUCH_LOOK_X)
    var pivot := player.get_node_or_null("CameraPivot") as Node3D
    if pivot != null:
        pivot.rotate_x(-relative.y * TOUCH_LOOK_Y)
        pivot.rotation.x = clampf(pivot.rotation.x, deg_to_rad(-60.0), deg_to_rad(35.0))


func _driven_vehicle() -> Node3D:
    for candidate: Node in get_tree().get_nodes_in_group("vehicle"):
        if candidate is Node3D and candidate.has_method("has_driver") and bool(candidate.call("has_driver")):
            return candidate as Node3D
    return null


func _interact() -> void:
    var driven_vehicle := _driven_vehicle()
    if driven_vehicle != null and driven_vehicle.has_method("exit_driver"):
        driven_vehicle.call("exit_driver")
        return
    if player != null and player.has_method("try_enter_vehicle"):
        player.call("try_enter_vehicle")


func _cycle_view() -> void:
    var driven_vehicle := _driven_vehicle()
    if driven_vehicle != null:
        var arm := driven_vehicle.get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
        var vehicle_camera := driven_vehicle.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
        if arm != null:
            var distances: Array[float] = [6.1, 3.8, 8.2]
            var fovs: Array[float] = [72.0, 76.0, 66.0]
            _vehicle_view_index = (_vehicle_view_index + 1) % distances.size()
            arm.spring_length = distances[_vehicle_view_index]
            if vehicle_camera != null:
                vehicle_camera.fov = fovs[_vehicle_view_index]
        return
    if player != null and player.has_method("cycle_camera_view"):
        player.call("cycle_camera_view")


func _toggle_travel_panel() -> void:
    if _travel_panel == null:
        return
    var opening := not _travel_panel.visible
    _travel_panel.visible = opening
    if opening:
        if _game_panel != null:
            _game_panel.visible = false
        _release_stick()
        _look_touch_id = -1


func _toggle_game_panel() -> void:
    if _game_panel == null:
        return
    var opening := not _game_panel.visible
    _game_panel.visible = opening
    if opening:
        if _travel_panel != null:
            _travel_panel.visible = false
        _release_stick()
        _look_touch_id = -1
        _refresh_game_panel()
    else:
        _new_game_armed_until_ms = 0
        if _new_game_button != null:
            _new_game_button.text = "NOUVELLE PARTIE"


func _fast_travel(destination: String) -> void:
    if player != null and player.has_method("fast_travel_to"):
        player.call("fast_travel_to", destination)
    if _travel_panel != null:
        _travel_panel.visible = false


func quick_save_from_ui() -> bool:
    var quick_save := get_node_or_null("../MissionQuickSave")
    if quick_save == null or not quick_save.has_method("quick_save"):
        return false
    var result := bool(quick_save.call("quick_save"))
    _refresh_game_panel()
    return result


func quick_load_from_ui() -> bool:
    var quick_save := get_node_or_null("../MissionQuickSave")
    if quick_save == null or not quick_save.has_method("quick_load"):
        return false
    var result := bool(quick_save.call("quick_load"))
    _refresh_game_panel()
    return result


func _request_new_game() -> void:
    var now := Time.get_ticks_msec()
    if _new_game_armed_until_ms <= now:
        _new_game_armed_until_ms = now + NEW_GAME_CONFIRM_MS
        if _new_game_button != null:
            _new_game_button.text = "CONFIRMER · TOUT RECOMMENCER"
        return
    restart_campaign_from_ui()
    _new_game_armed_until_ms = 0
    if _new_game_button != null:
        _new_game_button.text = "NOUVELLE PARTIE"


func restart_campaign_from_ui() -> bool:
    var autosave := get_node_or_null("../MissionCheckpointAutosave")
    var wallet := get_node_or_null("../Wallet")
    var mission := get_node_or_null("../MissionDriveToCenter")
    var return_mission := get_node_or_null("../MissionReturnToBourse")
    if autosave == null or wallet == null or mission == null or return_mission == null:
        return false
    if not autosave.has_method("clear_autosave") or not bool(autosave.call("clear_autosave")):
        return false
    if wallet.has_method("reset"):
        wallet.call("reset")
    if mission.has_method("restart_mission"):
        mission.call("restart_mission")
    if return_mission.has_method("restart_campaign"):
        return_mission.call("restart_campaign")
    _refresh_game_panel()
    return true


func ensure_gameplay_controls_for_test() -> void:
    visible = true
    if _actions == null:
        _build_controls()
    set_process_input(true)


func open_gameplay_panel_for_test() -> void:
    ensure_gameplay_controls_for_test()
    if _game_panel != null and not _game_panel.visible:
        _toggle_game_panel()


func gameplay_panel_state_for_test() -> Dictionary:
    return {
        "built": _game_panel != null,
        "visible": _game_panel != null and _game_panel.visible,
        "status": _game_status.text if _game_status != null else "",
        "new_game_label": _new_game_button.text if _new_game_button != null else "",
    }
