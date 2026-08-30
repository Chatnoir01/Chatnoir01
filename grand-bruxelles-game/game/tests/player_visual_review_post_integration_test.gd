extends SceneTree

const REPORTER_SCRIPT := preload("res://game/scripts/player_issue_report_runtime.gd")
const CATALOG_PATH := "res://data/qa/playable_zone_catalog.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("PLAYER_VISUAL_REVIEW_POST_INTEGRATION_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var reporter := REPORTER_SCRIPT.new()
    root.add_child(reporter)
    await process_frame

    var visual_report := {
        "schema": "grand-bruxelles-player-report-v2",
        "status": "open",
        "kind": "visual",
        "severity": "VISUAL_MAJOR",
        "blocking": false,
    }
    if bool(reporter.call("report_blocks_playable", visual_report)):
        _fail("visual report unexpectedly blocks playable advancement")
        return

    var legacy_visual_report := {
        "schema": "grand-bruxelles-player-report-v1",
        "status": "open",
    }
    if bool(reporter.call("report_blocks_playable", legacy_visual_report)):
        _fail("legacy player report unexpectedly blocks playable advancement")
        return

    var hard_report := {
        "schema": "grand-bruxelles-player-report-v2",
        "status": "open",
        "kind": "HARD_BLOCKER",
        "blocking": true,
    }
    if not bool(reporter.call("report_blocks_playable", hard_report)):
        _fail("hard blocker no longer blocks playable advancement")
        return

    var keep: Dictionary = reporter.call("review_effect", "GARDER", "candidate-old")
    if str(keep.get("state", "")) != "PREFERRED" or not bool(keep.get("keeps_active", false)):
        _fail("GARDER must keep candidate active and mark it preferred")
        return

    var improve: Dictionary = reporter.call("review_effect", "AMELIORER", "candidate-old")
    if str(improve.get("state", "")) != "IMPROVE" or not bool(improve.get("keeps_active", false)):
        _fail("AMELIORER must keep current candidate active")
        return

    var reject: Dictionary = reporter.call("review_effect", "REJETER", "candidate-old")
    if str(reject.get("state", "")) != "REJECTED" or bool(reject.get("keeps_active", true)):
        _fail("REJETER must deactivate candidate semantics")
        return
    if not bool(reject.get("rollback_requested", false)) or str(reject.get("fallback_candidate_id", "")) != "candidate-old":
        _fail("REJETER must request rollback to previous preferred candidate")
        return

    if not FileAccess.file_exists(CATALOG_PATH):
        _fail("playable zone catalog missing")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
    if not parsed is Dictionary:
        _fail("playable zone catalog invalid")
        return
    var quality_model: Variant = (parsed as Dictionary).get("quality_model", {})
    if not quality_model is Dictionary:
        _fail("quality_model missing")
        return
    if bool((quality_model as Dictionary).get("jouable_requires_human_promotion", true)):
        _fail("human promotion is still mandatory")
        return
    if bool((quality_model as Dictionary).get("open_player_report_blocks_jouable", true)):
        _fail("open player report still blocks JOUABLE")
        return
    if not bool((quality_model as Dictionary).get("hard_blocker_blocks_jouable", false)):
        _fail("hard blockers must remain blocking")
        return

    print("PLAYER_VISUAL_REVIEW_POST_INTEGRATION_OK: visual=soft hard=blocking garder=PREFERRED ameliorer=IMPROVE rejeter=REJECTED")
    quit(0)
