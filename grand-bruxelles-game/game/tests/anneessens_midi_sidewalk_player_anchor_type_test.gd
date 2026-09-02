extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ANNEESSENS_MIDI_SIDEWALK_PLAYER_ANCHOR_TYPE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var malformed := Node3D.new()
    malformed.name = "Main"
    var osm := Node3D.new()
    osm.name = "BrusselsOSM"
    malformed.add_child(osm)
    var roads := Node3D.new()
    roads.name = "GeneratedRoads"
    osm.add_child(roads)
    var road := CSGBox3D.new()
    road.name = "Road_test"
    road.size = Vector3(8.0, 0.2, 20.0)
    road.position = Vector3(-272.04, 0.0, -217.07)
    roads.add_child(road)
    var urbis := Node3D.new()
    urbis.name = "UrbISMidiExact"
    malformed.add_child(urbis)
    var fake_player := Node.new()
    fake_player.name = "Player"
    malformed.add_child(fake_player)
    root.add_child(malformed)

    var runtime := root.get_node_or_null("AnneessensMidiSidewalkRuntime")
    if runtime == null:
        _fail("AnneessensMidiSidewalkRuntime autoload missing")
        return

    for _frame: int in range(24):
        await process_frame

    if malformed.get_node_or_null("AnneessensMidiSidewalkKit") != null:
        _fail("runtime captured a malformed production scene whose Player anchor is not Node3D")
        return
    if int(runtime.call("diagnostic_sidewalk_count")) != 0 or int(runtime.call("diagnostic_collision_count")) != 0:
        _fail("runtime created sidewalk/collision state for malformed Player anchor")
        return

    print("ANNEESSENS_MIDI_SIDEWALK_PLAYER_ANCHOR_TYPE_OK: malformed_player_rejected=true")
    quit(0)
