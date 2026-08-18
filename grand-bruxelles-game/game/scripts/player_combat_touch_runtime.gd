extends Node

# Touch-only bridge for the combat arsenal. It stays independent from the existing
# movement controls so combat can evolve without destabilising mobile locomotion.

const WEAPON_CYCLE: Array[StringName] = [&"", &"bx9", &"cbr4", &"sct8"]
const WEAPON_LABELS: Dictionary = {
    &"bx9": "BX-9",
    &"cbr4": "CBR-4",
    &"sct8": "SCT-8",
}
const HOLD_RETRY_MS := 45

var _layer: CanvasLayer = null
var _panel: Panel = null
var _mode_button: Button = null
var _action_button: Button = null
var _aim_button: Button = null
var _reload_button: Button = null
var _status_label: Label = null
var _action_held := false
var _next_hold_retry_ms := 0

func _ready() -> void:
    set_process(true)
    call_deferred("_build_if_touch")

func _process(_delta: float) -> void:
    if _panel == null or not is_instance_valid(_panel):
        return
    var arsenal := _arsenal()
    var player := _current_player()
    if arsenal == null or player == null:
        _panel.visible = false
        return
    _panel.visible = true
    _refresh_labels(arsenal)
    if not _action_held:
        return
    var now := Time.get_ticks_msec()
    if now < _next_hold_retry_ms:
        return
    _next_hold_retry_ms = now + HOLD_RETRY_MS
    _perform_primary_action(arsenal, player)

func _build_if_touch() -> void:
    if not DisplayServer.is_touchscreen_available():
        return
    if _panel != null:
        return

    _layer = CanvasLayer.new()
    _layer.name = "CombatTouchLayer"
    _layer.layer = 31
    add_child(_layer)

    _panel = Panel.new()
    _panel.name = "CombatTouchPanel"
    _panel.anchor_left = 1.0
    _panel.anchor_top = 1.0
    _panel.anchor_right = 1.0
    _panel.anchor_bottom = 1.0
    _panel.offset_left = -364.0
    _panel.offset_top = -382.0
    _panel.offset_right = -18.0
    _panel.offset_bottom = -264.0
    _panel.mouse_filter = Control.MOUSE_FILTER_STOP
    _panel.add_theme_stylebox_override("panel", _panel_style())
    _layer.add_child(_panel)

    _status_label = Label.new()
    _status_label.name = "CombatTouchStatus"
    _status_label.position = Vector2(10.0, 6.0)
    _status_label.size = Vector2(326.0, 24.0)
    _status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _status_label.add_theme_font_size_override("font_size", 14)
    _panel.add_child(_status_label)

    _mode_button = _make_button("MODE", Vector2(8.0, 34.0), Vector2(78.0, 72.0))
    _action_button = _make_button("FRAPPER", Vector2(94.0, 34.0), Vector2(92.0, 72.0))
    _aim_button = _make_button("VISER", Vector2(194.0, 34.0), Vector2(72.0, 72.0))
    _reload_button = _make_button("RECH.", Vector2(274.0, 34.0), Vector2(64.0, 72.0))
    _panel.add_child(_mode_button)
    _panel.add_child(_action_button)
    _panel.add_child(_aim_button)
    _panel.add_child(_reload_button)

    _mode_button.pressed.connect(_cycle_weapon)
    _aim_button.pressed.connect(_toggle_aim)
    _reload_button.pressed.connect(_request_reload)
    _action_button.button_down.connect(_primary_down)
    _action_button.button_up.connect(_primary_up)
    _action_button.mouse_exited.connect(_primary_up)

func _panel_style() -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.025, 0.035, 0.05, 0.78)
    style.border_color = Color(0.82, 0.87, 0.92, 0.34)
    style.set_border_width_all(2)
    style.corner_radius_top_left = 18
    style.corner_radius_top_right = 18
    style.corner_radius_bottom_left = 18
    style.corner_radius_bottom_right = 18
    return style

func _make_button(text_value: String, pos: Vector2, size_value: Vector2) -> Button:
    var button := Button.new()
    button.text = text_value
    button.position = pos
    button.size = size_value
    button.custom_minimum_size = size_value
    button.focus_mode = Control.FOCUS_NONE
    button.add_theme_font_size_override("font_size", 14)
    var normal := StyleBoxFlat.new()
    normal.bg_color = Color(0.07, 0.09, 0.12, 0.88)
    normal.border_color = Color(0.88, 0.92, 0.95, 0.48)
    normal.set_border_width_all(2)
    normal.corner_radius_top_left = 20
    normal.corner_radius_top_right = 20
    normal.corner_radius_bottom_left = 20
    normal.corner_radius_bottom_right = 20
    button.add_theme_stylebox_override("normal", normal)
    var pressed := normal.duplicate() as StyleBoxFlat
    pressed.bg_color = Color(0.24, 0.36, 0.50, 0.95)
    pressed.border_color = Color(1.0, 1.0, 1.0, 0.78)
    button.add_theme_stylebox_override("pressed", pressed)
    return button

func _cycle_weapon() -> void:
    var arsenal := _arsenal()
    var player := _current_player()
    if arsenal == null or player == null:
        return
    var current := StringName(arsenal.call("equipped_weapon"))
    var index := WEAPON_CYCLE.find(current)
    var next_index := 0 if index < 0 else (index + 1) % WEAPON_CYCLE.size()
    arsenal.call("equip_weapon", player, WEAPON_CYCLE[next_index])
    _refresh_labels(arsenal)

func _toggle_aim() -> void:
    var arsenal := _arsenal()
    var player := _current_player()
    if arsenal == null or player == null or not bool(arsenal.call("is_armed")):
        return
    var next_aim := not bool(player.get_meta("combat_weapon_aiming", false))
    arsenal.set("_aiming", next_aim)
    player.set_meta("combat_weapon_aiming", next_aim)
    if arsenal.has_method("_refresh_hud"):
        arsenal.call("_refresh_hud", player)
    _refresh_labels(arsenal)

func _request_reload() -> void:
    var arsenal := _arsenal()
    var player := _current_player()
    if arsenal == null or player == null:
        return
    arsenal.call("request_reload", player)

func _primary_down() -> void:
    _action_held = true
    _next_hold_retry_ms = 0
    var arsenal := _arsenal()
    var player := _current_player()
    if arsenal != null and player != null:
        _perform_primary_action(arsenal, player)

func _primary_up() -> void:
    _action_held = false

func _perform_primary_action(arsenal: Node, player: CharacterBody3D) -> void:
    if bool(arsenal.call("is_armed")):
        arsenal.call("request_fire", player)
    else:
        arsenal.call("request_melee_combo", player)

func _refresh_labels(arsenal: Node) -> void:
    if _action_button == null or _mode_button == null or _aim_button == null or _reload_button == null or _status_label == null:
        return
    var armed := bool(arsenal.call("is_armed"))
    if not armed:
        _status_label.text = "COMBAT · MAINS NUES"
        _action_button.text = "FRAPPER"
        _aim_button.text = "VISER"
        _aim_button.disabled = true
        _reload_button.disabled = true
        _mode_button.text = "ARME"
        return
    var weapon_id := StringName(arsenal.call("equipped_weapon"))
    var label := String(WEAPON_LABELS.get(weapon_id, String(weapon_id).to_upper()))
    var ammo_variant: Variant = arsenal.call("ammo_state", weapon_id)
    var mag := 0
    var reserve := 0
    if ammo_variant is Dictionary:
        mag = int((ammo_variant as Dictionary).get("mag", 0))
        reserve = int((ammo_variant as Dictionary).get("reserve", 0))
    var player := _current_player()
    var aiming := player != null and bool(player.get_meta("combat_weapon_aiming", false))
    _status_label.text = "%s · %d/%d%s" % [label, mag, reserve, " · VISÉE" if aiming else ""]
    _action_button.text = "TIR"
    _aim_button.text = "VISÉE" if aiming else "VISER"
    _aim_button.disabled = false
    _reload_button.disabled = false
    _mode_button.text = "CHANGER"

func _arsenal() -> Node:
    return get_node_or_null("/root/PlayerCombatArsenalRuntime")

func _current_player() -> CharacterBody3D:
    var scene := get_tree().current_scene
    if scene == null:
        return null
    return scene.get_node_or_null("Player") as CharacterBody3D
