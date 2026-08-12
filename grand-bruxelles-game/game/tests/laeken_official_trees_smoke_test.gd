extends SceneTree

const TREE_DATA := "res://data/environment/laeken_jette/official_city_trees.game.json"
const HERO_AUDIT := "res://data/reference/laeken_jette/atomium_ground_foreground_inventory.json"


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("LAEKEN_OFFICIAL_TREES_FAIL: %s" % message)
    quit(1)


func _instance_count(node: MultiMeshInstance3D) -> int:
    return node.multimesh.instance_count if node != null and node.multimesh != null else 0


func _run() -> void:
    if not FileAccess.file_exists(TREE_DATA):
        _fail("official City of Brussels tree runtime missing")
        return
    if not FileAccess.file_exists(HERO_AUDIT):
        _fail("Atomium source-tree hero audit missing")
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
    var hero := int(tree_pass.get("hero_tree_count"))
    var hero_expected := int(tree_pass.get("hero_tree_expected_count"))
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
    if hero_expected != 17:
        _fail("unexpected Atomium hero-tree evidence count: %d" % hero_expected)
        return
    if hero != hero_expected:
        _fail("not all source-audited Atomium hero trees rendered: %d/%d" % [hero, hero_expected])
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
    var hero_trunks := scene.get_node_or_null("OfficialTrees/AtomiumHeroTreeTrunks") as MultiMeshInstance3D
    var broadleaf_node := scene.get_node_or_null("OfficialTrees/OfficialBroadleafCrowns") as MultiMeshInstance3D
    var hero_broadleaf_node := scene.get_node_or_null("OfficialTrees/AtomiumHeroBroadleafCrowns") as MultiMeshInstance3D
    var conifer_node := scene.get_node_or_null("OfficialTrees/OfficialConiferCrowns") as MultiMeshInstance3D
    if trunks == null or trunks.multimesh == null:
        _fail("standard trunk MultiMesh missing")
        return
    if hero_trunks == null or hero_trunks.multimesh == null:
        _fail("Atomium hero trunk MultiMesh missing")
        return
    if broadleaf_node == null or broadleaf_node.multimesh == null:
        _fail("broadleaf crown MultiMesh missing")
        return
    if hero_broadleaf_node == null or hero_broadleaf_node.multimesh == null:
        _fail("Atomium hero broadleaf crown MultiMesh missing")
        return
    if conifer_node == null or conifer_node.multimesh == null:
        _fail("conifer crown MultiMesh missing")
        return
    if _instance_count(trunks) + _instance_count(hero_trunks) != total:
        _fail("combined trunk MultiMesh count mismatch: %d + %d != %d" % [
            _instance_count(trunks), _instance_count(hero_trunks), total
        ])
        return
    if _instance_count(hero_trunks) != hero:
        _fail("hero trunk instance count mismatch: %d != %d" % [_instance_count(hero_trunks), hero])
        return

    var standard_trunk_mesh := trunks.multimesh.mesh as CylinderMesh
    var hero_trunk_mesh := hero_trunks.multimesh.mesh as CylinderMesh
    var standard_crown_mesh := broadleaf_node.multimesh.mesh as SphereMesh
    var hero_crown_mesh := hero_broadleaf_node.multimesh.mesh as SphereMesh
    if standard_trunk_mesh == null or hero_trunk_mesh == null:
        _fail("trunk mesh types invalid")
        return
    if standard_crown_mesh == null or hero_crown_mesh == null:
        _fail("broadleaf crown mesh types invalid")
        return
    if hero_trunk_mesh.radial_segments <= standard_trunk_mesh.radial_segments:
        _fail("hero trunk LOD is not denser than standard LOD")
        return
    if hero_crown_mesh.radial_segments <= standard_crown_mesh.radial_segments or hero_crown_mesh.rings <= standard_crown_mesh.rings:
        _fail("hero broadleaf LOD is not denser than standard LOD")
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

    print("LAEKEN_OFFICIAL_TREES_OK: total=%d hero=%d/%d grounded=%d broadleaf=%d conifer=%d columnar=%d skipped=%d" % [
        total, hero, hero_expected, grounded, broadleaf, conifer, columnar, skipped
    ])
    scene.queue_free()
    await process_frame
    quit(0)
