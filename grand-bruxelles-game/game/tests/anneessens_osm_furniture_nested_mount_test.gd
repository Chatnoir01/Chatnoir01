extends SceneTree

const RUNTIME_PATH := "res://game/scripts/anneessens_osm_furniture_runtime.gd"
const EXPECTED_TREES := 7

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ANNEESSENS_OSM_FURNITURE_NESTED_MOUNT_FAIL: %s" % message)
    quit(1)

func _make_foreign_nested_decoy() -> Node3D:
    var wrapper := Node3D.new()
    wrapper.name = "ForeignEnvironmentOwner"
    var decoy := Node3D.new()
    decoy.name = "ForeignNestedMain"
    wrapper.add_child(decoy)

    var brussels_osm := Node3D.new()
    brussels_osm.name = "BrusselsOSM"
    decoy.add_child(brussels_osm)

    var urbis_midi := Node3D.new()
    urbis_midi.name = "UrbISMidiExact"
    decoy.add_child(urbis_midi)

    var player := Node3D.new()
    player.name = "Player"
    decoy.add_child(player)
    return wrapper

func _make_foreign_nested_viewport_decoy() -> Node3D:
    var wrapper := Node3D.new()
    wrapper.name = "ForeignViewportOwner"

    var viewport := SubViewport.new()
    viewport.name = "ForeignNestedViewport"
    wrapper.add_child(viewport)

    var decoy := Node3D.new()
    decoy.name = "Main"
    viewport.add_child(decoy)

    var brussels_osm := Node3D.new()
    brussels_osm.name = "BrusselsOSM"
    decoy.add_child(brussels_osm)

    var urbis_midi := Node3D.new()
    urbis_midi.name = "UrbISMidiExact"
    decoy.add_child(urbis_midi)

    var player := Node3D.new()
    player.name = "Player"
    decoy.add_child(player)
    return wrapper

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

    for _frame: int in range(8):
        await process_frame
    if int(runtime.call("tree_count")) != 0:
        _fail("runtime built furniture before a valid production mount existed")
        return

    # A foreign nested node can legitimately expose the same anchor names. It must
    # never acquire authority for source-backed Anneessens furniture or collisions.
    var foreign_wrapper := _make_foreign_nested_decoy()
    root.add_child(foreign_wrapper)
    for _frame: int in range(12):
        await process_frame
    if int(runtime.call("tree_count")) != 0:
        _fail("foreign nested anchor clone captured Anneessens furniture authority")
        return
    var foreign_main := foreign_wrapper.get_node_or_null("ForeignNestedMain")
    if foreign_main != null and foreign_main.get_node_or_null("AnneessensOsmFurniture") != null:
        _fail("foreign nested anchor clone received owned Anneessens furniture root")
        return

    # A Viewport wrapper does not make an arbitrary nested Main authoritative. Only
    # a root-level dormant viewport mount may provide the established fallback owner.
    var foreign_viewport_wrapper := _make_foreign_nested_viewport_decoy()
    root.add_child(foreign_viewport_wrapper)
    for _frame: int in range(12):
        await process_frame
    if int(runtime.call("tree_count")) != 0:
        _fail("foreign nested viewport Main captured Anneessens furniture authority")
        return
    var foreign_viewport := foreign_viewport_wrapper.get_node_or_null("ForeignNestedViewport") as SubViewport
    var foreign_viewport_main := foreign_viewport.get_node_or_null("Main") if foreign_viewport != null else null
    if foreign_viewport_main != null and foreign_viewport_main.get_node_or_null("AnneessensOsmFurniture") != null:
        _fail("foreign nested viewport Main received owned Anneessens furniture root")
        return

    # Preserve the already-gated legitimate dormant mount contract: Main directly
    # under a root-level Viewport is authoritative even when current_scene is null.
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

    for _frame: int in range(24):
        await process_frame

    var tree_count := int(runtime.call("tree_count"))
    if tree_count != EXPECTED_TREES:
        _fail("nested production mount did not bind Anneessens furniture: trees=%d expected=%d" % [tree_count, EXPECTED_TREES])
        return
    var furniture_root := main.get_node_or_null("AnneessensOsmFurniture")
    if furniture_root == null:
        _fail("Anneessens furniture was not attached to nested Main")
        return
    if foreign_main != null and foreign_main.get_node_or_null("AnneessensOsmFurniture") != null:
        _fail("foreign nested anchor clone stole furniture after authoritative Main arrived")
        return
    if foreign_viewport_main != null and foreign_viewport_main.get_node_or_null("AnneessensOsmFurniture") != null:
        _fail("foreign nested viewport Main stole furniture after authoritative Main arrived")
        return
    if str(furniture_root.get_meta("source", "")) != "OpenStreetMap contributors via Overpass API":
        _fail("source provenance changed")
        return
    if str(furniture_root.get_meta("license", "")) != "ODbL-1.0":
        _fail("license provenance changed")
        return

    print("ANNEESSENS_OSM_FURNITURE_NESTED_MOUNT_OK: trees=%d current_scene=null owner=root-viewport-main foreign_decoys_rejected=true source=OSM license=ODbL-1.0" % tree_count)
    quit(0)
