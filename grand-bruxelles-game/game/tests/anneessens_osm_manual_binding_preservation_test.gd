extends SceneTree

const ANNEESSENS := Vector3(-272.04, 0.0, -217.07)
const EXPECTED_TREE_COUNT := 7

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ANNEESSENS_OSM_MANUAL_BIND_PRESERVATION_FAIL: %s" % message)
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

    # Manual/test binding is an explicit API and must remain usable even when the
    # scene is intentionally not the canonical packed production scene. The
    # automatic fallback identity hardening must not accidentally break this rail.
    var harness := Node3D.new()
    harness.name = "ManualAnneessensHarness"
    root.add_child(harness)
    harness.add_child(_make_anchor("BrusselsOSM"))
    harness.add_child(_make_anchor("UrbISMidiExact"))
    var player := _make_anchor("Player")
    player.position = ANNEESSENS
    harness.add_child(player)

    if harness.scene_file_path == "res://game/main.tscn":
        _fail("manual harness unexpectedly carries canonical production scene identity")
        return

    runtime.call("bind_scene", harness)
    for _i in range(8):
        await process_frame

    var furniture_root := harness.get_node_or_null("AnneessensOsmFurniture")
    if furniture_root == null:
        _fail("explicit bind_scene no longer mounts furniture on non-canonical harness")
        return
    var count := int(runtime.call("tree_count"))
    if count != EXPECTED_TREE_COUNT or furniture_root.get_child_count() != EXPECTED_TREE_COUNT:
        _fail("manual binding tree count mismatch: runtime=%d root=%d expected=%d" % [count, furniture_root.get_child_count(), EXPECTED_TREE_COUNT])
        return

    # A forged automatic-looking Main appearing afterwards must not steal ownership
    # from an explicit manual binding.
    var forged := Node3D.new()
    forged.name = "Main"
    root.add_child(forged)
    forged.add_child(_make_anchor("BrusselsOSM"))
    forged.add_child(_make_anchor("UrbISMidiExact"))
    forged.add_child(_make_anchor("Player"))
    for _i in range(4):
        await process_frame
    if forged.get_node_or_null("AnneessensOsmFurniture") != null:
        _fail("forged Main stole explicit manual ownership")
        return
    if int(runtime.call("tree_count")) != EXPECTED_TREE_COUNT:
        _fail("manual tree allocation changed after forged Main appeared")
        return

    print("ANNEESSENS_OSM_MANUAL_BIND_PRESERVATION_OK: canonical_identity_required_for_auto_only=true manual_trees=%d forged_main_rejected=true" % count)
    quit(0)
