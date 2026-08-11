extends Control

var forward_pressed: bool = false
var backward_pressed: bool = false
var left_pressed: bool = false
var right_pressed: bool = false
var sprint_pressed: bool = false
var jump_pressed: bool = false

@onready var player: CharacterBody3D = get_node("../Player")
@onready var car: CharacterBody3D = get_node("../PrototypeCar")

var _dpad: Control
var _actions: Control


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    visible = DisplayServer.is_touchscreen_available() or OS.has_feature("web")
    if not visible:
        return
    _build_controls()


func _build_controls() -> void:
    _dpad = Control.new()
    _dpad.name = "DPad"
    _dpad.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _dpad.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
    _dpad.position = Vector2(24.0, -230.0)
    add_child(_dpad)

    _actions = Control.new()
    _actions.name = "Actions"
    _actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _actions.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    _actions.position = Vector2(-250.0, -215.0)
    add_child(_actions)

    var up := _make_button("▲", Vector2(76, 0), Vector2(72, 72))
    var left := _make_button("◀", Vector2(0, 76), Vector2(72, 72))
    var down := _make_button("▼", Vector2(76, 76), Vector2(72, 72))
    var right := _make_button("▶", Vector2(152, 76), Vector2(72, 72))
    _dpad.add_child(up)
    _dpad.add_child(left)
    _dpad.add_child(down)
    _dpad.add_child(right)
    _bind_hold(up, "forward_pressed")
    _bind_hold(down, "backward_pressed")
    _bind_hold(left, "left_pressed")
    _bind_hold(right, "right_pressed")

    var interact := _make_button("E", Vector2(90, 5), Vector2(82, 82))
    var jump := _make_button("SAUT", Vector2(0, 95), Vector2(82, 70))
    var sprint := _make_button("RUN", Vector2(100, 100), Vector2(82, 70))
    _actions.add_child(interact)
    _actions.add_child(jump)
    _actions.add_child(sprint)
    interact.pressed.connect(_interact)
    _bind_hold(jump, "jump_pressed")
    _bind_hold(sprint, "sprint_pressed")


func _make_button(label: String, pos: Vector2, button_size: Vector2) -> Button:
    var button := Button.new()
    button.text = label
    button.position = pos
    button.size = button_size
    button.custom_minimum_size = button_size
    button.focus_mode = Control.FOCUS_NONE
    button.modulate = Color(1.0, 1.0, 1.0, 0.78)
    button.add_theme_font_size_override("font_size", 20)
    return button


func _bind_hold(button: Button, property_name: String) -> void:
    button.button_down.connect(_set_hold.bind(property_name, true))
    button.button_up.connect(_set_hold.bind(property_name, false))
    button.mouse_exited.connect(_release_if_needed.bind(property_name))


func _set_hold(property_name: String, pressed: bool) -> void:
    set(property_name, pressed)


func _release_if_needed(property_name: String) -> void:
    set(property_name, false)


func _interact() -> void:
    if car.has_method("has_driver") and bool(car.call("has_driver")):
        car.call("exit_driver")
    elif player.has_method("try_enter_vehicle"):
        player.call("try_enter_vehicle")
