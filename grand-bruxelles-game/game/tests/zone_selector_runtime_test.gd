extends SceneTree

const CATALOG_PATH := "res://data/qa/playable_zone_catalog.json"
const REPORT_RUNTIME_PATH := "res://game/scripts/player_issue_report_runtime.gd"
const EXPECTED_IDS := ["midi", "midi_machine_labo", "anneessens", "bourse", "grand_place", "central", "ixelles", "atomium", "jette"]

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    print("ZONE_SELECTOR_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    if not FileAccess.file_exists(CATALOG_PATH): _fail("catalog missing"); return
    if not ResourceLoader.exists(REPORT_RUNTIME_PATH): _fail("report runtime missing"); return
    if str(ProjectSettings.get_setting("autoload/ZoneSelectorRuntime", "")) != "*res://game/scripts/zone_selector_runtime.gd": _fail("autoload missing"); return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
    if typeof(parsed) != TYPE_DICTIONARY: _fail("catalog invalid"); return
    var zones: Variant = (parsed as Dictionary).get("zones", [])
    if not zones is Array: _fail("zones invalid"); return
    var ids: Array[String] = []
    var midi: Dictionary = {}; var midi_machine_labo: Dictionary = {}; var anneessens: Dictionary = {}; var central: Dictionary = {}
    for raw: Variant in zones:
        if not raw is Dictionary: _fail("zone row invalid"); return
        var zone := raw as Dictionary
        var quality := str(zone.get("quality", ""))
        if quality not in ["JOUABLE", "LABO", "LABO_BRUT"]: _fail("invalid quality %s" % quality); return
        for requirement: Variant in zone.get("requires", []):
            if not ResourceLoader.exists(str(requirement)) and not FileAccess.file_exists(str(requirement)): _fail("missing requirement %s" % str(requirement)); return
        match str(zone.get("id", "")):
            "midi": midi = zone
            "midi_machine_labo": midi_machine_labo = zone
            "anneessens": anneessens = zone
            "central": central = zone
        ids.append(str(zone.get("id", "")))
    if ids != EXPECTED_IDS: _fail("unexpected listed zones %s" % str(ids)); return
    if midi.is_empty() or str(midi.get("quality", "")) != "JOUABLE": _fail("canonical Midi contract drifted"); return
    if midi_machine_labo.is_empty() or str(midi_machine_labo.get("quality", "")) != "LABO": _fail("Midi City Machine LABO contract missing"); return
    if anneessens.is_empty() or str(anneessens.get("quality", "")) != "LABO": _fail("Anneessens LABO contract missing"); return
    if central.is_empty() or str(central.get("quality", "")) != "LABO_BRUT" or str(central.get("mode", "")) != "script_zone": _fail("Central LABO_BRUT selector contract missing"); return
    if str(central.get("script", "")) != "res://game/zones/central/central_station_labo.gd": _fail("Central selector script drifted"); return
    var life_script := str(anneessens.get("life_script", "")); var life_minimum: Variant = anneessens.get("life_minimum", {})
    if life_script.is_empty() or not ResourceLoader.exists(life_script): _fail("Anneessens life runtime missing"); return
    if not life_minimum is Dictionary or int((life_minimum as Dictionary).get("civilians", 0)) <= 0 or int((life_minimum as Dictionary).get("moving_vehicles", 0)) <= 0: _fail("Anneessens minimum-life gate missing"); return

    var selector := get_root().get_node_or_null("ZoneSelectorRuntime")
    if selector == null or not selector.has_method("available_zones"): _fail("runtime selector missing"); return
    await process_frame
    var available: Array = selector.call("available_zones")
    if available.size() != EXPECTED_IDS.size(): _fail("runtime filtered a proven zone"); return
    var runtime_central: Dictionary = {}
    for raw_zone: Variant in available:
        if raw_zone is Dictionary and str((raw_zone as Dictionary).get("id", "")) == "central": runtime_central = raw_zone as Dictionary; break
    if runtime_central.is_empty() or str(runtime_central.get("quality", "")) != "LABO_BRUT": _fail("Central missing from runtime list"); return
    var toggle := selector.get_node_or_null("ZoneSelectorToggle") as Button
    if toggle == null or toggle.text != "ZONES" or not toggle.is_visible_in_tree(): _fail("production ZONES button not player-visible"); return
    var panel := selector.get_node_or_null("ZoneSelectorPanel") as PanelContainer
    if panel == null: _fail("zone selector panel missing"); return
    selector.call("set_menu_open", true); await process_frame
    var central_button := panel.find_child("Zone_central", true, false) as Button
    if central_button == null or not central_button.is_visible_in_tree() or not central_button.text.contains("LABO_BRUT"): _fail("Central button not visible/honest in production selector"); return
    selector.call("set_menu_open", false)

    if not selector.has_method("reporting_runtime") or not selector.has_method("can_promote_zone"): _fail("reporting contract missing"); return
    var reporter: Node = selector.call("reporting_runtime")
    if reporter == null or reporter.get_node_or_null("ReportButton") == null: _fail("reporter missing"); return
    for method_name: String in ["begin_report", "create_report_from_image", "create_report_from_context", "open_report_count"]:
        if not reporter.has_method(method_name): _fail("reporter method missing %s" % method_name); return

    var sample := Image.create(8, 8, false, Image.FORMAT_RGBA8); sample.fill(Color(0.2, 0.3, 0.4, 1.0))
    var report_context := {"id": "anneessens", "label": "Anneessens", "quality": "LABO", "position": [-272.04, 1.05, -217.07]}
    var report_path := str(reporter.call("create_report_from_context", "sol trou", sample, report_context, false))
    if report_path.is_empty() or not FileAccess.file_exists(report_path): _fail("report ticket not written"); return
    var report_variant: Variant = JSON.parse_string(FileAccess.get_file_as_string(report_path))
    if not report_variant is Dictionary: _fail("report ticket invalid"); return
    var report := report_variant as Dictionary; var report_zone: Variant = report.get("zone", {}); var screenshot: Variant = report.get("screenshot", {})
    if report.get("schema", "") != "grand-bruxelles-player-report-v1" or report.get("status", "") != "open": _fail("report schema/status invalid"); return
    if not report_zone is Dictionary or str((report_zone as Dictionary).get("id", "")) != "anneessens" or report.get("note", "") != "sol trou": _fail("report player context invalid"); return
    if not screenshot is Dictionary or not str((screenshot as Dictionary).get("data", "")).begins_with("iVBOR"): _fail("report screenshot missing"); return
    if int(reporter.call("open_report_count", "anneessens")) != 1 or bool(selector.call("can_promote_zone", "anneessens")): _fail("open report did not block LABO promotion"); return
    var screenshot_path := str(report.get("screenshot_file", "")); DirAccess.remove_absolute(ProjectSettings.globalize_path(report_path)); if not screenshot_path.is_empty(): DirAccess.remove_absolute(ProjectSettings.globalize_path(screenshot_path))
    if not bool(selector.call("can_promote_zone", "anneessens")): _fail("promotion gate stayed blocked after report removal"); return
    print("PLAYER_REPORT_CONTRACT_OK: zone=anneessens note=sol trou screenshot=png promotion_blocked=true")

    print("ZONE_SELECTOR_OK: listed=%d central=LABO_BRUT zones_button=true central_button=true reporting=true no_invisible_quarantine=true" % available.size())
    quit(0)
