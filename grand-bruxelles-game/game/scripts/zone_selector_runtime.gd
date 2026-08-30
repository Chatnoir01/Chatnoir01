extends CanvasLayer

const CATALOG_PATH := "res://data/qa/playable_zone_catalog.json"
const MAIN_SCENE := "res://game/main.tscn"
const REPORT_RUNTIME := preload("res://game/scripts/player_issue_report_runtime.gd")
const CATALOG_SCHEMA_V1 := "grand-bruxelles-playable-zone-catalog-v1"
const CATALOG_SCHEMA_V2 := "grand-bruxelles-playable-zone-catalog-v2"
const STORED_QUALITIES := ["JOUABLE", "LABO", "LABO_BRUT"]
const ACTIVE_ZONE_ID_META := "grand_bruxelles_active_zone_id"
const ACTIVE_ZONE_LABEL_META := "grand_bruxelles_active_zone_label"

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
    _catalog = parse_catalog_document(parsed as Dictionary)

func parse_catalog_document(document: Dictionary) -> Array:
    var schema := str(document.get("schema", ""))
    if schema != CATALOG_SCHEMA_V1 and schema != CATALOG_SCHEMA_V2:
        push_error("Zone selector catalog unsupported schema: %s" % schema)
        return []
    var rows: Variant = document.get("zones", [])
    if not rows is Array:
        push_error("Zone selector catalog zones must be an array")
        return []
    var result: Array = []
    var seen_ids := {}
    for raw: Variant in rows:
        if not raw is Dictionary:
            push_error("Zone selector catalog row must be an object")
            continue
        var zone := (raw as Dictionary).duplicate(true)
        var zone_id := str(zone.get("id", "")).strip_edges()
        var label := str(zone.get("label", "")).strip_edges()
        var quality := str(zone.get("quality", "")).strip_edges().to_upper()
        if zone_id.is_empty() or label.is_empty():
            push_error("Zone selector catalog row missing id/label")
            continue
        if seen_ids.has(zone_id):
            push_error("Zone selector catalog duplicate id: %s" % zone_id)
            continue
        if quality not in STORED_QUALITIES:
            push_error("Zone selector catalog unknown stored quality for %s: %s" % [zone_id, quality])
            continue
        if schema == CATALOG_SCHEMA_V1 and quality == "LABO_BRUT":
            push_error("Zone selector catalog v1 cannot store LABO_BRUT: %s" % zone_id)
            continue
        if not _catalog_row_shape_valid(zone):
            push_error("Zone selector catalog malformed runtime contract: %s" % zone_id)
            continue
        zone["quality"] = quality
        seen_ids[zone_id] = true
        result.append(zone)
    return result

func _catalog_row_shape_valid(zone: Dictionary) -> bool:
    var requirements: Variant = zone.get("requires", [])
    if not requirements is Array or requirements.is_empty():
        return false
    for raw: Variant in requirements:
        if str(raw).strip_edges().is_empty():
            return false
    var mode := str(zone.get("mode", ""))
    if mode == "fast_travel":
        return not str(zone.get("destination", "")).strip_edges().is_empty()
    if mode == "position":
        var spawn: Variant = zone.get("spawn", [])
        return spawn is Array and spawn.size() >= 3
    if mode == "player_method":
        return not str(zone.get("method", "")).strip_edges().is_empty()
    if mode == "script_zone":
        var spawn: Variant = zone.get("spawn", [])
        return not str(zone.get("script", "")).strip_edges().is_empty() and spawn is Array and spawn.size() >= 3
    return false

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
    if main.has_meta(ACTIVE_ZONE_ID_META):
        var explicit_id := str(main.get_meta(ACTIVE_ZONE_ID_META, "")).strip_edges()
        if not explicit_id.is_empty() and not _zone_by_id(explicit_id).is_empty():
            return explicit_id
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
    _toggle.text = "CHANGER DE ZONE"
    _toggle.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    _toggle.position = Vector2(-560.0, 18.0)
    _toggle.size = Vector2(168.0, 42.0)
    _toggle.pressed.connect(func() -> void: set_menu_open(not _panel.visible))
    add_child(_toggle)

    _panel = PanelContainer.new()
    _panel.name = "ZoneSelectorPanel"
    _panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    _panel.position = Vector2(-590.0, 70.0)
    _panel.size = Vector2(520.0, 470.0)
    _panel.visible = false
    add_child(_panel)

    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 18)
    margin.add_theme_constant_override("margin_top", 16)
    margin.add_theme_constant_override("margin_right", 18)
    margin.add_theme_constant_override("margin_bottom", 16)
    _panel.add_child(margin)

    var root_box := VBoxContainer.new()
    root_box.add_theme_constant_override("separation", 8)
    margin.add_child(root_box)

    var title := Label.new()
    title.text = "CHANGER DE ZONE"
    title.add_theme_font_size_override("font_size", 22)
    root_box.add_child(title)

    _status = Label.new()
    _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _status.text = "Choisis une zone disponible. Les zones LABO restent en revue et ne sont pas promues automatiquement."
    root_box.add_child(_status)

    var scroll := ScrollContainer.new()
    scroll.custom_minimum_size = Vector2(0.0, 310.0)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    root_box.add_child(scroll)

    var zones_box := VBoxContainer.new()
    zones_box.name = "ZoneSelectorButtons"
    zones_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    zones_box.add_theme_constant_override("separation", 6)
    scroll.add_child(zones_box)

    for zone: Dictionary in available_zones():
        var zone_id := str(zone.get("id", ""))
        var button := Button.new()
        button.name = "Zone_%s" % zone_id
        button.text = "%s  —  %s" % [str(zone.get("label", zone_id)), str(zone.get("quality", "LABO"))]
        button.alignment = HORIZONTAL_ALIGNMENT_LEFT
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        button.pressed.connect(func() -> void: _on_zone_pressed(zone_id))
        zones_box.add_child(button)

func set_menu_open(open: bool) -> void:
    if _panel == null:
        return
    _panel.visible = open
    if open:
        _previous_mouse_mode = Input.mouse_mode
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    else:
        Input.mouse_mode = _previous_mouse_mode

func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
        set_menu_open(not _panel.visible)
        get_viewport().set_input_as_handled()

func _zone_by_id(zone_id: String) -> Dictionary:
    for raw: Variant in _catalog:
        if raw is Dictionary and str((raw as Dictionary).get("id", "")) == zone_id:
            return (raw as Dictionary).duplicate(true)
    return {}

func _on_zone_pressed(zone_id: String) -> void:
    if _busy:
        return
    var zone := _zone_by_id(zone_id)
    if zone.is_empty() or not _requirements_ready(zone):
        _status.text = "Zone indisponible: %s" % zone_id
        return
    _pending_zone_id = zone_id
    _busy = true
    set_menu_open(false)
    _status.text = "Chargement: %s" % str(zone.get("label", zone_id))
    call_deferred("_reload_and_apply", zone)

func _reload_and_apply(zone: Dictionary) -> void:
    if get_tree().change_scene_to_file(MAIN_SCENE) != OK:
        _busy = false
        _status.text = "Échec chargement de la scène principale."
        return
    await get_tree().process_frame
    for _attempt: int in range(240):
        var main := get_tree().current_scene
        if main != null and main.get_node_or_null("Player") != null:
            await _apply_zone(main, zone)
            _busy = false
            return
        await get_tree().process_frame
    _busy = false
    _status.text = "Échec: joueur indisponible."

func _apply_zone(main: Node, zone: Dictionary) -> void:
    var player := main.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        return
    var zone_id := str(zone.get("id", ""))
    var mode := str(zone.get("mode", ""))
    if mode == "fast_travel":
        var destination := str(zone.get("destination", ""))
        if player.has_method("fast_travel"):
            player.call("fast_travel", destination)
    elif mode == "position":
        var spawn: Array = zone.get("spawn", [])
        if spawn.size() >= 3:
            player.global_position = Vector3(float(spawn[0]), float(spawn[1]), float(spawn[2]))
            player.velocity = Vector3.ZERO
    elif mode == "player_method":
        var method := str(zone.get("method", ""))
        if player.has_method(method):
            player.call(method)
    elif mode == "script_zone":
        var script_path := str(zone.get("script", ""))
        var script := load(script_path) as Script
        if script == null:
            push_error("Zone selector script load failed: %s" % script_path)
            return
        var instance := Node3D.new()
        instance.name = "ZoneLab_%s" % zone_id
        instance.set_script(script)
        main.add_child(instance)
        var spawn: Array = zone.get("spawn", [])
        if spawn.size() >= 3:
            player.global_position = Vector3(float(spawn[0]), float(spawn[1]), float(spawn[2]))
            player.velocity = Vector3.ZERO
    main.set_meta(ACTIVE_ZONE_ID_META, zone_id)
    main.set_meta(ACTIVE_ZONE_LABEL_META, str(zone.get("label", zone_id)))
    _active_zone_id = zone_id
    _pending_zone_id = ""
