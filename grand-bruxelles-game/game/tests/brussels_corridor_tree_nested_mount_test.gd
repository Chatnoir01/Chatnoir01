extends SceneTree

const RUNTIME_PATH := "res://game/scripts/brussels_corridor_tree_runtime.gd"
const EXPECTED_TREES := 266

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_CORRIDOR_TREE_NESTED_MOUNT_FAIL: %s" % message)
    quit(1)

func _add_anchors(main: Node3D) -> void:
    var brussels_osm := Node3D.new()
    brussels_osm.name = "BrusselsOSM"
    main.add_child(brussels_osm)
    var roads := Node3D.new()
    roads.name = "GeneratedRoads"
    brussels_osm.add_child(roads)
    var urbis := Node3D.new()
    urbis.name = "UrbISMidiExact"
    main.add_child(urbis)
    var player := Node3D.new()
    player.name = "Player"
    main.add_child(player)

func _foreign_decoy() -> Node3D:
    var wrapper := Node3D.new()
    wrapper.name = "ForeignEnvironmentOwner"
    var main := Node3D.new()
    main.name = "ForeignNestedMain"
    wrapper.add_child(main)
    _add_anchors(main)
    return wrapper

func _run() -> void:
    if current_scene != null:
        _fail("witness requires current_scene == null")
        return
    var runtime_script := load(RUNTIME_PATH) as Script
    if runtime_script == null:
        _fail("runtime script missing")
        return
    var runtime := runtime_script.new() as Node
    runtime.name = "CorridorTreeNestedMountWitness"
    root.add_child(runtime)
    for _frame: int in range(8):
        await process_frame
    if int(runtime.call("tree_count")) != 0:
        _fail("runtime built before a valid production mount existed")
        return

    var foreign_wrapper := _foreign_decoy()
    root.add_child(foreign_wrapper)
    for _frame: int in range(12):
        await process_frame
    if int(runtime.call("tree_count")) != 0:
        _fail("foreign nested anchors captured corridor tree authority")
        return
    var foreign_main := foreign_wrapper.get_node_or_null("ForeignNestedMain")
    if foreign_main != null and foreign_main.get_node_or_null("BrusselsCorridorTrees") != null:
        _fail("foreign nested owner received corridor tree root")
        return

    var viewport := SubViewport.new()
    viewport.name = "EnvironmentViewport"
    root.add_child(viewport)
    var main := Node3D.new()
    main.name = "Main"
    viewport.add_child(main)
    _add_anchors(main)
    for _frame: int in range(30):
        await process_frame

    var tree_count := int(runtime.call("tree_count"))
    if tree_count != EXPECTED_TREES:
        _fail("root-level viewport Main did not bind corridor trees: trees=%d expected=%d" % [tree_count, EXPECTED_TREES])
        return
    var tree_root := main.get_node_or_null("BrusselsCorridorTrees")
    if tree_root == null:
        _fail("corridor tree root was not attached to authoritative Main")
        return
    if int(runtime.call("collision_count")) != EXPECTED_TREES:
        _fail("collision contract changed")
        return
    if not bool(runtime.call("source_positions_unchanged")):
        _fail("source-backed positions changed")
        return
    if str(tree_root.get_meta("source", "")) != "OpenStreetMap contributors via Overpass API":
        _fail("source provenance changed")
        return
    if str(tree_root.get_meta("license", "")) != "ODbL-1.0":
        _fail("license provenance changed")
        return
    if foreign_main != null and foreign_main.get_node_or_null("BrusselsCorridorTrees") != null:
        _fail("foreign owner stole corridor trees after authoritative Main arrived")
        return
    print("BRUSSELS_CORRIDOR_TREE_NESTED_MOUNT_OK: trees=%d collisions=%d foreign_decoy_rejected=true owner=root-viewport-main source=OSM license=ODbL-1.0" % [tree_count, int(runtime.call("collision_count"))])
    quit(0)
