extends SceneTree

const SaveStore = preload("res://game/scripts/save_game_store.gd")
const SAVE_PATH: String = "user://grand_bruxelles_save_store_test.json"


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("SAVE_STORE_FAIL: %s" % message)
    _cleanup()
    quit(1)


func _run() -> void:
    _cleanup()

    var payload: Dictionary = {
        "missions": {
            "midi_to_centre_01": {
                "schema_version": 1,
                "mission_id": "midi_to_centre_01",
                "stage": 2,
            }
        },
        "economy": {"cash_eur": 125.5},
        "world": {"day_index": 3, "time_minutes": 485},
    }

    var write_result: Dictionary = SaveStore.write_snapshot(SAVE_PATH, payload)
    if not bool(write_result.get("ok", false)):
        _fail("valid snapshot write failed: %s" % str(write_result))
        return

    var read_result: Dictionary = SaveStore.read_snapshot(SAVE_PATH)
    if not bool(read_result.get("ok", false)):
        _fail("valid snapshot read failed: %s" % str(read_result))
        return
    var loaded: Dictionary = read_result.get("payload", {})
    if int(loaded.get("missions", {}).get("midi_to_centre_01", {}).get("stage", -1)) != 2:
        _fail("mission stage did not survive save/load")
        return
    if not is_equal_approx(float(loaded.get("economy", {}).get("cash_eur", 0.0)), 125.5):
        _fail("economy value did not survive save/load")
        return

    var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
    if file == null:
        _fail("could not reopen test save for corruption regression")
        return
    var envelope: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not envelope is Dictionary:
        _fail("written save envelope was not valid JSON")
        return
    envelope["payload_sha256"] = "0000"
    file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    file.store_string(JSON.stringify(envelope))
    file.close()

    var corrupt_result: Dictionary = SaveStore.read_snapshot(SAVE_PATH)
    if bool(corrupt_result.get("ok", false)):
        _fail("checksum-corrupted save was accepted")
        return
    if str(corrupt_result.get("error", "")) != "checksum_mismatch":
        _fail("checksum corruption returned wrong error: %s" % str(corrupt_result))
        return

    file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    file.store_string("{definitely-not-json")
    file.close()
    var invalid_json_result: Dictionary = SaveStore.read_snapshot(SAVE_PATH)
    if str(invalid_json_result.get("error", "")) != "invalid_json":
        _fail("invalid JSON was not rejected deterministically")
        return

    _cleanup()
    print("SAVE_STORE_OK: atomic write/read + checksum/corruption guards passed")
    quit(0)


func _cleanup() -> void:
    var absolute_path: String = ProjectSettings.globalize_path(SAVE_PATH)
    for suffix: String in ["", ".tmp", ".bak"]:
        var candidate: String = absolute_path + suffix
        if FileAccess.file_exists(candidate):
            DirAccess.remove_absolute(candidate)
