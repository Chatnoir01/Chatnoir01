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
var _zone_list: VBoxContainer
var _report_help: Label
var _zone_buttons: Dictionary = {}
var _busy := false
var _pending_zone_id := ""
var _active_zone_id := "midi"
var _previous_mouse_mode := Input.MOUSE_MODE_CAPTURED

func _ready() -> void:
    layer = 120
    process_mode = Node.PROCESS_MODE_ALWAYS
    _load_catalog()
    _reporter = REPORT_RUNTIME.new()
    _reporter.name = "PlayerIssueReportRuntime"
    _reporter.call("configure", self)
    add_child(_reporter)
    if _reporter.has_signal("report_created"):
        _reporter.connect("report_created", _on_report_created)
    _build_ui()

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
        return _spawn_contract_ready(zone)
    if mode == "player_method":
        return not str(zone.get("method", "")).strip_edges().is_empty()
    if mode == "script_zone":
        return not str(zone.get("script", "")).strip_edges().is_empty() and _spawn_contract_ready(zone)
    return false

func _requirements_ready(zone: Dictionary) -> bool:
    var requirements: Variant = zone.get("requires", [])
    if not requirements is Array or requirements.is_empty():
        return false
    for raw: Variant in requirements:
        var path := str(raw).strip_edges()
        if path.is_empty() or (not ResourceLoader.exists(path) and not FileAccess.file_exists(path)):
            return false
    return true

func _spawn_contract_ready(zone: Dictionary) -> bool:
    var spawn: Variant = zone.get("spawn", [])
    if not spawn is Array or spawn.size() < 3:
        return false
    for index: int in range(3):
        var value: Variant = spawn[index]
        if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
            return false
        var number := float(value)
        if is_nan(number) or is_inf(number):
            return false
    return true

func _runtime_route_ready(zone: Dictionary, main: Node) -> bool:
    var life_script := str(zone.get("life_script", "")).strip_edges()
    if not life_script.is_empty():
        if not ResourceLoader.exists(life_script):
            return false
        var life_resource: Resource = load(life_script)
        if not life_resource is Script:
            return false
    var mode := str(zone.get("mode", ""))
    if mode == "script_zone":
        var script_path := str(zone.get("script", "")).strip_edges()
        if not ResourceLoader.exists(script_path):
            return false
        var zone_resource: Resource = load(script_path)
        if not zone_resource is Script:
            return false
    if main == null:
        return true
    var player := main.get_node_or_null("Player")
    if player == null:
        return false
    if mode == "fast_travel":
        return player.has_method("fast_travel_to")
    if mode == "position":
        return _spawn_contract_ready(zone)
    if mode == "player_method":
        return player.has_method(str(zone.get("method", "")))
    if mode == "script_zone":
        return _spawn_contract_ready(zone)
    return false

func _listing_failure_reason(zone: Dictionary, main: Node = null) -> String:
    var quality := str(zone.get("quality", "")).to_upper()
    if quality not in STORED_QUALITIES:
        return "honest_quality"
    if not _requirements_ready(zone):
        return "requires_resources"
    var mode := str(zone.get("mode", ""))
    if (mode == "position" or mode == "script_zone") and not _spawn_contract_ready(zone):
        return "spawn_stable"
    if not _runtime_route_ready(zone, main):
        return "load_without_crash"
    return ""

func listing_state(zone: Dictionary, main: Node = null) -> String:
    var effective_main := main
    if effective_main == null:
        effective_main = get_tree().current_scene
    if not _listing_failure_reason(zone, effective_main).is_empty():
        return "NON_LISTE"
    var quality := str(zone.get("quality", "LABO"))
    if quality != "JOUABLE" and _open_report_count(str(zone.get("id", ""))) > 0:
        return "LABO_REPORT"
    return quality

func _badge_text(state: String) -> String:
    if state == "LABO_BRUT":
        return "LABO·BRUT"
    if state == "LABO_REPORT":
        return "LABO·REPORT"
    return state

func available_zones() -> Array:
    var result: Array = []
    var main := get_tree().current_scene
    for raw: Variant in _catalog:
        if not raw is Dictionary:
            continue
        var zone := raw as Dictionary
        if listing_state(zone, main) == "NON_LISTE":
            continue
        result.append(zone.duplicate(true))
    return result

func _catalog_zone_by_id(zone_id: String) -> Dictionary:
    for raw: Variant in _catalog:
        if raw is Dictionary and str((raw as Dictionary).get("id", "")) == zone_id:
            return (raw as Dictionary).duplicate(true)
    return {}

func _open_report_count(zone_id: String) -> int:
    if _reporter == null or not _reporter.has_method("open_report_count"):
        return 0
    return int(_reporter.call("open_report_count", zone_id))

func reporting_runtime() -> Node:
    return _reporter

func can_promote_zone(zone_id: String) -> bool:
    var zone := _zone_by_id(zone_id)
    if zone.is_empty() or str(zone.get("quality", "")) != "LABO" or _reporter == null:
        return false
    return _open_report_count(zone_id) == 0

func current_report_context() -> Dictionary:
    var main := get_tree().current_scene
    if main == null:
        return {}
    var player := main.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        return {}
    var zone_id := _infer_active_zone_id(main)
    var zone := _catalog_zone_by_id(zone_id)
    if zone.is_empty():
        zone = _catalog_zone_by_id(_active_zone_id)
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
        if not explicit_id.is_empty() and not _catalog_zone_by_id(explicit_id).is_empty():
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
    _toggle.text = "ZONES"
    _toggle.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    _toggle.position = Vector2(-500.0, 18.0)
    _toggle.size = Vector2(108.0, 42.0)
    _toggle.pressed.connect(func() -> void: set_menu_open(not _panel.visible))
    add_child(_toggle)

    _panel = PanelContainer.new()
    _panel.name = "ZoneSelectorPanel"
    _panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    _panel.position = Vector2(-410.0, 70.0)
    _panel.size = Vector2(392.0, 590.0)
    add_child(_panel)

    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 9)
    _panel.add_child(box)
    var title := Label.new()
    title.text = "BRUXELLES · ZONES"
    title.add_theme_font_size_override("font_size", 20)
    box.add_child(title)
    var hint := Label.new()
    hint.text = "JOUABLE = validé humain · LABO = testable · BRUT = encore indigne du standard Midi"
    hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(hint)

    _report_help = Label.new()
    _report_help.name = "ZoneReportHelp"
    _report_help.text = "LABO·REPORT = défaut joueur ouvert · promotion qualité bloquée"
    _report_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _report_help.visible = false
    box.add_child(_report_help)

    _zone_list = VBoxContainer.new()
    _zone_list.name = "ZoneList"
    _zone_list.add_theme_constant_override("separation", 7)
    box.add_child(_zone_list)
    _rebuild_zone_rows()

    _status = Label.new()
    _status.name = "ZoneSelectorStatus"
    _status.text = "Seules les zones qui passent les gates minimum sont listées."
    _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(_status)
    var close := Button.new()
    close.text = "FERMER"
    close.pressed.connect(func() -> void: set_menu_open(false))
    box.add_child(close)
    _panel.visible = false

func _rebuild_zone_rows() -> void:
    if _zone_list == null:
        return
    for child: Node in _zone_list.get_children():
        _zone_list.remove_child(child)
        child.queue_free()
    _zone_buttons.clear()
    var report_count := 0
    for zone: Dictionary in available_zones():
        var state := listing_state(zone, get_tree().current_scene)
        var zone_id := str(zone.get("id", "unknown"))
        if state == "LABO_REPORT":
            report_count += 1
        var button := Button.new()
        button.name = "Zone_%s" % zone_id
        button.text = "%s  —  %s" % [str(zone.get("label", "Zone")), _badge_text(state)]
        button.custom_minimum_size = Vector2(356.0, 44.0)
        button.alignment = HORIZONTAL_ALIGNMENT_LEFT
        button.pressed.connect(_on_zone_pressed.bind(zone_id))
        _zone_list.add_child(button)
        _zone_buttons[zone_id] = button
    if _report_help != null:
        _report_help.visible = report_count > 0

func _on_report_created(_report_id: String, _zone_id: String, _report_path: String) -> void:
    _rebuild_zone_rows()

func set_menu_open(open: bool) -> void:
    if _panel == null:
        return
    if open:
        _rebuild_zone_rows()
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
        _status.text = "NON LISTÉ · un gate minimum échoue."
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
        if _spawn_contract_ready(zone):
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
    if not await _mount_life_if_required(main, zone):
        _travel_failed("zone loaded but minimum LABO life contract failed")
        return
    _active_zone_id = str(zone.get("id", _active_zone_id))
    _publish_active_zone(main, zone)
    _pending_zone_id = ""
    _busy = false
    var state := listing_state(zone, main)
    _status.text = "%s · %s" % [str(zone.get("label", "Zone")), _badge_text(state)]
    print("ZONE_VISIT_READY: id=%s quality=%s state=%s" % [str(zone.get("id", "")), str(zone.get("quality", "")), state])

func _publish_active_zone(main: Node, zone: Dictionary) -> void:
    if main == null:
        return
    var zone_id := str(zone.get("id", "")).strip_edges()
    var zone_label := str(zone.get("label", zone_id)).strip_edges()
    if zone_id.is_empty() or zone_label.is_empty():
        return
    main.set_meta(ACTIVE_ZONE_ID_META, zone_id)
    main.set_meta(ACTIVE_ZONE_LABEL_META, zone_label)

func _mount_life_if_required(main: Node, zone: Dictionary) -> bool:
    var script_path := str(zone.get("life_script", ""))
    if script_path.is_empty():
        return true
    var script: Script = load(script_path)
    if script == null:
        return false
    var life := Node3D.new()
    life.name = "ZoneLife_%s" % str(zone.get("id", "zone"))
    life.set_script(script)
    main.add_child(life)
    await get_tree().process_frame
    if life.has_method("has_minimum_playable_life") and not bool(life.call("has_minimum_playable_life")):
        life.queue_free()
        return false
    var minimum: Variant = zone.get("life_minimum", {})
    if minimum is Dictionary and life.has_method("get_counts"):
        var counts: Variant = life.call("get_counts")
        if not counts is Dictionary:
            life.queue_free()
            return false
        for key: Variant in (minimum as Dictionary).keys():
            if int((counts as Dictionary).get(key, 0)) < int((minimum as Dictionary).get(key, 0)):
                life.queue_free()
                return false
    return true

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
    if not _spawn_contract_ready(zone):
        lab.queue_free()
        return false
    player.global_position = Vector3(float(spawn[0]), float(spawn[1]), float(spawn[2]))
    player.velocity = Vector3.ZERO
    if player.has_method("_restore_runtime_hud"):
        player.call("_restore_runtime_hud")
    var location := main.get_node_or_null("LocationLabel")
    if location != null and location.has_method("set_forced_label"):
        location.call("set_forced_label", "%s · %s" % [str(zone.get("label", "ZONE")), _badge_text(listing_state(zone, main))])
    return true

func _travel_failed(message: String) -> void:
    push_error("Zone selector: %s" % message)
    _pending_zone_id = ""
    _busy = false
    if _status != null:
        _status.text = "INDISPONIBLE · NON LISTÉ tant que le gate échoue"
    set_menu_open(true)
