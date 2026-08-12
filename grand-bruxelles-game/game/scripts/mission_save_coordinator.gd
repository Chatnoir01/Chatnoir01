extends RefCounted
class_name MissionSaveCoordinator

const SaveStore = preload("res://game/scripts/save_game_store.gd")
const PAYLOAD_SCHEMA_VERSION: int = 1

static func save_mission(path: String, mission: Object) -> Dictionary:
    if mission == null or not is_instance_valid(mission): return _error("invalid_mission")
    if not mission.has_method("get_mission_id") or not mission.has_method("export_state"): return _error("unsupported_mission")
    var mission_id := str(mission.call("get_mission_id"))
    if mission_id.is_empty(): return _error("invalid_mission_id")
    var exported: Variant = mission.call("export_state")
    if not exported is Dictionary: return _error("invalid_mission_state")
    var state: Dictionary = exported
    if str(state.get("mission_id", "")) != mission_id: return _error("mission_id_mismatch")
    return SaveStore.write_snapshot(path, {"schema_version": PAYLOAD_SCHEMA_VERSION, "missions": {mission_id: state.duplicate(true)}})

static func load_mission(path: String, mission: Object) -> Dictionary:
    if mission == null or not is_instance_valid(mission): return _error("invalid_mission")
    if not mission.has_method("get_mission_id") or not mission.has_method("restore_state"): return _error("unsupported_mission")
    var mission_id := str(mission.call("get_mission_id"))
    var read_result: Dictionary = SaveStore.read_snapshot(path)
    if not bool(read_result.get("ok", false)): return read_result
    var payload: Variant = read_result.get("payload", null)
    if not payload is Dictionary: return _error("invalid_payload")
    var payload_dict: Dictionary = payload
    if int(payload_dict.get("schema_version", -1)) != PAYLOAD_SCHEMA_VERSION: return _error("unsupported_payload_schema")
    var missions: Variant = payload_dict.get("missions", null)
    if not missions is Dictionary: return _error("missing_missions")
    var missions_dict: Dictionary = missions
    if not missions_dict.has(mission_id): return _error("mission_not_found")
    var state: Variant = missions_dict[mission_id]
    if not state is Dictionary: return _error("invalid_mission_state")
    var state_dict: Dictionary = state
    if str(state_dict.get("mission_id", "")) != mission_id: return _error("mission_id_mismatch")
    if not bool(mission.call("restore_state", state_dict.duplicate(true))): return _error("restore_rejected")
    return {"ok": true, "error": "", "mission_id": mission_id}

static func _error(code: String) -> Dictionary:
    return {"ok": false, "error": code}
