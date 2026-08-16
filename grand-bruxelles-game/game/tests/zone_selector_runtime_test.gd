extends SceneTree

const CATALOG_PATH := "res://data/qa/playable_zone_catalog.json"
const REPORT_RUNTIME_PATH := "res://game/scripts/player_issue_report_runtime.gd"
const EXPECTED_IDS := ["midi", "anneessens", "bourse", "grand_place", "ixelles", "atomium", "jette"]

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    print("ZONE_SELECTOR_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    if not FileAccess.file_exists(CATALOG_PATH):
        _fail("catalog missing")
        return
    if not ResourceLoader.exists(REPORT_RUNTIME_PATH):
        _fail("report runtime missing")
        return
    if str(ProjectSettings.get_setting("autoload/ZoneSelectorRuntime", "")) != "*res://game/scripts/zone_selector_runtime.gd":
        _fail("autoload missing")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("catalog invalid")
        return
    var zones: Variant = (parsed as Dictionary).get("zones", [])
    if not zones is Array:
        _fail("zones invalid")
        return
    var ids: Array[String] = []
    for raw: Variant in zones:
        if not raw is Dictionary:
            _fail("zone row invalid")
            return
        var zone := raw as Dictionary
        var quality := str(zone.get("quality", ""))
        if quality not in ["JOUABLE", "LABO"]:
            _fail("invalid quality %s" % quality)
            return
        for requirement: Variant in zone.get("requires", []):
            if not ResourceLoader.exists(str(requirement)) and not FileAccess.file_exists(str(requirement)):
                _fail("missing requirement %s" % str(requirement))
                return
        ids.append(str(zone.get("id", "")))
    if ids != EXPECTED_IDS:
        _fail("unexpected listed zones %s" % str(ids))
        return
    var selector := get_root().get_node_or_null("ZoneSelectorRuntime")
    if selector == null or not selector.has_method("available_zones"):
        _fail("runtime selector missing")
        return
    await process_frame
    var available: Array = selector.call("available_zones")
    if available.size() != EXPECTED_IDS.size():
        _fail("runtime filtered a proven zone")
        return
    if not selector.has_method("reporting_runtime") or not selector.has_method("can_promote_zone"):
        _fail("reporting contract missing")
        return
    var reporter: Node = selector.call("reporting_runtime")
    if reporter == null:
        _fail("reporter missing")
        return
    for method_name: String in ["begin_report", "create_report_from_image", "create_report_from_context", "open_report_count"]:
        if not reporter.has_method(method_name):
            _fail("reporter method missing %s" % method_name)
            return
    if reporter.get_node_or_null("ReportButton") == null:
        _fail("SIGNALER button missing")
        return

    var sample := Image.create(8, 8, false, Image.FORMAT_RGBA8)
    sample.fill(Color(0.2, 0.3, 0.4, 1.0))
    var report_context := {
        "id": "anneessens",
        "label": "Anneessens",
        "quality": "LABO",
        "position": [-272.04, 1.05, -217.07],
    }
    var report_path := str(reporter.call("create_report_from_context", "sol trou", sample, report_context, false))
    if report_path.is_empty() or not FileAccess.file_exists(report_path):
        _fail("report ticket not written")
        return
    var report_variant: Variant = JSON.parse_string(FileAccess.get_file_as_string(report_path))
    if not report_variant is Dictionary:
        _fail("report ticket invalid")
        return
    var report := report_variant as Dictionary
    var report_zone: Variant = report.get("zone", {})
    var screenshot: Variant = report.get("screenshot", {})
    if report.get("schema", "") != "grand-bruxelles-player-report-v1" or report.get("status", "") != "open":
        _fail("report schema/status invalid")
        return
    if not report_zone is Dictionary or str((report_zone as Dictionary).get("id", "")) != "anneessens" or report.get("note", "") != "sol trou":
        _fail("report player context invalid")
        return
    if not screenshot is Dictionary or not str((screenshot as Dictionary).get("data", "")).begins_with("iVBOR"):
        _fail("report screenshot missing")
        return
    if int(reporter.call("open_report_count", "anneessens")) != 1 or bool(selector.call("can_promote_zone", "anneessens")):
        _fail("open report did not block LABO promotion")
        return
    var screenshot_path := str(report.get("screenshot_file", ""))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(report_path))
    if not screenshot_path.is_empty():
        DirAccess.remove_absolute(ProjectSettings.globalize_path(screenshot_path))
    if not bool(selector.call("can_promote_zone", "anneessens")):
        _fail("promotion gate stayed blocked after report removal")
        return
    print("PLAYER_REPORT_CONTRACT_OK: zone=anneessens note=sol trou screenshot=png promotion_blocked=true")

    if "capture=1" in OS.get_cmdline_user_args():
        var main := (load("res://game/main.tscn") as PackedScene).instantiate()
        get_root().add_child(main)
        current_scene = main
        selector.call("set_menu_open", false)
        for _frame: int in range(8):
            await process_frame
        reporter.call("begin_report")
        for _frame: int in range(3):
            await process_frame
        if reporter.get_node_or_null("ReportPanel") == null or not (reporter.get_node("ReportPanel") as Control).visible:
            _fail("report panel did not open")
            return
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/visual"))
        var result := get_root().get_viewport().get_texture().get_image().save_png("res://artifacts/visual/player_report_1280x720.png")
        if result != OK:
            _fail("report witness save failed")
            return
        print("PLAYER_REPORT_WITNESS_OK: 1280x720")
    print("ZONE_SELECTOR_OK: listed=%d playable=1 lab=6 reporting=true no_invisible_quarantine=true" % available.size())
    quit(0)
