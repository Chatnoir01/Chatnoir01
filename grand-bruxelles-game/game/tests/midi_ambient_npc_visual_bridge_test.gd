extends SceneTree

const EXPECTED_AMBIENT := 20

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_AMBIENT_NPC_VISUAL_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    for _frame: int in range(6):
        await process_frame

    var urban_life := scene.get_node_or_null("MidiUrbanLife")
    if urban_life == null:
        _fail("production MidiUrbanLife missing")
        return

    var ambient := get_nodes_in_group("ambient_pedestrian")
    if ambient.size() != EXPECTED_AMBIENT:
        _fail("expected %d ambient pedestrians, got %d" % [EXPECTED_AMBIENT, ambient.size()])
        return

    var signatures := {}
    for raw: Node in ambient:
        var person := raw as Node3D
        if person == null:
            _fail("ambient pedestrian is not Node3D")
            return
        var proxy := person.get_node_or_null("ProfiledNpcProxy") as NpcAgent
        if proxy == null:
            _fail("%s has no production NpcAgent visual proxy" % person.name)
            return
        if proxy.process_mode != Node.PROCESS_MODE_DISABLED:
            _fail("%s proxy may compete with legacy ambient movement" % person.name)
            return
        var visual := proxy.get_node_or_null("VisualUpgrade") as Node3D
        if visual == null or not visual.has_method("visual_signature"):
            _fail("%s has no production humanoid visual" % person.name)
            return
        var signature := str(visual.call("visual_signature"))
        if signature.is_empty():
            _fail("%s production appearance signature is empty" % person.name)
            return
        signatures[signature] = true
        for legacy_name: String in ["Torso", "LeftLeg", "RightLeg", "LeftArm", "RightArm", "Head", "Bag"]:
            var legacy := person.get_node_or_null(legacy_name)
            if legacy is VisualInstance3D and (legacy as VisualInstance3D).visible:
                _fail("%s still exposes legacy primitive %s" % [person.name, legacy_name])
                return

    if signatures.size() < 8:
        _fail("ambient crowd variation is too repetitive: %d unique signatures" % signatures.size())
        return

    print("MIDI_AMBIENT_NPC_VISUAL_OK: pedestrians=%d unique_signatures=%d" % [ambient.size(), signatures.size()])
    scene.queue_free()
    quit(0)
