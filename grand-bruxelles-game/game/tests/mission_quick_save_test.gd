extends SceneTree

const MissionSaveCoordinator = preload("res://game/scripts/mission_save_coordinator.gd")
const TEST_SAVE_PATH := "user://grand_bruxelles_quicksave_test.json"
const LEGACY_SAVE_PATH := "user://grand_bruxelles_legacy_quicksave_test.json"


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("MISSION_QUICK_SAVE_FAIL: %s" % message)
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
        rigid.sleeping = false
    elif vehicle is CharacterBody3D:
        var character := vehicle as CharacterBody3D
        character.velocity = linear
        character.set("speed", scalar_speed)


func _run() -> void:
    _cleanup()
    var packed: PackedScene = load("res://game/main.tscn")
    if packed == null:
        _fail("main scene did not load")
        return

    var scene: Node = packed.instantiate()
    root.add_child(scene)
    await process_frame
    await physics_frame

    var mission: Node = scene.get_node_or_null("MissionDriveToCenter")
    var quick_save: Node = scene.get_node_or_null("MissionQuickSave")
    var gameplay_state: Node = scene.get_node_or_null("RuntimeGameplayState")
    var status_label: Label = scene.get_node_or_null("SaveStatusLabel") as Label
    var player: CharacterBody3D = scene.get_node_or_null("Player") as CharacterBody3D
    var car: Node3D = _primary_vehicle(scene, mission) if mission != null else null
    if mission == null or quick_save == null or gameplay_state == null or status_label == null or car == null or player == null:
        _fail("quicksave runtime nodes missing")
        return

    quick_save.set("save_path", TEST_SAVE_PATH)
    if status_label.visible:
        _fail("quicksave feedback must not alter the initial HUD")
        return

    car.call("enter_driver", player)
    await physics_frame
    if int(mission.call("get_stage")) != 1:
        _fail("mission did not reach active stage in declared primary vehicle")
        return

    var saved_time: float = float(mission.call("get_time_remaining"))
    var saved_player_position: Vector3 = player.global_position
    var saved_car_position: Vector3 = car.global_position
    var saved_car_rotation: Vector3 = car.rotation
    var live_runtime_state: Dictionary = gameplay_state.call("export_state")
    var live_vehicle_state: Dictionary = live_runtime_state.get("vehicle", {})
    if not bool(live_vehicle_state.get("driver_active", false)):
        _fail("runtime save domain does not follow the active primary vehicle")
        return
    var runtime_vehicle_position := Vector3(
        float(live_vehicle_state["position"][0]),
        float(live_vehicle_state["position"][1]),
        float(live_vehicle_state["position"][2])
    )
    if runtime_vehicle_position.distance_to(saved_car_position) > 0.01:
        _fail("runtime save domain captured a different vehicle")
        return

    var save_event := InputEventKey.new()
    save_event.keycode = KEY_F5
    save_event.pressed = true
    quick_save.call("_unhandled_input", save_event)
    if not FileAccess.file_exists(TEST_SAVE_PATH):
        _fail("F5 did not create the quicksave")
        return
    if not status_label.text.contains("SAUVEGARDÉE"):
        _fail("successful save feedback missing")
        return
    if not status_label.visible:
        _fail("successful save feedback is not visible")
        return

    car.call("exit_driver")
    player.global_position = Vector3(120.0, 4.0, -80.0)
    player.velocity = Vector3(5.0, 1.0, -3.0)
    car.global_position = Vector3(-90.0, 2.0, 140.0)
    car.rotation = Vector3(0.0, 1.4, 0.0)
    _set_vehicle_motion(car, Vector3(12.0, 0.0, -4.0), Vector3(0.0, 1.4, 0.0), 11.0)
    var changed_state: Dictionary = mission.call("export_state")
    changed_state["stage"] = 2
    changed_state["time_remaining"] = 17.0
    if not bool(mission.call("restore_state", changed_state)):
        _fail("test could not mutate live mission state")
        return

    var load_event := InputEventKey.new()
    load_event.keycode = KEY_F9
    load_event.pressed = true
    quick_save.call("_unhandled_input", load_event)
    if int(mission.call("get_stage")) != 1:
        _fail("quickload did not restore mission stage")
        return
    if absf(float(mission.call("get_time_remaining")) - saved_time) > 0.1:
        _fail("quickload did not restore mission countdown")
        return
    if not status_label.text.contains("CHARGÉE"):
        _fail("successful load feedback missing")
        return
    if not status_label.visible:
        _fail("successful load feedback is not visible")
        return
    if not bool(car.call("has_driver")):
        _fail("quickload did not restore the player in the primary vehicle")
        return
    if player.global_position.distance_to(saved_player_position) > 0.01:
        _fail("quickload did not restore player position")
        return
    if car.global_position.distance_to(saved_car_position) > 0.01:
        _fail("quickload did not restore vehicle position")
        return
    if car.rotation.distance_to(saved_car_rotation) > 0.01:
        _fail("quickload did not restore vehicle rotation")
        return

    var invalid_runtime_state: Dictionary = gameplay_state.call("export_state")
    invalid_runtime_state["vehicle"]["position"] = [INF, 0.0, 0.0]
    if bool(gameplay_state.call("can_restore_state", invalid_runtime_state)):
        _fail("non-finite runtime position passed precheck")
        return
    if bool(gameplay_state.call("restore_state", invalid_runtime_state)):
        _fail("invalid runtime state was restored")
        return
    if car.global_position.distance_to(saved_car_position) > 0.01:
        _fail("rejected runtime state mutated the vehicle")
        return

    var legacy_result: Dictionary = MissionSaveCoordinator.save_mission(LEGACY_SAVE_PATH, mission)
    if not bool(legacy_result.get("ok", false)):
        _fail("legacy fixture could not be written")
        return
    changed_state = mission.call("export_state")
    changed_state["stage"] = 2
    changed_state["time_remaining"] = 9.0
    mission.call("restore_state", changed_state)
    quick_save.set("save_path", LEGACY_SAVE_PATH)
    if not bool(quick_save.call("quick_load")):
        _fail("legacy mission-only quicksave did not load")
        return
    if int(mission.call("get_stage")) != 1 or not status_label.text.contains("ANCIENNE MISSION CHARGÉE"):
        _fail("legacy quicksave fallback is not explicit")
        return

    quick_save.set("save_path", "user://missing_grand_bruxelles_quicksave_test.json")
    _remove_path(ProjectSettings.globalize_path(str(quick_save.get("save_path"))))
    if bool(quick_save.call("quick_load")):
        _fail("missing quicksave should not load")
        return
    if not status_label.text.contains("AUCUNE SAUVEGARDE"):
        _fail("missing-save feedback is not actionable")
        return

    quick_save.set("save_path", "user://../outside_quicksave.json")
    if bool(quick_save.call("quick_save")):
        _fail("unsafe quicksave path was accepted")
        return
    if not status_label.text.contains("SAUVEGARDE IMPOSSIBLE"):
        _fail("unsafe-path feedback is not actionable")
        return

    _cleanup()
    scene.queue_free()
    await process_frame
    print("MISSION_QUICK_SAVE_OK: runtime domain follows mission primary vehicle")
    quit(0)


func _cleanup() -> void:
    _remove_path(ProjectSettings.globalize_path(TEST_SAVE_PATH))
    _remove_path(ProjectSettings.globalize_path(LEGACY_SAVE_PATH))
    _remove_path(ProjectSettings.globalize_path("user://missing_grand_bruxelles_quicksave_test.json"))


func _remove_path(absolute: String) -> void:
    for suffix: String in ["", ".tmp", ".bak"]:
        var candidate := absolute + suffix
        if FileAccess.file_exists(candidate):
            DirAccess.remove_absolute(candidate)
