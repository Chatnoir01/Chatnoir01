extends Control

signal report_created(report_id: String, zone_id: String, report_path: String)
signal review_created(review_id: String, zone_id: String, action: String, review_path: String)
signal review_action_requested(action: String, zone_id: String, candidate_id: String, fallback_candidate_id: String)

const SCHEMA := "grand-bruxelles-player-report-v2"
const LEGACY_SCHEMA := "grand-bruxelles-player-report-v1"
const REVIEW_SCHEMA := "grand-bruxelles-visual-review-v1"
const PREFERENCES_SCHEMA := "grand-bruxelles-visual-preferences-v1"
const REPORT_DIR := "user://player_reports/open"
const REVIEW_DIR := "user://player_reports/reviews"
const PREFERENCES_PATH := "user://player_reports/visual_preferences.json"
const MAX_NOTE_LENGTH := 120
const REVIEW_ACTIONS := ["GARDER", "AMELIORER", "REJETER"]

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
    call_deferred("_refresh_report_button")

func _build_ui() -> void:
    _button = Button.new()
    _button.name = "ReportButton"
    _button.text = "À SIGNALER"
    _button.mouse_filter = Control.MOUSE_FILTER_STOP
    _button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    _button.position = Vector2(-660.0, 18.0)
    _button.size = Vector2(148.0, 42.0)
    _button.pressed.connect(begin_report)
    add_child(_button)

    _status = Label.new()
    _status.name = "ReportStatus"
    _status.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _status.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    _status.position = Vector2(-660.0, 64.0)
    _status.size = Vector2(300.0, 42.0)
    _status.visible = false
    add_child(_status)

    _panel = PanelContainer.new()
    _panel.name = "ReportPanel"
    _panel.mouse_filter = Control.MOUSE_FILTER_STOP
    _panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
    _panel.position = Vector2(-270.0, 84.0)
    _panel.size = Vector2(540.0, 258.0)
    add_child(_panel)

    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 8)
    _panel.add_child(box)

    var title := Label.new()
    title.text = "À SIGNALER · REVUE VISUELLE DANS LE JEU"
    title.add_theme_font_size_override("font_size", 19)
    box.add_child(title)

    _context_label = Label.new()
    _context_label.name = "ReportContext"
    box.add_child(_context_label)

    var hint := Label.new()
    hint.text = "Les défauts visuels restent jouables : signale, améliore ou rejette sans bloquer Bruxelles."
    hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(hint)

    _note = LineEdit.new()
    _note.name = "ReportNote"
    _note.placeholder_text = "Ex. façade trop plate, PNJ bizarre, rue vide…"
    _note.max_length = MAX_NOTE_LENGTH
    _note.text_submitted.connect(func(_text: String) -> void: _submit_pending())
    box.add_child(_note)

    var review_actions := HBoxContainer.new()
    review_actions.add_theme_constant_override("separation", 8)
    box.add_child(review_actions)

    var keep := Button.new()
    keep.name = "KeepVisualButton"
    keep.text = "GARDER"
    keep.pressed.connect(_submit_review.bind("GARDER"))
    review_actions.add_child(keep)

    var improve := Button.new()
    improve.name = "ImproveVisualButton"
    improve.text = "AMÉLIORER"
    improve.pressed.connect(_submit_review.bind("AMELIORER"))
    review_actions.add_child(improve)

    var reject := Button.new()
    reject.name = "RejectVisualButton"
    reject.text = "REJETER"
    reject.pressed.connect(_submit_review.bind("REJETER"))
    review_actions.add_child(reject)

    var report_actions := HBoxContainer.new()
    report_actions.add_theme_constant_override("separation", 8)
    box.add_child(report_actions)

    var send := Button.new()
    send.name = "SendVisualIssueButton"
    send.text = "SIGNALER UN PROBLÈME"
    send.pressed.connect(_submit_pending)
    report_actions.add_child(send)

    var cancel := Button.new()
    cancel.text = "ANNULER"
    cancel.pressed.connect(_cancel_pending)
    report_actions.add_child(cancel)
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
        _flash_status("À SIGNALER indisponible · joueur introuvable")
        return
    var image := get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        _flash_status("À SIGNALER indisponible · capture impossible")
        return
    _pending_image = image
    _pending_context = _enrich_context((context as Dictionary).duplicate(true))
    if _selector.has_method("set_menu_open"):
        _selector.call("set_menu_open", false)
    _previous_mouse_mode = Input.mouse_mode
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    var pos: Array = _pending_context.get("position", [0.0, 0.0, 0.0])
    _context_label.text = "%s · %s · %s   (%.1f, %.1f, %.1f)" % [
        str(_pending_context.get("label", "Zone")),
        str(_pending_context.get("quality", "LABO")),
        str(_candidate_payload(_pending_context).get("id", "current")),
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
    return create_report_from_context(note, image, _enrich_context(context as Dictionary), true)

func create_report_from_context(note: String, image: Image, context: Dictionary, export_ticket := true) -> String:
    if image == null or image.is_empty() or context.is_empty():
        return ""
    var zone_id := str(context.get("id", "unknown")).strip_edges()
    if zone_id.is_empty():
        return ""
    _sequence += 1
    var report_id := _make_id(zone_id, _sequence)
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
        "kind": "visual",
        "severity": "VISUAL_MEDIUM",
        "blocking": false,
        "zone": {
            "id": zone_id,
            "label": str(context.get("label", zone_id)),
            "quality": str(context.get("quality", "LABO")),
        },
        "candidate": _candidate_payload(context),
        "player_position": [float(position[0]), float(position[1]), float(position[2])],
        "camera": context.get("camera", {}),
        "look_target": context.get("look_target", {}),
        "build_sha": str(context.get("build_sha", "")),
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
    _refresh_report_button()
    print("PLAYER_REPORT_CREATED: id=%s zone=%s blocking=false pos=%s note=%s" % [report_id, zone_id, str(report["player_position"]), clean_note])
    return report_path

func create_review_from_context(action: String, note: String, image: Image, context: Dictionary) -> String:
    var normalized := action.strip_edges().to_upper()
    if normalized not in REVIEW_ACTIONS or context.is_empty():
        return ""
    var zone_id := str(context.get("id", "unknown")).strip_edges()
    if zone_id.is_empty():
        return ""
    _sequence += 1
    var review_id := _make_id(zone_id, _sequence)
    var candidate := _candidate_payload(context)
    var candidate_id := str(candidate.get("id", ""))
    var preferences := _load_preferences()
    var preferred_before := _preferred_candidate_id(preferences, zone_id)
    if preferred_before.is_empty():
        preferred_before = str(context.get("previous_preferred_candidate", ""))
    var effect := review_effect(normalized, preferred_before)

    var screenshot_path := ""
    if image != null and not image.is_empty():
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REVIEW_DIR))
        screenshot_path = REVIEW_DIR.path_join("%s.png" % review_id)
        if image.save_png(screenshot_path) != OK:
            screenshot_path = ""

    var review := {
        "schema": REVIEW_SCHEMA,
        "id": review_id,
        "action": normalized,
        "state": str(effect.get("state", "")),
        "keeps_active": bool(effect.get("keeps_active", true)),
        "rollback_requested": bool(effect.get("rollback_requested", false)),
        "fallback_candidate_id": str(effect.get("fallback_candidate_id", "")),
        "zone": {
            "id": zone_id,
            "label": str(context.get("label", zone_id)),
            "quality": str(context.get("quality", "LABO")),
        },
        "candidate": candidate,
        "note": note.strip_edges().substr(0, MAX_NOTE_LENGTH),
        "camera": context.get("camera", {}),
        "look_target": context.get("look_target", {}),
        "build_sha": str(context.get("build_sha", "")),
        "captured_unix": int(Time.get_unix_time_from_system()),
        "screenshot_file": screenshot_path,
    }
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REVIEW_DIR))
    var review_path := REVIEW_DIR.path_join("%s.gbreview.json" % review_id)
    var file := FileAccess.open(review_path, FileAccess.WRITE)
    if file == null:
        if not screenshot_path.is_empty():
            DirAccess.remove_absolute(ProjectSettings.globalize_path(screenshot_path))
        return ""
    file.store_string(JSON.stringify(review))
    file.close()

    if normalized == "GARDER" and not candidate_id.is_empty():
        _store_preferred_candidate(preferences, zone_id, candidate)

    review_created.emit(review_id, zone_id, normalized, review_path)
    review_action_requested.emit(normalized, zone_id, candidate_id, str(effect.get("fallback_candidate_id", "")))
    print("PLAYER_VISUAL_REVIEW_CREATED: id=%s zone=%s action=%s candidate=%s state=%s fallback=%s" % [
        review_id,
        zone_id,
        normalized,
        candidate_id,
        str(effect.get("state", "")),
        str(effect.get("fallback_candidate_id", ""))
    ])
    return review_path

func review_effect(action: String, preferred_before := "") -> Dictionary:
    match action.strip_edges().to_upper():
        "GARDER":
            return {
                "state": "PREFERRED",
                "keeps_active": true,
                "rollback_requested": false,
                "fallback_candidate_id": "",
            }
        "AMELIORER":
            return {
                "state": "IMPROVE",
                "keeps_active": true,
                "rollback_requested": false,
                "fallback_candidate_id": "",
            }
        "REJETER":
            return {
                "state": "REJECTED",
                "keeps_active": false,
                "rollback_requested": true,
                "fallback_candidate_id": preferred_before,
            }
    return {}

func report_blocks_playable(report: Dictionary) -> bool:
    if str(report.get("status", "")) != "open":
        return false
    if bool(report.get("blocking", false)):
        return true
    return str(report.get("kind", "")).strip_edges().to_upper() == "HARD_BLOCKER"

# Compatibility contract used by ZoneSelectorRuntime.can_promote_zone().
# It now counts only genuine hard blockers. Visual player reports remain open
# and visible in the review queue without preventing a LABO candidate from
# advancing through the playable pipeline.
func open_report_count(zone_id: String) -> int:
    return blocking_report_count(zone_id)

func blocking_report_count(zone_id: String) -> int:
    return _report_count(zone_id, true)

func visual_report_count(zone_id: String) -> int:
    return _report_count(zone_id, false)

func _report_count(zone_id: String, blocking_only: bool) -> int:
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
        var schema := str(report.get("schema", ""))
        if schema != SCHEMA and schema != LEGACY_SCHEMA:
            continue
        var zone: Variant = report.get("zone", {})
        if not zone is Dictionary or str((zone as Dictionary).get("id", "")) != zone_id:
            continue
        if str(report.get("status", "")) != "open":
            continue
        if blocking_only:
            if report_blocks_playable(report):
                count += 1
        else:
            if not report_blocks_playable(report):
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
        _flash_status("SIGNALÉ · %s · reste jouable" % label)

func _submit_review(action: String) -> void:
    if _pending_context.is_empty():
        _cancel_pending()
        return
    var review_path := create_review_from_context(action, _note.text, _pending_image, _pending_context)
    var label := str(_pending_context.get("label", "Zone"))
    var normalized := action.strip_edges().to_upper()
    _clear_pending()
    if review_path.is_empty():
        _flash_status("ÉCHEC REVUE · décision non enregistrée")
        return
    match normalized:
        "GARDER":
            _flash_status("GARDÉ · %s devient préféré" % label)
        "AMELIORER":
            _flash_status("À AMÉLIORER · %s reste actif" % label)
        "REJETER":
            _flash_status("REJETÉ · rollback demandé · %s" % label)

func _cancel_pending() -> void:
    _clear_pending()

func _clear_pending() -> void:
    _panel.visible = false
    _pending_image = null
    _pending_context.clear()
    if not DisplayServer.is_touchscreen_available():
        Input.mouse_mode = _previous_mouse_mode
    _refresh_report_button()

func _refresh_report_button() -> void:
    if _button == null:
        return
    var count := 0
    if _selector != null and _selector.has_method("current_report_context"):
        var context: Variant = _selector.call("current_report_context")
        if context is Dictionary:
            var zone_id := str((context as Dictionary).get("id", ""))
            if not zone_id.is_empty():
                count = visual_report_count(zone_id)
    _button.text = "À SIGNALER %d" % count if count > 0 else "À SIGNALER"

func _flash_status(message: String) -> void:
    _status.text = message
    _status.visible = true
    _status_timer.start()

func _enrich_context(context: Dictionary) -> Dictionary:
    var enriched := context.duplicate(true)
    var main := get_tree().current_scene
    if main != null:
        enriched["candidate_id"] = str(main.get_meta("grand_bruxelles_visual_candidate_id", enriched.get("candidate_id", "")))
        enriched["candidate_version"] = str(main.get_meta("grand_bruxelles_visual_candidate_version", enriched.get("candidate_version", "current")))
        enriched["previous_preferred_candidate"] = str(main.get_meta("grand_bruxelles_visual_previous_preferred", enriched.get("previous_preferred_candidate", "")))
        enriched["build_sha"] = str(main.get_meta("grand_bruxelles_build_sha", enriched.get("build_sha", "")))
    var camera := get_viewport().get_camera_3d()
    if camera != null:
        enriched["camera"] = {
            "node_path": str(camera.get_path()),
            "position": _vector3_to_array(camera.global_position),
            "rotation": _vector3_to_array(camera.global_rotation),
            "fov": camera.fov,
        }
        enriched["look_target"] = _look_target(camera)
    return enriched

func _look_target(camera: Camera3D) -> Dictionary:
    if camera == null or camera.get_world_3d() == null:
        return {}
    var from := camera.global_position
    var to := from + (-camera.global_transform.basis.z * 140.0)
    var query := PhysicsRayQueryParameters3D.create(from, to)
    query.collide_with_areas = true
    query.collide_with_bodies = true
    var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
    if hit.is_empty():
        return {}
    var collider: Variant = hit.get("collider", null)
    var target := {
        "position": _vector3_to_array(hit.get("position", Vector3.ZERO)),
        "normal": _vector3_to_array(hit.get("normal", Vector3.UP)),
    }
    if collider is Node:
        var node := collider as Node
        target["node_path"] = str(node.get_path())
        target["node_name"] = node.name
        target["instance_id"] = node.get_instance_id()
        if node.has_meta("visual_candidate_id"):
            target["candidate_id"] = str(node.get_meta("visual_candidate_id"))
    return target

func _candidate_payload(context: Dictionary) -> Dictionary:
    var zone_id := str(context.get("id", "unknown"))
    var version := str(context.get("candidate_version", "current")).strip_edges()
    if version.is_empty():
        version = "current"
    var candidate_id := str(context.get("candidate_id", "")).strip_edges()
    if candidate_id.is_empty():
        var target: Variant = context.get("look_target", {})
        if target is Dictionary:
            candidate_id = str((target as Dictionary).get("candidate_id", "")).strip_edges()
    if candidate_id.is_empty():
        candidate_id = "%s:%s" % [zone_id, version]
    return {
        "id": candidate_id,
        "version": version,
        "previous_preferred_id": str(context.get("previous_preferred_candidate", "")),
    }

func _load_preferences() -> Dictionary:
    if not FileAccess.file_exists(PREFERENCES_PATH):
        return {"schema": PREFERENCES_SCHEMA, "zones": {}}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PREFERENCES_PATH))
    if not parsed is Dictionary:
        return {"schema": PREFERENCES_SCHEMA, "zones": {}}
    var preferences := parsed as Dictionary
    if str(preferences.get("schema", "")) != PREFERENCES_SCHEMA or not preferences.get("zones", {}) is Dictionary:
        return {"schema": PREFERENCES_SCHEMA, "zones": {}}
    return preferences

func _preferred_candidate_id(preferences: Dictionary, zone_id: String) -> String:
    var zones: Variant = preferences.get("zones", {})
    if not zones is Dictionary:
        return ""
    var zone: Variant = (zones as Dictionary).get(zone_id, {})
    if not zone is Dictionary:
        return ""
    var candidate: Variant = (zone as Dictionary).get("preferred", {})
    if not candidate is Dictionary:
        return ""
    return str((candidate as Dictionary).get("id", ""))

func _store_preferred_candidate(preferences: Dictionary, zone_id: String, candidate: Dictionary) -> void:
    var zones: Dictionary = preferences.get("zones", {}) if preferences.get("zones", {}) is Dictionary else {}
    zones[zone_id] = {
        "preferred": candidate.duplicate(true),
        "updated_unix": int(Time.get_unix_time_from_system()),
    }
    preferences["schema"] = PREFERENCES_SCHEMA
    preferences["zones"] = zones
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://player_reports"))
    var file := FileAccess.open(PREFERENCES_PATH, FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify(preferences))
        file.close()

func _make_id(zone_id: String, sequence: int) -> String:
    return "%d-%03d-%s-%02d" % [
        int(Time.get_unix_time_from_system()),
        int(Time.get_ticks_msec() % 1000),
        zone_id.replace("/", "-"),
        sequence
    ]

func _vector3_to_array(value: Variant) -> Array:
    if value is Vector3:
        var vector := value as Vector3
        return [vector.x, vector.y, vector.z]
    return [0.0, 0.0, 0.0]

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
