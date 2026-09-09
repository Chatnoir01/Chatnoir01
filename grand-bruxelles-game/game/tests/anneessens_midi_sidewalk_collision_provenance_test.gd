extends SceneTree

const RUNTIME := preload("res://game/scripts/anneessens_midi_sidewalk_runtime.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ANNEESSENS_SIDEWALK_COLLISION_PROVENANCE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var scene := Node3D.new()
    scene.name = "Main"
    root.add_child(scene)

    var osm := Node3D.new()
    osm.name = "BrusselsOSM"
    scene.add_child(osm)
    var roads := Node3D.new()
    roads.name = "GeneratedRoads"
    osm.add_child(roads)

    var road := CSGBox3D.new()
    road.name = "Road_Regression"
    road.size = Vector3(9.0, 0.12, 40.0)
    road.position = Vector3(-272.04, 0.0, -217.07)
    road.use_collision = true
    roads.add_child(road)

    var urbis := Node3D.new()
    urbis.name = "UrbISMidiExact"
    scene.add_child(urbis)
    var player := Node3D.new()
    player.name = "Player"
    scene.add_child(player)

    var runtime := RUNTIME.new()
    root.add_child(runtime)
    runtime.call("bind_scene", scene)
    await process_frame

    var kit := scene.get_node_or_null("AnneessensMidiSidewalkKit")
    if kit == null:
        _fail("sidewalk kit was not built")
        return
    if kit.get_meta("vertical_profile_source_backed", true) != false:
        _fail("root must remain explicit that vertical profile is not source-backed")
        return
    if kit.get_meta("sidewalk_presence_source_backed", true) != false:
        _fail("root must remain explicit that sidewalk presence is not source-backed")
        return

    var sidewalks := 0
    for child: Node in kit.get_children():
        if child is CSGBox3D:
            sidewalks += 1
            var pavement := child as CSGBox3D
            if pavement.get_meta("vertical_profile_source_backed", true) != false:
                _fail("proxy sidewalk unexpectedly claims source-backed vertical profile")
                return
            if pavement.use_collision:
                _fail("authored proxy with unverified vertical profile must not own player collision: %s" % pavement.name)
                return

    if sidewalks != 2:
        _fail("expected exactly two regression sidewalks, got %d" % sidewalks)
        return
    if int(runtime.call("diagnostic_sidewalk_count")) != sidewalks:
        _fail("visual sidewalk diagnostic count drifted")
        return
    if int(runtime.call("diagnostic_collision_count")) != 0:
        _fail("unverified authored proxy reports collision ownership")
        return

    print("ANNEESSENS_SIDEWALK_COLLISION_PROVENANCE_OK: sidewalks=%d collisions=0 visual_proxy_retained=true" % sidewalks)
    quit(0)
