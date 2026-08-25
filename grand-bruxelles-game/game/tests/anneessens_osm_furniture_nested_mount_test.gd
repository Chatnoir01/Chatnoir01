extends SceneTree

const RUNTIME_PATH := "res://game/scripts/anneessens_osm_furniture_runtime.gd"
const EXPECTED_TREES := 7

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ANNEESSENS_OSM_FURNITURE_NESTED_MOUNT_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    if current_scene != null:
        _fail("script witness requires current_scene == null")
        return

    var runtime_script := load(RUNTIME_PATH) as Script
    if runtime_script == null:
        _fail("runtime script missing")
        return
    var runtime := runtime_script.new() as Node
    if runtime == null:
        _fail("runtime is not a Node")
        return
    runtime.name = "AnneessensOsmFurnitureNestedWitness"
    root.add_child(runtime)

    # Legitimate absence must remain dormant and must not fabricate furniture.
    for _frame: int in range(8):
        await process_frame
    if int(runtime.call("tree_count")) != 0:
        _fail("runtime built furniture before a valid production mount existed")
        return

    # Historical player/evidence mounts may place Main under a SubViewport while
    # SceneTree.current_scene stays null. The runtime must discover this bounded
    # production shape rather than only scanning direct root Node3D children.
    var viewport := SubViewport.new()
    viewport.name = "NestedEnvironmentViewport"
    root.add_child(viewport)

    var main := Node3D.new()
    main.name = "Main"
    viewport.add_child(main)

    var brussels_osm := Node3D.new()
    brussels_osm.name = "BrusselsOSM"
    main.add_child(brussels_osm)

    var urbis_midi := Node3D.new()
    urbis_midi.name = "UrbISMidiExact"
    main.add_child(urbis_midi)

    var player := Node3D.new()
    player.name = "Player"
    main.add_child(player)

    for _frame: int in range(16):
        await process_frame

    var tree_count := int(runtime.call("tree_count"))
    if tree_count != EXPECTED_TREES:
        _fail("nested production mount did not bind Anneessens furniture: trees=%d expected=%d" % [tree_count, EXPECTED_TREES])
        return
    var furniture_root := main.get_node_or_null("AnneessensOsmFurniture")
    if furniture_root == null:
        _fail("Anneessens furniture was not attached to nested Main")
        return
    if str(furniture_root.get_meta("source", "")) != "OpenStreetMap contributors via Overpass API":
        _fail("source provenance changed")
        return
    if str(furniture_root.get_meta("license", "")) != "ODbL-1.0":
        _fail("license provenance changed")
        return

    print("ANNEESSENS_OSM_FURNITURE_NESTED_MOUNT_OK: trees=%d current_scene=null source=OSM license=ODbL-1.0" % tree_count)
    quit(0)
