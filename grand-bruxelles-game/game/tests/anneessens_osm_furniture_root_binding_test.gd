extends SceneTree

const EXPECTED_TREE_COUNT := 7
const EXPECTED_SOURCE := "OpenStreetMap contributors via Overpass API"
const EXPECTED_LICENSE := "ODbL-1.0"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ANNEESSENS_OSM_FURNITURE_ROOT_BIND_FAIL: %s" % message)
    quit(1)

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
    if scene.get_node_or_null("BrusselsOSM") == null or scene.get_node_or_null("UrbISMidiExact") == null:
        _fail("production scene anchors missing")
        return

    var runtime := root.get_node_or_null("AnneessensOsmFurnitureRuntime")
    if runtime == null:
        _fail("AnneessensOsmFurnitureRuntime autoload missing")
        return

    for _frame: int in range(24):
        await process_frame

    var count := int(runtime.call("tree_count"))
    if count != EXPECTED_TREE_COUNT:
        _fail("runtime did not auto-discover root-instantiated production scene: trees=%d expected=%d" % [count, EXPECTED_TREE_COUNT])
        return

    var furniture_root := scene.get_node_or_null("AnneessensOsmFurniture")
    if furniture_root == null:
        _fail("AnneessensOsmFurniture was not mounted under production scene")
        return
    if furniture_root.get_child_count() != EXPECTED_TREE_COUNT:
        _fail("mounted tree count mismatch")
        return
    if str(furniture_root.get_meta("source", "")) != EXPECTED_SOURCE:
        _fail("source provenance mismatch")
        return
    if str(furniture_root.get_meta("license", "")) != EXPECTED_LICENSE:
        _fail("license provenance mismatch")
        return
    if not bool(furniture_root.get_meta("placement_source_backed", false)):
        _fail("placement source-backed contract missing")
        return
    if bool(furniture_root.get_meta("visual_dimensions_source_backed", true)):
        _fail("unsupported visual-dimensions source claim enabled")
        return

    print("ANNEESSENS_OSM_FURNITURE_ROOT_BIND_OK: trees=%d source=OSM license=ODbL-1.0 current_scene=null" % count)
    quit(0)
