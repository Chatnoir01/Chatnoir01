extends SceneTree

const TREE_DATA := "res://data/environment/laeken_jette/official_city_trees.game.json"


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("LAEKEN_OFFICIAL_TREES_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    if not FileAccess.file_exists(TREE_DATA):
        _fail("official City of Brussels tree runtime missing")
        return
    var packed := load("res://game/zones/laeken_jette/laeken_jette.tscn") as PackedScene
    if packed == null:
        _fail("Laeken scene failed to load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    for _i in range(14):
        await process_frame

    var tree_pass = scene.get_node_or_null("OfficialTrees")
    if tree_pass == null:
        _fail("OfficialTrees node missing")
        return
    if not bool(tree_pass.get("trees_loaded")):
        _fail("official tree population did not load")
        return

    var total := int(tree_pass.get("official_tree_count"))
    var grounded := int(tree_pass.get("terrain_grounded_count"))
    var broadleaf := int(tree_pass.get("broadleaf_count"))
    var conifer := int(tree_pass.get("conifer_count"))
    var columnar := int(tree_pass.get("columnar_count"))
    var skipped := int(tree_pass.get("skipped_count"))

    if total < 7500:
        _fail("too few official trees rendered: %d" % total)
        return
    if grounded != total:
        _fail("rendered tree / terrain-grounded mismatch: %d vs %d" % [total, grounded])
        return
    if broadleaf < 5000:
        _fail("broadleaf population unexpectedly small: %d" % broadleaf)
        return
    if conifer < 500:
        _fail("conifer population unexpectedly small: %d" % conifer)
        return
    if columnar < 1:
        _fail("columnar classifier produced no trees")
        return
    if skipped > 800:
        _fail("too many official records skipped: %d" % skipped)
        return

    var trunks := scene.get_node_or_null("OfficialTrees/OfficialTreeTrunks") as MultiMeshInstance3D
    var broadleaf_node := scene.get_node_or_null("OfficialTrees/OfficialBroadleafCrowns") as MultiMeshInstance3D
    var conifer_node := scene.get_node_or_null("OfficialTrees/OfficialConiferCrowns") as MultiMeshInstance3D
    if trunks == null or trunks.multimesh == null:
        _fail("trunk MultiMesh missing")
        return
    if broadleaf_node == null or broadleaf_node.multimesh == null:
        _fail("broadleaf crown MultiMesh missing")
        return
    if conifer_node == null or conifer_node.multimesh == null:
        _fail("conifer crown MultiMesh missing")
        return
    if trunks.multimesh.instance_count != total:
        _fail("trunk MultiMesh instance count mismatch: %d != %d" % [trunks.multimesh.instance_count, total])
        return

    var approach := scene.get_node_or_null("AtomiumApproachPhotoGuided")
    var fake_trees := 0
    if approach != null:
        for child in approach.get_children():
            if child.name == "ApproachTree":
                fake_trees += 1
    if fake_trees > 0:
        _fail("photo-guided placeholder trees still visible after official tree import: %d" % fake_trees)
        return

    print("LAEKEN_OFFICIAL_TREES_OK: total=%d grounded=%d broadleaf=%d conifer=%d columnar=%d skipped=%d" % [total, grounded, broadleaf, conifer, columnar, skipped])
    scene.queue_free()
    await process_frame
    quit(0)
