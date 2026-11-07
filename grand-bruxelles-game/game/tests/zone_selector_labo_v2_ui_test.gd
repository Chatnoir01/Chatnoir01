extends SceneTree

const CATALOG_PATH := "res://data/qa/playable_zone_catalog.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ZONE_SELECTOR_LABO_V2_FAIL: %s" % message)
    quit(1)

func _zone_by_id(zones: Array, zone_id: String) -> Dictionary:
    for raw: Variant in zones:
        if raw is Dictionary and str((raw as Dictionary).get("id", "")) == zone_id:
            return raw as Dictionary
    return {}

func _cleanup_reports() -> void:
    var report_dir := "user://player_reports/open"
    if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(report_dir)):
        return
    for filename: String in DirAccess.get_files_at(report_dir):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(report_dir.path_join(filename)))

func _run() -> void:
    _cleanup_reports()
    var selector := get_root().get_node_or_null("ZoneSelectorRuntime")
    if selector == null:
        _fail("autoload selector missing")
        return
    await process_frame
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
    if not parsed is Dictionary:
        _fail("catalog missing")
        return
    var zones: Array = selector.call("parse_catalog_document", parsed as Dictionary)
    var anneessens := _zone_by_id(zones, "anneessens")
    if anneessens.is_empty():
        _fail("Anneessens missing")
        return

    var missing_resource := {
        "id": "missing",
        "label": "Missing",
        "quality": "LABO",
        "mode": "fast_travel",
        "destination": "midi",
        "requires": ["res://definitely/missing.resource"]
    }
    if str(selector.call("listing_state", missing_resource, null)) != "NON_LISTE":
        _fail("missing resource was still listable")
        return

    var bad_spawn := {
        "id": "bad_spawn",
        "label": "Bad Spawn",
        "quality": "LABO",
        "mode": "position",
        "spawn": ["wall", 1.0, 2.0],
        "requires": ["res://game/main.tscn"]
    }
    if str(selector.call("listing_state", bad_spawn, null)) != "NON_LISTE":
        _fail("invalid spawn was still listable")
        return

    var raw_lab := {
        "id": "raw_lab",
        "label": "Raw Lab",
        "quality": "LABO_BRUT",
        "mode": "fast_travel",
        "destination": "midi",
        "requires": ["res://game/main.tscn"]
    }
    if str(selector.call("listing_state", raw_lab, null)) != "LABO_BRUT" or str(selector.call("_badge_text", "LABO_BRUT")) != "LABO·BRUT":
        _fail("LABO_BRUT badge contract failed")
        return

    var reporter: Node = selector.call("reporting_runtime")
    if reporter == null:
        _fail("reporter missing")
        return
    var sample := Image.create(8, 8, false, Image.FORMAT_RGBA8)
    sample.fill(Color(0.2, 0.3, 0.4, 1.0))
    var report_context := {
        "id": "anneessens",
        "label": "Anneessens",
        "quality": "LABO",
        "position": [-272.04, 1.05, -217.07]
    }
    var report_path := str(reporter.call("create_report_from_context", "preuve report", sample, report_context, false))
    if report_path.is_empty():
        _fail("could not create OPEN report")
        return
    if str(selector.call("listing_state", anneessens, null)) != "LABO_REPORT":
        _fail("OPEN report did not derive LABO_REPORT")
        return
    selector.call("_rebuild_zone_rows")
    var anneessens_button := selector.get_node_or_null("ZoneSelectorPanel/VBoxContainer/ZoneList/Zone_anneessens")
    if anneessens_button == null:
        anneessens_button = selector.find_child("Zone_anneessens", true, false)
    if anneessens_button == null or not str((anneessens_button as Button).text).contains("LABO·REPORT"):
        _fail("Anneessens REPORT badge not visible in menu row")
        return
    var report_help := selector.find_child("ZoneReportHelp", true, false) as Label
    if report_help == null or not report_help.visible:
        _fail("REPORT help line not visible")
        return

    if "capture=1" in OS.get_cmdline_user_args():
        var main := (load("res://game/main.tscn") as PackedScene).instantiate()
        get_root().add_child(main)
        current_scene = main
        for _frame: int in range(8):
            await process_frame
        selector.call("set_menu_open", true)
        for _frame: int in range(5):
            await process_frame
        DisplayServer.window_set_size(Vector2i(1280, 720))
        for _frame: int in range(3):
            await process_frame
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/visual"))
        var save_result := get_root().get_viewport().get_texture().get_image().save_png("res://artifacts/visual/zone_selector_labo_v2_1280x720.png")
        if save_result != OK:
            _fail("menu witness save failed")
            return
        print("ZONE_SELECTOR_LABO_V2_WITNESS_OK: anneessens=LABO_REPORT menu=1280x720")

    _cleanup_reports()
    print("ZONE_SELECTOR_LABO_V2_OK: missing=NON_LISTE bad_spawn=NON_LISTE brut=LABO_BRUT report=LABO_REPORT")
    quit(0)
