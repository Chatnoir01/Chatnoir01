extends SceneTree

const REPORT_RUNTIME := preload("res://game/scripts/player_issue_report_runtime.gd")
const TEST_DIR := "user://continuity_report_sync_export_test"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("PLAYER_REPORT_SYNC_EXPORT_FAIL: %s" % message)
    _cleanup()
    quit(1)

func _write_report(filename: String, report_id: String, zone_id: String, captured_unix: int, note: String) -> void:
    var payload := {
        "schema": "grand-bruxelles-player-report-v1",
        "id": report_id,
        "status": "open",
        "zone": {"id": zone_id, "label": zone_id.capitalize(), "quality": "LABO"},
        "captured_unix": captured_unix,
        "note": note,
    }
    var file := FileAccess.open(TEST_DIR.path_join(filename), FileAccess.WRITE)
    if file == null:
        _fail("could not create fixture %s" % filename)
        return
    file.store_string(JSON.stringify(payload))
    file.close()

func _cleanup() -> void:
    if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(TEST_DIR)):
        return
    for filename: String in DirAccess.get_files_at(TEST_DIR):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_DIR.path_join(filename)))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_DIR))

func _run() -> void:
    _cleanup()
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))
    var runtime := REPORT_RUNTIME.new()

    var empty: Dictionary = runtime.build_report_sync_snapshot("anneessens", TEST_DIR)
    if str(empty.get("schema", "")) != "grand-bruxelles-continuity-report-sync-v1":
        _fail("wrong sync schema")
        return
    if str(empty.get("state", "")) != "complete_snapshot" or int(empty.get("open_count", -1)) != 0:
        _fail("empty directory did not produce complete zero snapshot")
        return
    if not bool(empty.get("zero_open_is_proven", false)):
        _fail("zero OPEN was not explicitly proven")
        return

    _write_report("new.gbreport.json", "new", "anneessens", 200, "newer")
    _write_report("old.gbreport.json", "old", "anneessens", 100, "oldest")
    _write_report("bourse.gbreport.json", "foreign", "bourse", 50, "other zone")

    var populated: Dictionary = runtime.build_report_sync_snapshot("anneessens", TEST_DIR)
    if int(populated.get("open_count", -1)) != 2:
        _fail("snapshot did not filter to exactly two Anneessens OPEN reports")
        return
    if bool(populated.get("zero_open_is_proven", true)):
        _fail("non-empty snapshot falsely proved zero OPEN")
        return
    if str(populated.get("oldest_open_report_id", "")) != "old":
        _fail("oldest OPEN report was not selected deterministically")
        return
    var rows: Variant = populated.get("open_reports", [])
    if not rows is Array or (rows as Array).size() != 2:
        _fail("open_reports payload malformed")
        return
    var first: Dictionary = (rows as Array)[0]
    if str(first.get("id", "")) != "old" or str(first.get("zone_id", "")) != "anneessens":
        _fail("snapshot rows are not sorted/source-scoped correctly")
        return

    _cleanup()
    print("PLAYER_REPORT_SYNC_EXPORT_OK: zone=anneessens zero_snapshot=true open_snapshot=2 oldest=old foreign_zone_filtered=true")
    quit(0)
