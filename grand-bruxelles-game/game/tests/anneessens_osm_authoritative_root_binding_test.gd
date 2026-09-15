extends SceneTree

const EXPECTED_TREE_COUNT := 7
const ANNEESSENS := Vector3(-272.04, 0.0, -217.07)

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ANNEESSENS_OSM_AUTHORITATIVE_ROOT_BIND_FAIL: %s" % message)
    quit(1)

func _make_anchor(name_value: String) -> Node3D:
    var node := Node3D.new()
    node.name = name_value
    return node

func _run() -> void:
    var runtime := root.get_node_or_null("AnneessensOsmFurnitureRuntime")
    if runtime == null:
        _fail("AnneessensOsmFurnitureRuntime autoload missing")
        return

    # A tooling/sandbox root can legitimately contain production-like child names,
    # including a forged Main name. Automatic Shared Environment ownership must be
    # bound to the canonical packed production scene identity, not node naming.
    var decoy := Node3D.new()
    decoy.name = "Main"
    root.add_child(decoy)
    decoy.add_child(_make_anchor("BrusselsOSM"))
    decoy.add_child(_make_anchor("UrbISMidiExact"))
    var decoy_player := _make_anchor("Player")
    decoy_player.position = ANNEESSENS
    decoy.add_child(decoy_player)

    for _frame: int in range(8):
        await process_frame

    if decoy.get_node_or_null("AnneessensOsmFurniture") != null:
        _fail("runtime mounted source-backed furniture under forged Main root")
        return
    if int(runtime.call("tree_count")) != 0:
        _fail("runtime allocated trees for forged Main root")
        return

    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("production main scene missing")
        return
    var scene := packed.instantiate() as Node3D
    if scene == null:
        _fail("production main scene did not instantiate as Node3D")
        return
    root.add_child(scene)

    if str(scene.name) != "Main":
        _fail("production root fallback identity drifted: %s" % str(scene.name))
        return
    if scene.scene_file_path != "res://game/main.tscn":
        _fail("production scene file identity drifted: %s" % scene.scene_file_path)
        return
    var player := scene.get_node_or_null("Player") as Node3D
    if player == null:
        _fail("production Player missing")
        return
    player.position = ANNEESSENS

    for _frame: int in range(24):
        await process_frame

    if decoy.get_node_or_null("AnneessensOsmFurniture") != null:
        _fail("forged Main acquired furniture after real production scene appeared")
        return
    var furniture_root := scene.get_node_or_null("AnneessensOsmFurniture")
    if furniture_root == null:
        _fail("authoritative Main did not receive Anneessens furniture")
        return
    var count := int(runtime.call("tree_count"))
    if count != EXPECTED_TREE_COUNT or furniture_root.get_child_count() != EXPECTED_TREE_COUNT:
        _fail("authoritative Main tree count mismatch: runtime=%d root=%d expected=%d" % [count, furniture_root.get_child_count(), EXPECTED_TREE_COUNT])
        return

    print("ANNEESSENS_OSM_AUTHORITATIVE_ROOT_BIND_OK: forged_main_rejected=true production_scene=res://game/main.tscn trees=%d current_scene=null" % count)
    quit(0)
