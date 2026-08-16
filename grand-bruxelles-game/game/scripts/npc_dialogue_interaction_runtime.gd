extends CanvasLayer

const CATALOG_PATH := "res://data/npc/dialogue/midi_resident.game.json"
const SESSION_SCRIPT := preload("res://game/scripts/npc_llm_session.gd")
const CATALOG_SCRIPT := preload("res://game/scripts/npc_dialogue_catalog.gd")
const TALK_RANGE := 6.0
const NAMES := ["Nora", "Samir", "Yasmine", "Mehdi", "Sofia", "Rayan", "Lina", "Amine"]

var _catalog
var _sessions: Dictionary = {}
var _active_npc: Node3D = null
var _active_anchor := Vector3.ZERO
var _panel: PanelContainer
var _talk_button: Button
var _title: Label
var _response: Label
var _source: Label
var _input: LineEdit
var _send: Button
var _busy := false
var _event_serial := 0

func _ready() -> void:
    layer = 116
    process_mode = Node.PROCESS_MODE_ALWAYS
    process_priority = 100
    _load_catalog()
    _build_ui()

func _load_catalog() -> void:
    _catalog = CATALOG_SCRIPT.new()
    if not _catalog.load_from_file(CATALOG_PATH):
        push_error("NPC dialogue catalog unavailable: %s" % _catalog.last_error)

func _build_ui() -> void:
    _talk_button = Button.new()
    _talk_button.name = "NpcTalkButton"
    _talk_button.text = "PARLER  [T]"
    _talk_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    _talk_button.position = Vector2(-178.0, -82.0)
    _talk_button.size = Vector2(158.0, 48.0)
    _talk_button.visible = false
    _talk_button.pressed.connect(_open_nearest)
    add_child(_talk_button)

    _panel = PanelContainer.new()
    _panel.name = "NpcDialoguePanel"
    _panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
    _panel.position = Vector2(22.0, -260.0)
    _panel.size = Vector2(520.0, 228.0)
    _panel.visible = false
    add_child(_panel)

    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 8)
    _panel.add_child(box)

    _title = Label.new()
    _title.name = "NpcDialogueTitle"
    _title.text = "PNJ"
    _title.add_theme_font_size_override("font_size", 21)
    box.add_child(_title)

    _response = Label.new()
    _response.name = "NpcDialogueResponse"
    _response.text = "…"
    _response.custom_minimum_size = Vector2(480.0, 54.0)
    _response.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _response.add_theme_font_size_override("font_size", 18)
    box.add_child(_response)

    _source = Label.new()
    _source.name = "NpcDialogueSource"
    _source.text = "BAKE OFFLINE"
    box.add_child(_source)

    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    box.add_child(row)

    _input = LineEdit.new()
    _input.name = "NpcDialogueInput"
    _input.placeholder_text = "Parle au PNJ…"
    _input.custom_minimum_size = Vector2(350.0, 42.0)
    _input.max_length = 320
    _input.text_submitted.connect(func(_text: String) -> void: _send_turn())
    row.add_child(_input)

    _send = Button.new()
    _send.name = "NpcDialogueSend"
    _send.text = "ENVOYER"
    _send.custom_minimum_size = Vector2(110.0, 42.0)
    _send.pressed.connect(_send_turn)
    row.add_child(_send)

    var close := Button.new()
    close.name = "NpcDialogueClose"
    close.text = "FERMER"
    close.pressed.connect(close_dialogue)
    box.add_child(close)

func _process(_delta: float) -> void:
    if _active_npc != null and is_instance_valid(_active_npc) and bool(_active_npc.get_meta("dialogue_hold", false)):
        _active_npc.global_position = _active_anchor
    if _talk_button != null and not _panel.visible:
        _talk_button.visible = nearest_talkable() != null

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_T:
        if _panel.visible:
            close_dialogue()
        else:
            _open_nearest()
        get_viewport().set_input_as_handled()

func nearest_talkable() -> Node3D:
    var main := get_tree().current_scene
    if main == null:
        return null
    var player := main.get_node_or_null("Player") as Node3D
    if player == null:
        return null
    var nearest: Node3D = null
    var best := TALK_RANGE
    for raw: Node in get_tree().get_nodes_in_group("ambient_pedestrian"):
        var pedestrian := raw as Node3D
        if pedestrian == null or not pedestrian.is_inside_tree():
            continue
        var distance := player.global_position.distance_to(pedestrian.global_position)
        if distance <= best:
            best = distance
            nearest = pedestrian
    return nearest

func _open_nearest() -> void:
    var npc := nearest_talkable()
    if npc != null:
        open_for_npc(npc)

func open_for_npc(npc: Node3D) -> bool:
    if npc == null or not is_instance_valid(npc) or not npc.is_in_group("ambient_pedestrian"):
        return false
    close_dialogue()
    _active_npc = npc
    _active_anchor = npc.global_position
    npc.set_meta("dialogue_hold", true)
    npc.set_meta("dialogue_action", "idle")
    _panel.visible = true
    _talk_button.visible = false
    _title.text = "%s · MIDI" % _display_name(npc)
    var session = _session_for(npc)
    var snapshot: Dictionary = session._fallback_result(_build_blackboard(), "dialogue_open")
    _apply_result(snapshot)
    _input.text = ""
    _input.grab_focus()
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    return true

func close_dialogue() -> void:
    if _active_npc != null and is_instance_valid(_active_npc):
        _active_npc.set_meta("dialogue_hold", false)
    _active_npc = null
    _busy = false
    if _panel != null:
        _panel.visible = false
    if _send != null:
        _send.disabled = false
    if not DisplayServer.is_touchscreen_available():
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func is_dialogue_open() -> bool:
    return _panel != null and _panel.visible

func displayed_line() -> String:
    return "" if _response == null else _response.text

func displayed_source() -> String:
    return "" if _source == null else _source.text

func _session_for(npc: Node3D):
    var session_id := _npc_id(npc)
    if _sessions.has(session_id) and is_instance_valid(_sessions[session_id]):
        return _sessions[session_id]
    var session = SESSION_SCRIPT.new()
    session.name = "DialogueSession_%s" % session_id
    add_child(session)
    session.configure(session_id, _display_name(npc), "midi", "midi_resident_01", _catalog)
    _sessions[session_id] = session
    return session

func _npc_id(npc: Node3D) -> String:
    return "midi_%s" % npc.name.to_snake_case()

func _display_name(npc: Node3D) -> String:
    var suffix := int(abs(npc.name.hash()))
    return NAMES[suffix % NAMES.size()]

func _build_blackboard() -> Dictionary:
    _event_serial += 1
    var distance := 9999.0
    var main := get_tree().current_scene
    if main != null and _active_npc != null:
        var player := main.get_node_or_null("Player") as Node3D
        if player != null:
            distance = player.global_position.distance_to(_active_npc.global_position)
    return {
        "threat": 0.0,
        "health": 100.0,
        "police_nearby": false,
        "distance_to_player": distance,
        "zone": "midi",
        "event_serial": _event_serial,
    }

func _send_turn() -> void:
    if _busy or _active_npc == null or not is_instance_valid(_active_npc):
        return
    var message := _input.text.strip_edges()
    if message.is_empty():
        return
    _busy = true
    _send.disabled = true
    _response.text = "…"
    _source.text = "LLM LOCAL · tentative"
    var session = _session_for(_active_npc)
    var result: Dictionary = await session.request_turn(message, _build_blackboard())
    _apply_result(result)
    _input.text = ""
    _busy = false
    _send.disabled = false
    _input.grab_focus()

func inject_model_text_for_test(user_message: String, raw_text: String, blackboard: Dictionary = {}) -> Dictionary:
    if _active_npc == null or not is_instance_valid(_active_npc):
        return {}
    var board := blackboard.duplicate(true)
    if board.is_empty():
        board = _build_blackboard()
    var result: Dictionary = _session_for(_active_npc).resolve_model_text(user_message, raw_text, board)
    _apply_result(result)
    return result

func _apply_result(result: Dictionary) -> void:
    var line := str(result.get("line", "…"))
    var source := str(result.get("source", "fallback"))
    var action := str(result.get("action", "idle"))
    _response.text = line
    _source.text = "LLM LOCAL" if source == "llm" else "BAKE OFFLINE"
    if _active_npc != null and is_instance_valid(_active_npc):
        _active_npc.set_meta("dialogue_action", action)
        _active_npc.set_meta("dialogue_source", source)
        _active_npc.set_meta("dialogue_line", line)
        _active_npc.set_meta("dialogue_hold", action != "walk")
        if bool(_active_npc.get_meta("dialogue_hold", false)):
            _active_anchor = _active_npc.global_position
