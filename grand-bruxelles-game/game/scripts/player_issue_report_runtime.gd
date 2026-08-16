extends Control

signal report_created(report_id: String, zone_id: String, report_path: String)

const SCHEMA := "grand-bruxelles-player-report-v1"
const REPORT_DIR := "user://player_reports/open"
const MAX_NOTE_LENGTH := 80

var _selector: Node
var _button: Button
var _panel: PanelContainer
var _context_label: Label
var _note: LineEdit
var _status: Label
var _status_timer: Timer
var _pending_image: Image
var _pending_context: Dictionary = {}
var _previous_mouse_mode := Input.MOUSE_MODE_CAPTURED
var _sequence := 0

func configure(selector: Node) -> void:
    _selector = selector

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _build_ui()

func _build_ui() -> void:
    _button = Button.new()
    _button.name = "ReportButton"
    _button.text = "SIGNALER"
    _button.mouse_filter = Control.MOUSE_FILTER_STOP
    _button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    _button.position = Vector2(-632.0, 18.0)
    _button.size = Vector2(120.0, 42.0)
    _button.pressed.connect(begin_report)
    add_child(_button)

    _status = Label.new()
    _status.name = "ReportStatus"
    _status.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _status.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    _status.position = Vector2(-632.0, 64.0)
    _status.size = Vector2(240.0, 34.0)
    _status.visible = false
    add_child(_status)

    _panel = PanelContainer.new()
    _panel.name = "ReportPanel"
    _panel.mouse_filter = Control.MOUSE_FILTER_STOP
    _panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
    _panel.position = Vector2(-230.0, 84.0)
    _panel.size = Vector2(460.0, 185.0)
    add_child(_panel)

    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 8)
    _panel.add_child(box)
    var title := Label.new()
    title.text = "SIGNALER UN DÉFAUT JOUEUR"
    title.add_theme_font_size_override("font_size", 19)
    box.add_child(title)
    _context_label = Label.new()
    _context_label.name = "ReportContext"
    box.add_child(_context_label)
    _note = LineEdit.new()
    _note.name = "ReportNote"
    _note.placeholder_text = "Mot court (optionnel) : sol trou, spawn mur…"
    _note.max_length = MAX_NOTE_LENGTH
    _note.text_submitted.connect(func(_text: String) -> void: _submit_pending())
    box.add_child(_note)
    var actions := HBoxContainer.new()
    actions.add_theme_constant_override("separation", 8)
    box.add_child(actions)
    var send := Button.new()
    send.text = "ENVOYER"
    send.pressed.connect(_submit_pending)
    actions.add_child(send)
    var cancel := Button.new()
    cancel.text = "ANNULER"
    cancel.pressed.connect(_cancel_pending)
    actions.add_child(cancel)
    _panel.visible = false

    _status_timer = Timer.new()
    _status_timer.one_shot = true
    _status_timer.wait_time = 4.0
    _status_timer.timeout.connect(func() -> void: _status.visible = false)
    add_child(_status_timer)

func begin_report() -> void:
    if _panel.visible or _selector == null or not _selector.has_method("current_report_context"):
        return
    var context: Variant = _selector.call("current_report_context")
    if not context is Dictionary or (context as Dictionary).is_empty():
        _flash_status("SIGNALER indisponible · joueur introuvable")
        return
    var image := get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        _flash_status("SIGNALER indisponible · capture impossible")
        return
    _pending_image = image
    _pending_context = (context as Dictionary).duplicate(true)
    if _selector.has_method("set_menu_open"):
        _selector.call("set_menu_open", false)
    _previous_mouse_mode = Input.mouse_mode
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    var pos: Array = _pending_context.get("position", [0.0, 0.0, 0.0])
    _context_label.text = "%s · %s   (%.1f, %.1f, %.1f)" % [
        str(_pending_context.get("label", "Zone")),
        str(_pending_context.get("quality", "LABO")),
        float(pos[0]), float(pos[1]), float(pos[2])
    ]
    _note.text = ""
    _panel.visible = true
    _note.grab_focus()

func create_report_from_image(note: String, image: Image) -> String:
    if _selector == null or not _selector.has_method("current_report_context"):
        return ""
    var context: Variant = _selector.call("current_report_context")
    if not context is Dictionary:
        return ""
    return create_report_from_context(note, image, context as Dictionary, true)

func create_report_from_context(note: String, image: Image, context: Dictionary, export_ticket := true) -> String:
    if image == null or image.is_empty() or context.is_empty():
        return ""
    var zone_id := str(context.get("id", "unknown")).strip_edges()
    if zone_id.is_empty():
        return ""
    _sequence += 1
    var report_id := "%d-%03d-%s-%02d" % [
        int(Time.get_unix_time_from_system()),
        int(Time.get_ticks_msec() % 1000),
        zone_id.replace("/", "-"),
        _sequence
    ]
    var png_bytes := image.save_png_to_buffer()
    if png_bytes.is_empty():
        return ""
    var clean_note := note.strip_edges().substr(0, MAX_NOTE_LENGTH)
    var position: Array = context.get("position", [0.0, 0.0, 0.0])
    var screenshot_path := REPORT_DIR.path_join("%s.png" % report_id)
    var report_path := REPORT_DIR.path_join("%s.gbreport.json" % report_id)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT_DIR))
    if image.save_png(screenshot_path) != OK:
        return ""
    var report := {
        "schema": SCHEMA,
        "id": report_id,
        "status": "open",
        "zone": {
            "id": zone_id,
            "label": str(context.get("label", zone_id)),
            "quality": str(context.get("quality", "LABO")),
        },
        "player_position": [float(position[0]), float(position[1]), float(position[2])],
        "note": clean_note,
        "captured_unix": int(Time.get_unix_time_from_system()),
        "screenshot_file": screenshot_path,
        "screenshot": {
            "encoding": "base64-png",
            "width": image.get_width(),
            "height": image.get_height(),
            "data": Marshalls.raw_to_base64(png_bytes),
        },
    }
    var payload := JSON.stringify(report)
    var file := FileAccess.open(report_path, FileAccess.WRITE)
    if file == null:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(screenshot_path))
        return ""
    file.store_string(payload)
    file.close()
    if export_ticket:
        _export_ticket(report_id, payload)
    report_created.emit(report_id, zone_id, report_path)
    print("PLAYER_REPORT_CREATED: id=%s zone=%s pos=%s note=%s" % [report_id, zone_id, str(report["player_position"]), clean_note])
    return report_path

func open_report_count(zone_id: String) -> int:
    if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(REPORT_DIR)):
        return 0
    var count := 0
    for filename: String in DirAccess.get_files_at(REPORT_DIR):
        if not filename.ends_with(".gbreport.json"):
            continue
        var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REPORT_DIR.path_join(filename)))
        if not parsed is Dictionary:
            continue
        var report := parsed as Dictionary
        var zone: Variant = report.get("zone", {})
        if report.get("schema", "") == SCHEMA and report.get("status", "") == "open" and zone is Dictionary and str((zone as Dictionary).get("id", "")) == zone_id:
            count += 1
    return count

func _submit_pending() -> void:
    if _pending_image == null or _pending_context.is_empty():
        _cancel_pending()
        return
    var report_path := create_report_from_context(_note.text, _pending_image, _pending_context, true)
    var label := str(_pending_context.get("label", "Zone"))
    _clear_pending()
    if report_path.is_empty():
        _flash_status("ÉCHEC SIGNALER · ticket non créé")
    else:
        _flash_status("SIGNALÉ · %s" % label)

func _cancel_pending() -> void:
    _clear_pending()

func _clear_pending() -> void:
    _panel.visible = false
    _pending_image = null
    _pending_context.clear()
    if not DisplayServer.is_touchscreen_available():
        Input.mouse_mode = _previous_mouse_mode

func _flash_status(message: String) -> void:
    _status.text = message
    _status.visible = true
    _status_timer.start()

func _export_ticket(report_id: String, payload: String) -> void:
    var filename := "%s.gbreport.json" % report_id
    if OS.has_feature("web"):
        var encoded := Marshalls.raw_to_base64(payload.to_utf8_buffer())
        var script := "(function(){const b=atob('%s');const a=new Uint8Array(b.length);for(let i=0;i<b.length;i++)a[i]=b.charCodeAt(i);const u=URL.createObjectURL(new Blob([a],{type:'application/json'}));const e=document.createElement('a');e.href=u;e.download='%s';e.click();setTimeout(()=>URL.revokeObjectURL(u),1000);})();" % [encoded, filename]
        JavaScriptBridge.eval(script)
        return
    var downloads := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
    if downloads.is_empty():
        return
    DirAccess.make_dir_recursive_absolute(downloads)
    var file := FileAccess.open(downloads.path_join(filename), FileAccess.WRITE)
    if file != null:
        file.store_string(payload)
        file.close()
