extends SceneTree
const Coordinator = preload("res://game/scripts/mission_save_coordinator.gd")
const SaveStore = preload("res://game/scripts/save_game_store.gd")
const SAVE_PATH := "user://grand_bruxelles_mission_coordinator_test.json"
class FakeMission:
    extends RefCounted
    var mission_id := "midi_to_centre_01"
    var stage := 2
    func get_mission_id() -> String: return mission_id
    func export_state() -> Dictionary: return {"schema_version":1,"mission_id":mission_id,"stage":stage,"stage_count":4}
    func restore_state(state: Dictionary) -> bool:
        if int(state.get("schema_version",-1)) != 1 or str(state.get("mission_id","")) != mission_id: return false
        var candidate := int(state.get("stage",-1))
        if candidate < 0 or candidate > 4: return false
        stage = candidate
        return true
func _initialize() -> void: call_deferred("_run")
func _fail(message:String) -> void:
    push_error("MISSION_SAVE_COORDINATOR_FAIL: %s" % message); _cleanup(); quit(1)
func _run() -> void:
    _cleanup(); var mission := FakeMission.new()
    var save_result := Coordinator.save_mission(SAVE_PATH, mission)
    if not bool(save_result.get("ok",false)): _fail("save failed"); return
    mission.stage = 0
    var load_result := Coordinator.load_mission(SAVE_PATH, mission)
    if not bool(load_result.get("ok",false)) or mission.stage != 2: _fail("round trip failed"); return
    var other := FakeMission.new(); other.mission_id = "other_mission"
    var missing := Coordinator.load_mission(SAVE_PATH, other)
    if bool(missing.get("ok",false)) or str(missing.get("error","")) != "mission_not_found": _fail("wrong mission accepted"); return
    var invalid := {"schema_version":1,"missions":{"midi_to_centre_01":{"schema_version":1,"mission_id":"midi_to_centre_01","stage":99,"stage_count":4}}}
    if not bool(SaveStore.write_snapshot(SAVE_PATH, invalid).get("ok",false)): _fail("invalid fixture write failed"); return
    mission.stage = 1
    var rejected := Coordinator.load_mission(SAVE_PATH, mission)
    if bool(rejected.get("ok",false)) or str(rejected.get("error","")) != "restore_rejected" or mission.stage != 1: _fail("invalid restore handling failed"); return
    _cleanup(); print("MISSION_SAVE_COORDINATOR_OK"); quit(0)
func _cleanup() -> void:
    var absolute := ProjectSettings.globalize_path(SAVE_PATH)
    for suffix:String in ["", ".tmp", ".bak"]:
        var candidate := absolute + suffix
        if FileAccess.file_exists(candidate): DirAccess.remove_absolute(candidate)
