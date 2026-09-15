extends SceneTree

const EXPECTED_TREE_COUNT := 7
const ANNEESSENS := Vector3(-272.04, 0.0, -217.07)
const RUNTIME_PATH := "res://game/scripts/anneessens_osm_furniture_runtime.gd"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ANNEESSENS_OSM_AUTHORITATIVE_ROOT_BIND_FAIL: %s" % message)
    quit(1)

func _make_anchor(name_value: String) -> Node3D:
    var node := Node3D.new()
    node.name = name_value
    return node

func _make_forged_main() -> Node3D:
    var decoy := Node3D.new()
    decoy.name = "Main"
    decoy.add_child(_make_anchor("BrusselsOSM"))
    decoy.add_child(_make_anchor("UrbISMidiExact"))
    var decoy_player := _make_anchor("Player")
    decoy_player.position = ANNEESSENS
    decoy.add_child(decoy_player)
    return decoy

func _run() -> void:
    var runtime := root.get_node_or_null("AnneessensOsmFurnitureRuntime")
    if runtime == null:
        _fail("AnneessensOsmFurnitureRuntime autoload missing")
        return

    # Lock the intended production identity contract as well as its behavior.
    # This prevents a future implementation from merely special-casing this decoy
    # while continuing to authorize arbitrary root children by node name.
    var runtime_source := FileAccess.get_file_as_string(RUNTIME_PATH)
    if runtime_source.is_empty():
        _fail("runtime source unavailable for identity contract")
        return
    if "scene_file_path" not in runtime_source or "res://game/main.tscn" not in runtime_source:
        _fail("runtime does not bind fallback ownership to canonical packed scene identity")
        return

    # Both automatic fallback topologies accepted by the runtime are adversarially
    # reproduced here: a direct root child and a Main nested one Viewport below root.
    # Neither may become Shared Environment owner from node naming/anchors alone.
    var root_decoy := _make_forged_main()
    root.add_child(root_decoy)

    var viewport := SubViewport.new()
    viewport.name = "ForgedProductionViewport"
    root.add_child(viewport)
    var viewport_decoy := _make_forged_main()
    viewport.add_child(viewport_decoy)

    for _frame: int in range(8):
        await process_frame

    if root_decoy.get_node_or_null("AnneessensOsmFurniture") != null:
        _fail("runtime mounted source-backed furniture under forged root-level Main")
        return
    if viewport_decoy.get_node_or_null("AnneessensOsmFurniture") != null:
        _fail("runtime mounted source-backed furniture under forged Viewport Main")
        return
    if int(runtime.call("tree_count")) != 0:
        _fail("runtime allocated trees for forged Main fallback topology")
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

    if root_decoy.get_node_or_null("AnneessensOsmFurniture") != null:
        _fail("forged root-level Main acquired furniture after real production scene appeared")
        return
    if viewport_decoy.get_node_or_null("AnneessensOsmFurniture") != null:
        _fail("forged Viewport Main acquired furniture after real production scene appeared")
        return
    var furniture_root := scene.get_node_or_null("AnneessensOsmFurniture")
    if furniture_root == null:
        _fail("authoritative Main did not receive Anneessens furniture")
        return
    var count := int(runtime.call("tree_count"))
    if count != EXPECTED_TREE_COUNT or furniture_root.get_child_count() != EXPECTED_TREE_COUNT:
        _fail("authoritative Main tree count mismatch: runtime=%d root=%d expected=%d" % [count, furniture_root.get_child_count(), EXPECTED_TREE_COUNT])
        return

    print("ANNEESSENS_OSM_AUTHORITATIVE_ROOT_BIND_OK: forged_root_main_rejected=true forged_viewport_main_rejected=true production_scene=res://game/main.tscn trees=%d current_scene=null" % count)
    quit(0)
