extends SceneTree

const AUTOSAVE_PATH := "user://grand_bruxelles_checkpoint_autosave_test.json"
const CORRUPT_PATH := "user://grand_bruxelles_checkpoint_autosave_corrupt_test.json"
const FIRST_CHECKPOINT := Vector3(-272.04, 0.0, -217.07)


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("MISSION_CHECKPOINT_AUTOSAVE_FAIL: %s" % message)
    _cleanup()
    quit(1)


func _primary_vehicle(scene: Node, mission: Node) -> Node3D:
    var vehicle_name := "PrototypeCar"
    if mission.has_method("primary_vehicle_node_name"):
        vehicle_name = str(mission.call("primary_vehicle_node_name"))
    return scene.get_node_or_null(vehicle_name) as Node3D


func _set_vehicle_motion(vehicle: Node3D, linear: Vector3, angular: Vector3 = Vector3.ZERO, scalar_speed: float = 0.0) -> void:
    if vehicle is RigidBody3D:
        var rigid := vehicle as RigidBody3D
        rigid.linear_velocity = linear
        rigid.angular_velocity = angular
    elif vehicle is CharacterBody3D:
        var character := vehicle as CharacterBody3D
        character.velocity = linear
        character.set("speed", scalar_speed)


func _move_vehicle_xz(vehicle: Node3D, target: Vector3) -> void:
    vehicle.global_position = Vector3(target.x, vehicle.global_position.y, target.z)
    _set_vehicle_motion(vehicle, Vector3.ZERO)


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
    var vehicle: Node3D = _primary_vehicle(first_scene, mission)
    var status_label: Label = first_scene.get_node("SaveStatusLabel")

    if vehicle == null:
        _fail("mission primary vehicle missing")
        return

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
        _fail("mission did not start when the player entered the declared primary vehicle")
        return
    if FileAccess.file_exists(AUTOSAVE_PATH):
        _fail("autosave was written before a checkpoint")
        return

    _move_vehicle_xz(vehicle, FIRST_CHECKPOINT)
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
    var return_mission: Node = resumed_scene.get_node("MissionReturnToBourse")
    autosave = resumed_scene.get_node("MissionCheckpointAutosave")
    vehicle = _primary_vehicle(resumed_scene, mission)
    status_label = resumed_scene.get_node("SaveStatusLabel")
    if vehicle == null:
        _fail("cold resume mission primary vehicle missing")
        return
    if int(mission.call("get_stage")) != 2:
        _fail("cold resume did not restore the completed checkpoint")
        return
    var horizontal_resume_error := Vector2(
        vehicle.global_position.x - saved_vehicle_position.x,
        vehicle.global_position.z - saved_vehicle_position.z
    ).length()
    var vertical_resume_error := absf(vehicle.global_position.y - saved_vehicle_position.y)
    if horizontal_resume_error > 0.15 or vertical_resume_error > 0.35:
        _fail("cold resume drifted from checkpoint: horizontal=%.3fm vertical=%.3fm" % [horizontal_resume_error, vertical_resume_error])
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
    if int(return_mission.call("get_state")) != 0:
        _fail("new game did not reset the return mission")
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
    print("MISSION_CHECKPOINT_AUTOSAVE_OK: cold resume follows mission primary vehicle at physical ride height")
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
