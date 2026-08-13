extends SceneTree

const TEST_SAVE_PATH := "user://grand_bruxelles_quicksave_test.json"


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("MISSION_QUICK_SAVE_FAIL: %s" % message)
    _cleanup()
    quit(1)


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
    var status_label: Label = scene.get_node_or_null("SaveStatusLabel")
    var car: CharacterBody3D = scene.get_node_or_null("PrototypeCar")
    var player: CharacterBody3D = scene.get_node_or_null("Player")
    if mission == null or quick_save == null or status_label == null or car == null or player == null:
        _fail("quicksave runtime nodes missing")
        return

    quick_save.set("save_path", TEST_SAVE_PATH)
    if status_label.visible:
        _fail("quicksave feedback must not alter the initial HUD")
        return

    car.call("enter_driver", player)
    await physics_frame
    if int(mission.call("get_stage")) != 1:
        _fail("mission did not reach active stage")
        return

    var saved_time: float = float(mission.call("get_time_remaining"))
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

    quick_save.set("save_path", "user://missing_grand_bruxelles_quicksave_test.json")
    _remove_path(ProjectSettings.globalize_path(str(quick_save.get("save_path"))))
    if bool(quick_save.call("quick_load")):
        _fail("missing quicksave should not load")
        return
    if not status_label.text.contains("AUCUNE SAUVEGARDE"):
        _fail("missing-save feedback is not actionable")
        return

    _cleanup()
    scene.queue_free()
    await process_frame
    print("MISSION_QUICK_SAVE_OK")
    quit(0)


func _cleanup() -> void:
    _remove_path(ProjectSettings.globalize_path(TEST_SAVE_PATH))
    _remove_path(ProjectSettings.globalize_path("user://missing_grand_bruxelles_quicksave_test.json"))


func _remove_path(absolute: String) -> void:
    for suffix: String in ["", ".tmp", ".bak"]:
        var candidate := absolute + suffix
        if FileAccess.file_exists(candidate):
            DirAccess.remove_absolute(candidate)
