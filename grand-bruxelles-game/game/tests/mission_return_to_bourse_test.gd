extends SceneTree

const AUTOSAVE_PATH := "user://grand_bruxelles_return_mission_test.json"
const PRIMARY_CHECKPOINTS: Array[Vector3] = [
    Vector3(-272.04, 0.08, -217.07),
    Vector3(81.54, 0.08, -664.58),
    Vector3(319.01, 0.08, -535.20),
]
const BOURSE := Vector3(81.54, 0.08, -664.58)


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("MISSION_RETURN_TO_BOURSE_FAIL: %s" % message)
    _cleanup()
    quit(1)


func _run() -> void:
    _cleanup()
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    scene.get_node("MissionCheckpointAutosave").set("autosave_path", AUTOSAVE_PATH)
    root.add_child(scene)
    await process_frame
    await physics_frame

    var primary: Node = scene.get_node("MissionDriveToCenter")
    var return_mission: Node = scene.get_node("MissionReturnToBourse")
    var wallet: Node = scene.get_node("Wallet")
    var runtime: Node = scene.get_node("RuntimeGameplayState")
    var label: Label = scene.get_node("MissionLabel")
    var player: CharacterBody3D = scene.get_node("Player")
    var vehicle: CharacterBody3D = scene.get_node("PrototypeCar")

    vehicle.call("enter_driver", player)
    await physics_frame
    for checkpoint: Vector3 in PRIMARY_CHECKPOINTS:
        vehicle.global_position = checkpoint
        vehicle.velocity = Vector3.ZERO
        vehicle.set("speed", 0.0)
        await physics_frame
        await process_frame
    if int(wallet.call("get_cash_cents")) != 35000 or int(return_mission.call("get_state")) != 1:
        _fail("primary completion did not unlock the return mission")
        return

    var start_event := InputEventKey.new()
    start_event.keycode = KEY_F
    start_event.pressed = true
    return_mission.call("_unhandled_input", start_event)
    if int(return_mission.call("get_state")) != 1:
        _fail("return mission started while the player was still driving")
        return

    vehicle.call("exit_driver")
    player.global_position = PRIMARY_CHECKPOINTS[-1] + Vector3(2.0, 1.0, 0.0)
    return_mission.call("_unhandled_input", start_event)
    await process_frame
    if int(return_mission.call("get_state")) != 2 or not label.text.contains("PLACE DE LA BOURSE"):
        _fail("on-foot interaction did not start the return mission")
        return
    if not FileAccess.file_exists(AUTOSAVE_PATH):
        _fail("starting the return mission did not create an autosave")
        return

    vehicle.global_position = player.global_position + Vector3(2.0, 0.0, 0.0)
    vehicle.call("enter_driver", player)
    vehicle.global_position = BOURSE
    vehicle.velocity = Vector3.ZERO
    vehicle.set("speed", 0.0)
    await physics_frame
    await process_frame
    if int(return_mission.call("get_state")) != 3:
        _fail("Bourse destination did not complete the return mission")
        return
    if int(wallet.call("get_cash_cents")) != 47000 or not label.text.contains("Récompense 120 €"):
        _fail("return mission reward is missing or not visible")
        return
    await physics_frame
    if int(wallet.call("get_cash_cents")) != 47000:
        _fail("return mission paid its reward more than once")
        return

    var completed_state: Dictionary = runtime.call("export_state")
    var impossible_state := completed_state.duplicate(true)
    impossible_state["mission"]["stage"] = 1
    impossible_state["return_mission"]["state"] = 2
    impossible_state["return_mission"]["reward_claimed"] = false
    if bool(runtime.call("can_restore_state", impossible_state)):
        _fail("active return mission was accepted before primary completion")
        return

    return_mission.call("restart_campaign")
    wallet.call("reset")
    if not bool(runtime.call("restore_state", completed_state)):
        _fail("completed return mission state was rejected")
        return
    if int(return_mission.call("get_state")) != 3 or int(wallet.call("get_cash_cents")) != 47000:
        _fail("return mission and wallet did not round trip")
        return

    var legacy_state := completed_state.duplicate(true)
    legacy_state.erase("return_mission")
    if not bool(runtime.call("restore_state", legacy_state)):
        _fail("pre-return-mission runtime save is not backward compatible")
        return
    if int(return_mission.call("get_state")) != 1:
        _fail("legacy completed primary save did not unlock the new mission")
        return

    scene.queue_free()
    await process_frame
    _cleanup()
    print("MISSION_RETURN_TO_BOURSE_OK")
    quit(0)


func _cleanup() -> void:
    var absolute := ProjectSettings.globalize_path(AUTOSAVE_PATH)
    for suffix: String in ["", ".tmp", ".bak"]:
        var candidate := absolute + suffix
        if FileAccess.file_exists(candidate):
            DirAccess.remove_absolute(candidate)
