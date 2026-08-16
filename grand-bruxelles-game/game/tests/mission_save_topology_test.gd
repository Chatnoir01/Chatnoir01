extends SceneTree

const MissionSaveCoordinator = preload("res://game/scripts/mission_save_coordinator.gd")
const SaveStore = preload("res://game/scripts/save_game_store.gd")
const SAVE_PATH := "user://grand_bruxelles_mission_topology_test.json"

class FakeMission:
    extends RefCounted
    var restore_called := false

    func get_mission_id() -> String:
        return "topology_contract_test"

    func get_stage_count() -> int:
        return 4

    func restore_state(_state: Dictionary) -> bool:
        restore_called = true
        return true


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("MISSION_SAVE_TOPOLOGY_FAIL: %s" % message)
    _cleanup()
    quit(1)


func _write_state(stage_count: int) -> bool:
    var payload := {
        "schema_version": 1,
        "missions": {
            "topology_contract_test": {
                "schema_version": 1,
                "mission_id": "topology_contract_test",
                "stage": 1,
                "stage_count": stage_count,
            }
        }
    }
    return bool(SaveStore.write_snapshot(SAVE_PATH, payload).get("ok", false))


func _run() -> void:
    _cleanup()
    var mission := FakeMission.new()

    if not _write_state(3):
        _fail("could not write mismatched topology fixture")
        return
    var mismatched := MissionSaveCoordinator.load_mission(SAVE_PATH, mission)
    if bool(mismatched.get("ok", false)):
        _fail("snapshot from a different checkpoint topology must be rejected")
        return
    if str(mismatched.get("error", "")) != "mission_topology_mismatch":
        _fail("topology mismatch must return a deterministic error code")
        return
    if mission.restore_called:
        _fail("mission restore must not run for mismatched topology")
        return

    mission.restore_called = false
    if not _write_state(4):
        _fail("could not write matching topology fixture")
        return
    var matching := MissionSaveCoordinator.load_mission(SAVE_PATH, mission)
    if not bool(matching.get("ok", false)):
        _fail("matching mission topology should restore")
        return
    if not mission.restore_called:
        _fail("matching mission topology did not reach restore_state")
        return

    print("MISSION_SAVE_TOPOLOGY_OK: incompatible checkpoint topology rejected before restore")
    _cleanup()
    quit(0)


func _cleanup() -> void:
    var absolute := ProjectSettings.globalize_path(SAVE_PATH)
    for suffix: String in ["", ".tmp", ".bak"]:
        var candidate := absolute + suffix
        if FileAccess.file_exists(candidate):
            DirAccess.remove_absolute(candidate)
