extends CanvasLayer

const CATALOG_PATH := "res://data/qa/playable_zone_catalog.json"
const MAIN_SCENE := "res://game/main.tscn"
const REPORT_RUNTIME := preload("res://game/scripts/player_issue_report_runtime.gd")

var _catalog: Array = []
var _panel: PanelContainer
var _status: Label
var _toggle: Button
var _reporter: Node
var _busy := false
var _pending_zone_id := ""
var _active_zone_id := "midi"
var _previous_mouse_mode := Input.MOUSE_MODE_CAPTURED

func _ready() -> void:
    layer = 120
    process_mode = Node.PROCESS_MODE_ALWAYS
    _load_catalog()
    _build_ui()
    _reporter = REPORT_RUNTIME.new()
    _reporter.name = "PlayerIssueReportRuntime"
    _reporter.call("configure", self)
    add_child(_reporter)

func _load_catalog() -> void:
    _catalog.clear()
    if not FileAccess.file_exists(CATALOG_PATH):
        push_error("Zone selector catalog missing: %s" % CATALOG_PATH)
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Zone selector catalog invalid")
        return
    var rows: Variant = (parsed as Dictionary).get("zones", [])
    if rows is Array:
        _catalog = rows

func _requirements_ready(zone: Dictionary) -> bool:
    var requirements: Variant = zone.get("requires", [])
    if not requirements is Array:
        return false
    for raw: Variant in requirements:
        var path := str(raw)
        if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
            return false
    return true

func available_zones() -> Array:
    var result: Array = []
    for raw: Variant in _catalog:
        if raw is Dictionary and _requirements_ready(raw as Dictionary):
            result.append((raw as Dictionary).duplicate(true))
    return result

func reporting_runtime() -> Node:
    return _reporter

func can_promote_zone(zone_id: String) -> bool:
    var zone := _zone_by_id(zone_id)
    if zone.is_empty() or str(zone.get("quality", "")) != "LABO" or _reporter == null:
        return false
    return int(_reporter.call("open_report_count", zone_id)) == 0

func current_report_context() -> Dictionary:
    var main := get_tree().current_scene
    if main == null:
        return {}
    var player := main.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        return {}
    var zone_id := _infer_active_zone_id(main)
    var zone := _zone_by_id(zone_id)
    if zone.is_empty():
        zone = _zone_by_id(_active_zone_id)
    if zone.is_empty():
        return {}
    return {
        "id": str(zone.get("id", zone_id)),
        "label": str(zone.get("label", zone_id)),
        "quality": str(zone.get("quality", "LABO")),
        "position": [player.global_position.x, player.global_position.y, player.global_position.z],
    }

func _infer_active_zone_id(main: Node) -> String:
    var location := main.get_node_or_null("LocationLabel")
    if location == null or not location.has_method("get_current_location_text"):
        return _active_zone_id
    var text := str(location.call("get_current_location_text")).to_upper()
    var hints := {
        "GRAND-PLACE": "grand_place",
        "ANNEESSENS": "anneessens",
        "BOURSE": "bourse",
        "MIDI": "midi",
        "IXELLES": "ixelles",
        "ATOMIUM": "atomium",
        "JETTE": "jette",
    }
    for needle: String in hints:
        if text.contains(needle):
            return str(hints[needle])
    return _active_zone_id

func _build_ui() -> void:
    _toggle = Button.new()
    _toggle.name = "ZoneSelectorToggle"
    _toggle.text = "ZONES"
    _toggle.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    _toggle.position = Vector2(-500.0, 18.0)
    _toggle.size = Vector2(108.0, 42.0)
    _toggle.pressed.connect(func() -> void: set_menu_open(not _panel.visible))
    add_child(_toggle)

    _panel = PanelContainer.new()
    _panel.name = "ZoneSelectorPanel"
    _panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    _panel.position = Vector2(-382.0, 70.0)
    _panel.size = Vector2(364.0, 540.0)
    add_child(_panel)

    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 9)
    _panel.add_child(box)
    var title := Label.new()
    title.text = "BRUXELLES · ZONES SUR MAIN"
    title.add_theme_font_size_override("font_size", 20)
    box.add_child(title)
    var hint := Label.new()
    hint.text = "JOUABLE = validé · LABO = à tester en jouant"
    hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(hint)

    for zone: Dictionary in available_zones():
        var button := Button.new()
        button.name = "Zone_%s" % str(zone.get("id", "unknown"))
        button.text = "%s  —  %s" % [str(zone.get("label", "Zone")), str(zone.get("quality", "LABO"))]
        button.custom_minimum_size = Vector2(330.0, 44.0)
        button.alignment = HORIZONTAL_ALIGNMENT_LEFT
        button.pressed.connect(_on_zone_pressed.bind(str(zone.get("id", ""))))
        box.add_child(button)

    _status = Label.new()
    _status.name = "ZoneSelectorStatus"
    _status.text = "Choisis une zone. Le menu ne liste que les runtimes présents."
    _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(_status)
    var close := Button.new()
    close.text = "FERMER"
    close.pressed.connect(func() -> void: set_menu_open(false))
    box.add_child(close)
    _panel.visible = false

func set_menu_open(open: bool) -> void:
    if _panel == null:
        return
    _panel.visible = open
    if open:
        _previous_mouse_mode = Input.mouse_mode
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    elif not DisplayServer.is_touchscreen_available():
        Input.mouse_mode = _previous_mouse_mode

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
        set_menu_open(not _panel.visible)
        get_viewport().set_input_as_handled()

func _zone_by_id(zone_id: String) -> Dictionary:
    for zone: Dictionary in available_zones():
        if str(zone.get("id", "")) == zone_id:
            return zone
    return {}

func _on_zone_pressed(zone_id: String) -> void:
    if _busy:
        return
    var zone := _zone_by_id(zone_id)
    if zone.is_empty():
        _status.text = "Zone indisponible : elle n'est plus listable."
        return
    _busy = true
    _pending_zone_id = zone_id
    _status.text = "CHARGEMENT · %s" % str(zone.get("label", zone_id))
    set_menu_open(false)
    call_deferred("_reload_main_for_pending")

func _reload_main_for_pending() -> void:
    var error := get_tree().change_scene_to_file(MAIN_SCENE)
    if error != OK:
        _travel_failed("main scene reload failed: %s" % error)
        return
    call_deferred("_apply_pending_when_ready")

func _apply_pending_when_ready() -> void:
    for _attempt: int in range(180):
        await get_tree().process_frame
        var main := get_tree().current_scene
        if main != null and main.scene_file_path == MAIN_SCENE and main.get_node_or_null("Player") != null:
            var zone := _zone_by_id(_pending_zone_id)
            if zone.is_empty():
                _travel_failed("zone contract disappeared")
                return
            await _apply_zone(main, zone)
            return
    _travel_failed("main scene/player did not become ready")

func _apply_zone(main: Node, zone: Dictionary) -> void:
    var player := main.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _travel_failed("player missing")
        return
    var mode := str(zone.get("mode", ""))
    var ok := false
    if mode == "fast_travel":
        ok = bool(player.call("fast_travel_to", str(zone.get("destination", ""))))
    elif mode == "position":
        var spawn: Variant = zone.get("spawn", [])
        if spawn is Array and spawn.size() >= 3:
            player.global_position = Vector3(float(spawn[0]), float(spawn[1]), float(spawn[2]))
            player.velocity = Vector3.ZERO
            if player.has_method("_restore_runtime_hud"):
                player.call("_restore_runtime_hud")
            ok = true
    elif mode == "player_method":
        var method := str(zone.get("method", ""))
        if player.has_method(method):
            await player.call(method)
            ok = true
            if player.has_method("_restore_runtime_hud"):
                player.call("_restore_runtime_hud")
    elif mode == "script_zone":
        ok = await _mount_script_zone(main, player, zone)
    if not ok:
        _travel_failed("zone runtime refused to load")
        return
    _active_zone_id = str(zone.get("id", _active_zone_id))
    _pending_zone_id = ""
    _busy = false
    _status.text = "%s · %s" % [str(zone.get("label", "Zone")), str(zone.get("quality", "LABO"))]
    print("ZONE_VISIT_READY: id=%s quality=%s" % [str(zone.get("id", "")), str(zone.get("quality", ""))])

func _mount_script_zone(main: Node, player: CharacterBody3D, zone: Dictionary) -> bool:
    var script_path := str(zone.get("script", ""))
    var script: Script = load(script_path)
    if script == null:
        return false
    var lab := Node3D.new()
    lab.name = "ZoneLab_%s" % str(zone.get("id", "zone"))
    lab.set_script(script)
    main.add_child(lab)
    await get_tree().process_frame
    var stats: Variant = lab.get("last_stats")
    if not stats is Dictionary or int((stats as Dictionary).get("buildings", 0)) <= 0 or int((stats as Dictionary).get("street_surfaces", 0)) <= 0:
        lab.queue_free()
        return false
    var spawn: Variant = zone.get("spawn", [])
    if not spawn is Array or spawn.size() < 3:
        lab.queue_free()
        return false
    player.global_position = Vector3(float(spawn[0]), float(spawn[1]), float(spawn[2]))
    player.velocity = Vector3.ZERO
    if player.has_method("_restore_runtime_hud"):
        player.call("_restore_runtime_hud")
    var location := main.get_node_or_null("LocationLabel")
    if location != null and location.has_method("set_forced_label"):
        location.call("set_forced_label", "%s · LABO" % str(zone.get("label", "ZONE")))
    return true

func _travel_failed(message: String) -> void:
    push_error("Zone selector: %s" % message)
    _pending_zone_id = ""
    _busy = false
    if _status != null:
        _status.text = "INDISPONIBLE · non validé, non promu"
    set_menu_open(true)
