extends SceneTree

const ANNEESSENS := Vector2(-272.04, -217.07)
const DETAIL_RADIUS_M := 150.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ANNEESSENS_MIDI_SIDEWALK_ROOT_BIND_FAIL: %s" % message)
    quit(1)

func _expected_sidewalk_count(scene: Node3D) -> int:
    var roads := scene.get_node_or_null("BrusselsOSM/GeneratedRoads")
    if roads == null:
        return -1
    var eligible := 0
    for child: Node in roads.get_children():
        if not child is CSGBox3D or not child.name.begins_with("Road_"):
            continue
        var road := child as CSGBox3D
        var center_2d := Vector2(road.global_position.x, road.global_position.z)
        if center_2d.distance_to(ANNEESSENS) > DETAIL_RADIUS_M:
            continue
        if road.size.z < 1.0 or road.size.x < 2.0:
            continue
        eligible += 1
    return eligible * 2

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("production main scene missing")
        return

    var scene := packed.instantiate() as Node3D
    if scene == null:
        _fail("production main scene did not instantiate as Node3D")
        return
    root.add_child(scene)

    if current_scene != null:
        _fail("harness unexpectedly assigned SceneTree.current_scene")
        return
    if scene.get_node_or_null("BrusselsOSM") == null or scene.get_node_or_null("UrbISMidiExact") == null or scene.get_node_or_null("Player") == null:
        _fail("production scene anchors missing")
        return

    var expected := _expected_sidewalk_count(scene)
    if expected <= 0:
        _fail("production Anneessens road selection unexpectedly empty")
        return

    var runtime := root.get_node_or_null("AnneessensMidiSidewalkRuntime")
    if runtime == null:
        _fail("AnneessensMidiSidewalkRuntime autoload missing")
        return

    for _frame: int in range(24):
        await process_frame

    var sidewalk_count := int(runtime.call("diagnostic_sidewalk_count"))
    var collision_count := int(runtime.call("diagnostic_collision_count"))
    if sidewalk_count != expected:
        _fail("runtime did not auto-discover root-instantiated production scene: sidewalks=%d expected=%d" % [sidewalk_count, expected])
        return
    if collision_count != expected:
        _fail("collision count mismatch: collisions=%d expected=%d" % [collision_count, expected])
        return

    var kit := scene.get_node_or_null("AnneessensMidiSidewalkKit")
    if kit == null:
        _fail("AnneessensMidiSidewalkKit not mounted under production scene")
        return
    if kit.get_child_count() != expected:
        _fail("mounted sidewalk child count mismatch")
        return

    print("ANNEESSENS_MIDI_SIDEWALK_ROOT_BIND_OK: sidewalks=%d collisions=%d current_scene=null" % [sidewalk_count, collision_count])
    quit(0)
