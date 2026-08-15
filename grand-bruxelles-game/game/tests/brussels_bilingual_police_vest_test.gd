extends SceneTree

var _failed := false

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
    for _frame in range(6):
        await process_frame

    var runtime := root.get_node_or_null("VisibleCityRuntime")
    if runtime == null:
        _fail("VisibleCityRuntime autoload missing")
        return
    runtime.call("ensure_zone_for_test", "midi")
    for _frame in range(5):
        await process_frame

    var police_checked := 0
    for node: Node in get_nodes_in_group("police_officer"):
        if not node is NpcAgent:
            continue
        var officer := node as NpcAgent
        if not officer.active:
            continue
        var visual := officer.get_node_or_null("VisibleHumanoid")
        if visual == null:
            _fail("active production police officer missing VisibleHumanoid")
            return
        var front_panel := visual.get_node_or_null("PoliceFrontHiVis")
        var rear_panel := visual.get_node_or_null("PoliceRearHiVis")
        var front_label := visual.get_node_or_null("UniformPoliceFrontLabel") as Label3D
        var rear_label := visual.get_node_or_null("UniformPoliceRearLabel") as Label3D
        if front_panel == null or rear_panel == null:
            _fail("police bilingual vest must expose front and rear high-visibility surfaces")
            return
        if front_label == null or rear_label == null:
            _fail("police bilingual vest must expose front and rear labels")
            return
        if front_label.text != "POLICE · POLITIE" or rear_label.text != "POLICE · POLITIE":
            _fail("bilingual identity text drifted")
            return
        police_checked += 1

    if police_checked < 2:
        _fail("expected at least two naturally spawned Midi police officers")
        return

    for node: Node in get_nodes_in_group("behavioral_civilian"):
        if not node is NpcAgent:
            continue
        var visual := node.get_node_or_null("VisibleHumanoid")
        if visual != null and (visual.get_node_or_null("PoliceRearHiVis") != null or visual.get_node_or_null("UniformPoliceRearLabel") != null):
            _fail("civilian received police identity")
            return

    print("BRUSSELS_BILINGUAL_POLICE_VEST_OK: officers=%d visual_mount=VisibleHumanoid" % police_checked)
    quit(0)

func _fail(message: String) -> void:
    if _failed:
        return
    _failed = true
    push_error(message)
    print("BRUSSELS_BILINGUAL_POLICE_VEST_FAIL: %s" % message)
    quit(1)
