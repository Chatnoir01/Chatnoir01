extends SceneTree

const Coordinator = preload("res://game/scripts/mission_save_coordinator.gd")
const SaveStore = preload("res://game/scripts/save_game_store.gd")
const SAVE_PATH: String = "user://grand_bruxelles_mission_coordinator_test.json"


class FakeMission:
    extends RefCounted

    var mission_id: String = "midi_to_centre_01"
    var stage: int = 2

    func get_mission_id() -> String:
        return mission_id

    func export_state() -> Dictionary:
        return {
            "schema_version": 1,
            "mission_id": mission_id,
            "stage": stage,
            "stage_count": 4,
        }

    func restore_state(state: Dictionary) -> bool:
        if int(state.get("schema_version", -1)) != 1:
            return false
        if str(state.get("mission_id", "")) != mission_id:
            return false
        var candidate: int = int(state.get("stage", -1))
        if candidate < 0 or candidate > 4:
            return false
        stage = candidate
        return true


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("MISSION_SAVE_COORDINATOR_FAIL: %s" % message)
    _cleanup()
    quit(1)


func _run() -> void:
    _cleanup()

    var mission := FakeMission.new()
    var save_result: Dictionary = Coordinator.save_mission(SAVE_PATH, mission)
    if not bool(save_result.get("ok", false)):
        _fail("mission save failed: %s" % str(save_result))
        return

    mission.stage = 0
    var load_result: Dictionary = Coordinator.load_mission(SAVE_PATH, mission)
    if not bool(load_result.get("ok", false)):
        _fail("mission load failed: %s" % str(load_result))
        return
    if mission.stage != 2:
        _fail("mission stage was not restored from persisted snapshot")
        return

    var other := FakeMission.new()
    other.mission_id = "other_mission"
    var missing_result: Dictionary = Coordinator.load_mission(SAVE_PATH, other)
    if bool(missing_result.get("ok", false)) or str(missing_result.get("error", "")) != "mission_not_found":
        _fail("save for another mission was not rejected deterministically")
        return

    var invalid_payload: Dictionary = {
        "schema_version": 1,
        "missions": {
            "midi_to_centre_01": {
                "schema_version": 1,
                "mission_id": "midi_to_centre_01",
                "stage": 99,
                "stage_count": 4,
            }
        },
    }
    var overwrite_result: Dictionary = SaveStore.write_snapshot(SAVE_PATH, invalid_payload)
    if not bool(overwrite_result.get("ok", false)):
        _fail("could not prepare invalid-state regression snapshot")
        return

    mission.stage = 1
    var rejected_result: Dictionary = Coordinator.load_mission(SAVE_PATH, mission)
    if bool(rejected_result.get("ok", false)) or str(rejected_result.get("error", "")) != "restore_rejected":
        _fail("mission accepted an out-of-range persisted stage")
        return
    if mission.stage != 1:
        _fail("rejected restore mutated the live mission state")
        return

    _cleanup()
    print("MISSION_SAVE_COORDINATOR_OK: mission round-trip + identity/state rejection passed")
    quit(0)


func _cleanup() -> void:
    var absolute_path: String = ProjectSettings.globalize_path(SAVE_PATH)
    for suffix: String in ["", ".tmp", ".bak"]:
        var candidate: String = absolute_path + suffix
        if FileAccess.file_exists(candidate):
            DirAccess.remove_absolute(candidate)
