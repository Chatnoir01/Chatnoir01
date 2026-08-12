extends SceneTree

const Coordinator = preload("res://game/scripts/game_state_save_coordinator.gd")
const SAVE_PATH := "user://grand_bruxelles_global_save_test.json"

class FakeDomain:
    extends RefCounted
    var value: int
    var reject_precheck := false
    var fail_restore := false

    func _init(initial_value: int) -> void:
        value = initial_value

    func export_state() -> Dictionary:
        return {"schema_version": 1, "value": value}

    func can_restore_state(state: Dictionary) -> bool:
        if reject_precheck:
            return false
        return int(state.get("schema_version", -1)) == 1 and state.has("value")

    func restore_state(state: Dictionary) -> bool:
        if fail_restore:
            fail_restore = false
            return false
        if not can_restore_state(state):
            return false
        value = int(state["value"])
        return true

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GAME_STATE_SAVE_COORDINATOR_FAIL: %s" % message)
    _cleanup()
    quit(1)

func _run() -> void:
    _cleanup()

    var player := FakeDomain.new(12)
    var world := FakeDomain.new(34)
    var providers := {"player": player, "world": world}

    var save_result := Coordinator.save_domains(SAVE_PATH, providers)
    if not bool(save_result.get("ok", false)):
        _fail("save failed")
        return

    player.value = 1
    world.value = 2
    var load_result := Coordinator.load_domains(SAVE_PATH, providers)
    if not bool(load_result.get("ok", false)) or player.value != 12 or world.value != 34:
        _fail("round trip failed")
        return

    player.value = 5
    world.value = 6
    world.reject_precheck = true
    var rejected := Coordinator.load_domains(SAVE_PATH, providers)
    world.reject_precheck = false
    if bool(rejected.get("ok", false)) or str(rejected.get("error", "")) != "restore_precheck_rejected":
        _fail("precheck rejection not reported")
        return
    if player.value != 5 or world.value != 6:
        _fail("precheck rejection mutated live state")
        return

    player.value = 7
    world.value = 8
    world.fail_restore = true
    var failed_apply := Coordinator.load_domains(SAVE_PATH, providers)
    if bool(failed_apply.get("ok", false)) or str(failed_apply.get("error", "")) != "restore_rejected":
        _fail("apply failure not reported")
        return
    if not bool(failed_apply.get("rolled_back", false)) or player.value != 7 or world.value != 8:
        _fail("transaction rollback failed")
        return

    _cleanup()
    print("GAME_STATE_SAVE_COORDINATOR_OK")
    quit(0)

func _cleanup() -> void:
    var absolute := ProjectSettings.globalize_path(SAVE_PATH)
    for suffix: String in ["", ".tmp", ".bak"]:
        var candidate := absolute + suffix
        if FileAccess.file_exists(candidate):
            DirAccess.remove_absolute(candidate)
