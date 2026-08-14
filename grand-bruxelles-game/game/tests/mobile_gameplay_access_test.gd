extends SceneTree

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene missing")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    current_scene = scene
    for _frame in range(5):
        await process_frame

    var controls := scene.get_node_or_null("MobileControls")
    if controls == null:
        _fail("MobileControls missing")
        return
    if not controls.has_method("ensure_gameplay_controls_for_test"):
        _fail("gameplay panel test hook missing")
        return
    controls.call("ensure_gameplay_controls_for_test")
    controls.call("open_gameplay_panel_for_test")
    await process_frame

    var state: Dictionary = controls.call("gameplay_panel_state_for_test")
    if not bool(state.get("built", false)):
        _fail("gameplay panel was not built")
        return
    if not bool(state.get("visible", false)):
        _fail("gameplay panel is not visible")
        return
    var status := str(state.get("status", ""))
    if not status.contains("MISSION") or not status.contains("SOLDE"):
        _fail("gameplay panel does not expose mission and wallet")
        return

    var panel := controls.get_node_or_null("GameplayPanel")
    if panel == null:
        _fail("GameplayPanel node missing")
        return
    var labels: Array[String] = []
    _collect_button_labels(panel, labels)
    for required: String in ["SAUVEGARDER", "CHARGER", "NOUVELLE PARTIE", "FERMER"]:
        if not labels.has(required):
            _fail("missing gameplay action button: %s" % required)
            return

    if not controls.has_method("quick_save_from_ui") or not bool(controls.call("quick_save_from_ui")):
        _fail("mobile save action did not reach existing quick-save system")
        return
    if not controls.has_method("quick_load_from_ui") or not bool(controls.call("quick_load_from_ui")):
        _fail("mobile load action did not reach existing quick-load system")
        return

    var save_status := scene.get_node_or_null("SaveStatusLabel") as Label
    if save_status == null or not save_status.visible:
        _fail("save/load feedback is not visible to mobile player")
        return

    print("MOBILE_GAMEPLAY_ACCESS_OK: buttons=%s" % [labels])
    quit(0)

func _collect_button_labels(node: Node, labels: Array[String]) -> void:
    if node is Button:
        labels.append((node as Button).text)
    for child: Node in node.get_children():
        _collect_button_labels(child, labels)

func _fail(message: String) -> void:
    push_error(message)
    print("MOBILE_GAMEPLAY_ACCESS_FAIL: %s" % message)
    quit(1)
