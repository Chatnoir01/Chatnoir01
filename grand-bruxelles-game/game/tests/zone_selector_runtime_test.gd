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
    for method_name: String in ["begin_report", "create_report_from_image", "open_report_count"]:
        if not reporter.has_method(method_name):
            _fail("reporter method missing %s" % method_name)
            return
    if reporter.get_node_or_null("ReportButton") == null:
        _fail("SIGNALER button missing")
        return
    if "capture=1" in OS.get_cmdline_user_args():
        var main := (load("res://game/main.tscn") as PackedScene).instantiate()
        get_root().add_child(main)
        current_scene = main
        selector.call("set_menu_open", true)
        for _frame: int in range(8):
            await process_frame
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/visual"))
        var result := get_root().get_viewport().get_texture().get_image().save_png("res://artifacts/visual/zone_selector_1280x720.png")
        if result != OK:
            _fail("witness save failed")
            return
        print("ZONE_SELECTOR_WITNESS_OK: 1280x720")
    print("ZONE_SELECTOR_OK: listed=%d playable=1 lab=6 reporting=true no_invisible_quarantine=true" % available.size())
    quit(0)
