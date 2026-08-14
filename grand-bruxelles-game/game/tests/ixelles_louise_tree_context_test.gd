extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const SOURCE_PATH := "res://data/sources/ixelles/avenue_louise_alignment_trees.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("IXELLES_LOUISE_TREE_CONTEXT_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
    if not parsed is Dictionary:
        _fail("source contract invalid")
        return
    var source := parsed as Dictionary
    if str(source.get("cell_id", "")) != "bxl-e149000-n169000-s500":
        _fail("cell drifted")
        return
    if bool(source.get("runtime_approved", true)) or bool(source.get("promote_runtime", true)):
        _fail("cue must remain locally provisional")
        return
    var trees: Variant = source.get("trees", [])
    if not trees is Array or trees.size() != 21:
        _fail("selected tree count drifted")
        return
    for raw: Variant in trees:
        if not raw is Dictionary:
            _fail("tree record invalid")
            return
        var tree := raw as Dictionary
        if str(tree.get("status", "")) != "en vie" or str(tree.get("road", "")) != "Louise (Av.)":
            _fail("non-live/non-Louise tree entered cue")
            return
        if float(tree.get("height_m", 0.0)) <= 0.0 or float(tree.get("crown_diameter_m", 0.0)) <= 0.0:
            _fail("source dimensions missing")
            return

    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    await process_frame
    var player := main.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _fail("player missing")
        return
    player.call("_apply_direct_spawn_from_user_args", PackedStringArray(["spawn=ixelles"]))
    for _frame: int in range(12):
        await process_frame
    var slice := main.get_node_or_null("IxellesDirectMicroSlice")
    if slice == null or not bool(slice.get("runtime_loaded")):
        _fail("Ixelles runtime unavailable")
        return
    if int(slice.get("building_count")) != 260 or int(slice.get("skipped_unapproved_height_buildings")) != 460:
        _fail("building/no-invention invariant drifted")
        return
    if int(slice.get("street_surface_count")) != 309 or int(slice.get("street_segment_count")) != 277:
        _fail("street invariant drifted")
        return
    if not bool(slice.get("louise_tree_context_built")) or int(slice.get("louise_tree_count")) != 21:
        _fail("official tree context not built")
        return
    var root_node := slice.get_node_or_null("OfficialLouiseAlignmentTrees")
    if root_node == null or root_node.get_child_count() != 21:
        _fail("tree root count mismatch")
        return
    print("IXELLES_LOUISE_TREE_CONTEXT_OK: trees=21 buildings=260 skipped=460 streets=309 axes=277")
    quit(0)
