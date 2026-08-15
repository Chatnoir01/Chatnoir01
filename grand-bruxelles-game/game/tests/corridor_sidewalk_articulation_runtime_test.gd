extends SceneTree

const MIDI_ANCHOR := Vector2(-668.5, 627.84)
const BOURSE_ANCHOR := Vector2(81.54, -664.58)

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("CORRIDOR_SIDEWALK_ARTICULATION_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    for _frame: int in range(4):
        await process_frame

    var roads := scene.get_node_or_null("BrusselsOSM/GeneratedRoads")
    if roads == null:
        _fail("production GeneratedRoads root missing")
        return
    var articulation := scene.get_node_or_null("BrusselsOSM/CorridorSidewalkArticulation")
    if articulation == null:
        _fail("production sidewalk articulation layer missing")
        return
    if not articulation.has_method("articulation_counts_near"):
        _fail("production sidewalk articulation exposes no diagnostics")
        return

    var midi: Dictionary = articulation.call("articulation_counts_near", MIDI_ANCHOR, 300.0)
    var bourse: Dictionary = articulation.call("articulation_counts_near", BOURSE_ANCHOR, 180.0)
    var midi_curbs := int(midi.get("curbs", 0))
    var midi_joints := int(midi.get("joints", 0))
    var bourse_curbs := int(bourse.get("curbs", 0))
    var bourse_joints := int(bourse.get("joints", 0))

    if midi_curbs < 40 or midi_joints < 80:
        _fail("Midi sidewalks remain slab-like: curbs=%d joints=%d" % [midi_curbs, midi_joints])
        return
    if bourse_curbs < 20 or bourse_joints < 40:
        _fail("Bourse sidewalks remain slab-like: curbs=%d joints=%d" % [bourse_curbs, bourse_joints])
        return
    for required_name: String in ["CurbLips", "PavementJoints"]:
        if articulation.get_node_or_null(required_name) == null:
            _fail("missing visible MultiMesh layer %s" % required_name)
            return

    print("CORRIDOR_SIDEWALK_ARTICULATION_OK: midi_curbs=%d midi_joints=%d bourse_curbs=%d bourse_joints=%d" % [midi_curbs, midi_joints, bourse_curbs, bourse_joints])
    scene.queue_free()
    quit(0)
