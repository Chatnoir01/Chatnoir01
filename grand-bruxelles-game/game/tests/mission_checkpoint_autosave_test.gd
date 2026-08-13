extends SceneTree

const AUTOSAVE_PATH := "user://grand_bruxelles_checkpoint_autosave_test.json"
const CORRUPT_PATH := "user://grand_bruxelles_checkpoint_autosave_corrupt_test.json"
const FIRST_CHECKPOINT := Vector3(-272.04, 0.08, -217.07)


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("MISSION_CHECKPOINT_AUTOSAVE_FAIL: %s" % message)
    _cleanup()
    quit(1)


func _run() -> void:
    _cleanup()
    var first_scene := _instantiate_scene(AUTOSAVE_PATH)
    if first_scene == null:
        return
    await process_frame
    await physics_frame

    var mission: Node = first_scene.get_node("MissionDriveToCenter")
    var autosave: Node = first_scene.get_node("MissionCheckpointAutosave")
    var quick_save: Node = first_scene.get_node("MissionQuickSave")
    var player: CharacterBody3D = first_scene.get_node("Player")
    var vehicle: CharacterBody3D = first_scene.get_node("PrototypeCar")
    var status_label: Label = first_scene.get_node("SaveStatusLabel")

    quick_save.call("_show_feedback", "RETOUR QUICKSAVE", false)
    autosave.call("_show_feedback", "RETOUR AUTOSAVE", false)
    quick_save.call("_process", 10.0)
    if not status_label.visible or status_label.text != "RETOUR AUTOSAVE":
        _fail("quicksave timer hid newer autosave feedback")
        return
    autosave.call("_process", 10.0)
    if status_label.visible:
        _fail("autosave feedback did not expire")
        return

    vehicle.call("enter_driver", player)
    await physics_frame
    if int(mission.call("get_stage")) != 1:
        _fail("mission did not start when the player entered the vehicle")
        return
    if FileAccess.file_exists(AUTOSAVE_PATH):
        _fail("autosave was written before a checkpoint")
        return

    vehicle.global_position = FIRST_CHECKPOINT
    vehicle.velocity = Vector3.ZERO
    vehicle.set("speed", 0.0)
    await physics_frame
    await process_frame
    if int(mission.call("get_stage")) != 2:
        _fail("first checkpoint was not completed")
        return
    if not FileAccess.file_exists(AUTOSAVE_PATH):
        _fail("checkpoint did not create the autosave")
        return
    if not status_label.visible or not status_label.text.contains("SAUVEGARDE AUTO · Place Anneessens"):
        _fail("checkpoint autosave feedback is missing")
        return

    var saved_vehicle_position := vehicle.global_position
    first_scene.queue_free()
    await process_frame
    await process_frame

    var resumed_scene := _instantiate_scene(AUTOSAVE_PATH)
    if resumed_scene == null:
        return
    await process_frame
    await process_frame
    await physics_frame

    mission = resumed_scene.get_node("MissionDriveToCenter")
    autosave = resumed_scene.get_node("MissionCheckpointAutosave")
    vehicle = resumed_scene.get_node("PrototypeCar")
    status_label = resumed_scene.get_node("SaveStatusLabel")
    if int(mission.call("get_stage")) != 2:
        _fail("cold resume did not restore the completed checkpoint")
        return
    if vehicle.global_position.distance_to(saved_vehicle_position) > 0.15:
        _fail("cold resume did not restore the checkpoint vehicle position")
        return
    if not bool(vehicle.call("has_driver")):
        _fail("cold resume did not restore the active driver")
        return
    if not status_label.visible or not status_label.text.contains("REPRISE AUTO · N nouvelle partie"):
        _fail("cold resume feedback is missing")
        return

    var wallet: Node = resumed_scene.get_node("Wallet")
    wallet.call("credit", 12500)
    var new_game_event := InputEventKey.new()
    new_game_event.keycode = KEY_N
    new_game_event.pressed = true
    autosave.call("_unhandled_input", new_game_event)
    if FileAccess.file_exists(AUTOSAVE_PATH):
        _fail("new game did not clear the autosave slot")
        return
    if int(mission.call("get_stage")) != 0 or bool(vehicle.call("has_driver")):
        _fail("new game did not reset the mission and driver")
        return
    if int(wallet.call("get_cash_cents")) != 0:
        _fail("new game did not reset the wallet")
        return
    if not status_label.text.contains("NOUVELLE PARTIE · Bruxelles-Midi"):
        _fail("new game feedback is missing")
        return

    resumed_scene.queue_free()
    await process_frame
    await process_frame

    var corrupt_file := FileAccess.open(CORRUPT_PATH, FileAccess.WRITE)
    if corrupt_file == null:
        _fail("corrupt autosave fixture could not be created")
        return
    corrupt_file.store_string(JSON.stringify({
        "schema_version": 1,
        "payload_json": "{}",
        "payload_sha256": "checksum-volontairement-invalide",
    }))
    corrupt_file.close()

    var corrupt_scene := _instantiate_scene(CORRUPT_PATH)
    if corrupt_scene == null:
        return
    await process_frame
    await process_frame
    mission = corrupt_scene.get_node("MissionDriveToCenter")
    status_label = corrupt_scene.get_node("SaveStatusLabel")
    if int(mission.call("get_stage")) != 0:
        _fail("corrupt autosave mutated the fresh mission")
        return
    if not status_label.visible or not status_label.text.contains("REPRISE AUTO IMPOSSIBLE"):
        _fail("corrupt autosave failure is not visible")
        return

    corrupt_scene.queue_free()
    await process_frame
    _cleanup()
    print("MISSION_CHECKPOINT_AUTOSAVE_OK")
    quit(0)


func _instantiate_scene(path: String) -> Node:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return null
    var scene := packed.instantiate()
    var autosave: Node = scene.get_node("MissionCheckpointAutosave")
    autosave.set("autosave_path", path)
    root.add_child(scene)
    autosave.call_deferred("resume_autosave")
    return scene


func _cleanup() -> void:
    for path: String in [AUTOSAVE_PATH, CORRUPT_PATH]:
        var absolute := ProjectSettings.globalize_path(path)
        for suffix: String in ["", ".tmp", ".bak"]:
            var candidate := absolute + suffix
            if FileAccess.file_exists(candidate):
                DirAccess.remove_absolute(candidate)
