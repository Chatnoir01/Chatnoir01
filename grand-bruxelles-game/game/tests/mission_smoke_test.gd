extends SceneTree

const MissionSaveCoordinator = preload("res://game/scripts/mission_save_coordinator.gd")
const SAVE_PATH := "user://grand_bruxelles_timed_mission_smoke.json"


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("MISSION_SMOKE_FAIL: %s" % message)
    _cleanup_save()
    quit(1)


func _run() -> void:
    _cleanup_save()
    var packed: PackedScene = load("res://game/main.tscn")
    if packed == null:
        _fail("main scene did not load")
        return

    var scene: Node = packed.instantiate()
    root.add_child(scene)
    await process_frame
    await physics_frame

    var player: CharacterBody3D = scene.get_node_or_null("Player") as CharacterBody3D
    var car: CharacterBody3D = scene.get_node_or_null("PrototypeCar") as CharacterBody3D
    var mission: Node = scene.get_node_or_null("MissionDriveToCenter")
    var label: Label = scene.get_node_or_null("MissionLabel") as Label

    if player == null or car == null or mission == null or label == null:
        _fail("mission dependencies missing")
        return
    if int(mission.call("get_stage")) != 0:
        _fail("mission should start at stage 0")
        return

    var initial_state: Dictionary = mission.call("export_state")
    if str(initial_state.get("mission_id", "")) != "midi_to_centre_01":
        _fail("mission state must expose a stable mission id")
        return
    if int(initial_state.get("schema_version", -1)) != 1:
        _fail("mission state schema version missing")
        return
    if int(initial_state.get("stage", -1)) != 0:
        _fail("initial exported stage should be 0")
        return
    if absf(float(initial_state.get("time_remaining", -1.0)) - 240.0) > 0.001:
        _fail("mission should expose its complete initial time budget")
        return
    if bool(initial_state.get("failed", true)):
        _fail("mission should not start failed")
        return

    var initial_player_position: Vector3 = player.global_position
    var initial_car_position: Vector3 = car.global_position

    car.call("enter_driver", player)
    await physics_frame
    if int(mission.call("get_stage")) != 1:
        _fail("entering the car should start route stage 1")
        return

    var stage_one_state: Dictionary = mission.call("export_state")
    if int(stage_one_state.get("stage", -1)) != 1:
        _fail("exported mission state did not capture stage 1")
        return
    if not label.text.contains("04:00"):
        _fail("active mission HUD should expose the countdown")
        return
    var saved_time_remaining: float = float(stage_one_state["time_remaining"])
    var save_result: Dictionary = MissionSaveCoordinator.save_mission(SAVE_PATH, mission)
    if not bool(save_result.get("ok", false)):
        _fail("active timed mission could not be saved")
        return

    var checkpoints: Array[Vector3] = [
        Vector3(-272.04, 0.58, -217.07),
        Vector3(81.54, 0.58, -664.58),
        Vector3(319.01, 0.58, -535.20),
    ]

    for index: int in range(checkpoints.size()):
        car.global_position = checkpoints[index]
        car.velocity = Vector3.ZERO
        await physics_frame
        await physics_frame
        var expected_stage: int = index + 2
        if int(mission.call("get_stage")) != expected_stage:
            _fail("checkpoint %d did not advance to stage %d" % [index, expected_stage])
            return

    if int(mission.call("get_stage")) != int(mission.call("get_stage_count")):
        _fail("mission did not reach completed stage")
        return
    if not label.text.contains("MISSION TERMINÉE"):
        _fail("mission completion HUD text missing")
        return
    if not label.text.contains("Temps restant"):
        _fail("mission completion should preserve the measured time result")
        return

    if not bool(mission.call("restore_state", stage_one_state)):
        _fail("valid stage-one mission snapshot was rejected")
        return
    if int(mission.call("get_stage")) != 1:
        _fail("mission did not restore stage 1")
        return
    if not label.text.contains("Place Anneessens"):
        _fail("restored mission stage did not refresh the HUD")
        return

    var legacy_state: Dictionary = stage_one_state.duplicate(true)
    legacy_state.erase("time_remaining")
    legacy_state.erase("failed")
    if not bool(mission.call("restore_state", legacy_state)):
        _fail("legacy mission snapshot without timer fields was rejected")
        return
    if bool(mission.call("is_failed")) or absf(float(mission.call("get_time_remaining")) - 240.0) > 0.001:
        _fail("legacy mission snapshot did not receive safe timer defaults")
        return

    var expired_state: Dictionary = stage_one_state.duplicate(true)
    expired_state["time_remaining"] = 0.0
    if not bool(mission.call("restore_state", expired_state)):
        _fail("valid expired active snapshot was rejected")
        return
    await physics_frame
    if not bool(mission.call("is_failed")):
        _fail("mission should fail once its countdown reaches zero")
        return
    if not label.text.contains("TEMPS ÉCOULÉ"):
        _fail("failed mission HUD should explain the time failure")
        return

    car.set("speed", 12.0)
    mission.call("restart_mission")
    await physics_frame
    if int(mission.call("get_stage")) != 0 or bool(mission.call("is_failed")):
        _fail("mission restart should restore the initial playable state")
        return
    if bool(car.call("has_driver")):
        _fail("mission restart should return the player to on-foot mode")
        return
    var player_horizontal_error := Vector2(
        player.global_position.x - initial_player_position.x,
        player.global_position.z - initial_player_position.z
    ).length()
    if player_horizontal_error > 0.01 or absf(player.global_position.y - initial_player_position.y) > 0.25:
        _fail("mission restart did not restore the player spawn")
        return
    var car_horizontal_error := Vector2(
        car.global_position.x - initial_car_position.x,
        car.global_position.z - initial_car_position.z
    ).length()
    if car_horizontal_error > 0.01 or absf(car.global_position.y - initial_car_position.y) > 0.25:
        _fail("mission restart did not restore the vehicle spawn")
        return
    var car_horizontal_velocity := Vector2(car.velocity.x, car.velocity.z).length()
    if absf(float(car.get("speed"))) > 0.001 or car_horizontal_velocity > 0.01:
        _fail("mission restart did not reset vehicle motion")
        return

    var load_result: Dictionary = MissionSaveCoordinator.load_mission(SAVE_PATH, mission)
    if not bool(load_result.get("ok", false)):
        _fail("saved active timed mission could not be reloaded")
        return
    if int(mission.call("get_stage")) != 1:
        _fail("mission reload did not restore the active route stage")
        return
    if absf(float(mission.call("get_time_remaining")) - saved_time_remaining) > 0.1:
        _fail("mission reload did not restore its countdown")
        return

    var completed_state: Dictionary = mission.call("export_state")
    completed_state["stage"] = int(mission.call("get_stage_count"))
    if not bool(mission.call("restore_state", completed_state)):
        _fail("valid completed mission snapshot was rejected")
        return
    if not label.text.contains("MISSION TERMINÉE"):
        _fail("restored completed mission did not refresh completion HUD")
        return

    var wrong_mission: Dictionary = completed_state.duplicate(true)
    wrong_mission["mission_id"] = "other_mission"
    if bool(mission.call("restore_state", wrong_mission)):
        _fail("snapshot for another mission id must be rejected")
        return

    var future_schema: Dictionary = completed_state.duplicate(true)
    future_schema["schema_version"] = 999
    if bool(mission.call("restore_state", future_schema)):
        _fail("unknown mission state schema must be rejected")
        return

    var invalid_stage: Dictionary = completed_state.duplicate(true)
    invalid_stage["stage"] = int(mission.call("get_stage_count")) + 1
    if bool(mission.call("restore_state", invalid_stage)):
        _fail("out-of-range mission stage must be rejected")
        return

    var invalid_time: Dictionary = stage_one_state.duplicate(true)
    invalid_time["time_remaining"] = "soon"
    if bool(mission.call("restore_state", invalid_time)):
        _fail("non-numeric mission countdown must be rejected")
        return

    var impossible_failure: Dictionary = initial_state.duplicate(true)
    impossible_failure["failed"] = true
    impossible_failure["time_remaining"] = 0.0
    if bool(mission.call("restore_state", impossible_failure)):
        _fail("failed state before mission start must be rejected")
        return

    print("MISSION_SMOKE_OK: timed route progression + fail/restart + state snapshot/restore passed")
    _cleanup_save()
    scene.queue_free()
    await process_frame
    quit(0)


func _cleanup_save() -> void:
    var absolute := ProjectSettings.globalize_path(SAVE_PATH)
    for suffix: String in ["", ".tmp", ".bak"]:
        var candidate := absolute + suffix
        if FileAccess.file_exists(candidate):
            DirAccess.remove_absolute(candidate)
