extends SceneTree

const RUNTIME := preload("res://game/scripts/brussels_osm_environment_runtime.gd")
const TREE := preload("res://game/scripts/brussels_street_tree_asset.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_TREE_DISTANCE_LOD_FAIL: %s" % message)
    quit(1)

func _instance_count(node: Node, name_value: String) -> int:
    var batch := node.get_node_or_null(name_value) as MultiMeshInstance3D
    if batch == null or batch.multimesh == null:
        return 0
    return batch.multimesh.instance_count

func _run() -> void:
    var runtime := RUNTIME.new()
    root.add_child(runtime)
    runtime.set_process(false)

    if not "tree_full_detail_radius_m" in runtime:
        _fail("distance-aware tree LOD radius missing")
        return
    if float(runtime.tree_full_detail_radius_m) <= 0.0 or float(runtime.tree_full_detail_radius_m) >= float(runtime.render_radius_m):
        _fail("tree LOD radius must be positive and below render radius")
        return

    var near_base := Vector3(10.0, 0.0, 0.0)
    var far_base := Vector3(float(runtime.tree_full_detail_radius_m) + 40.0, 0.0, 0.0)
    var rows := [
        {"osm_id": 101, "position": near_base, "distance_sq": near_base.length_squared()},
        {"osm_id": 202, "position": far_base, "distance_sq": far_base.length_squared()},
    ]
    runtime.call("_build_tree_batches", rows)

    if _instance_count(runtime, "TreeTrunks") != 2:
        _fail("tree LOD must preserve every source-backed trunk")
        return
    var foliage_total := _instance_count(runtime, "TreeFoliageDark") + _instance_count(runtime, "TreeFoliageLight")
    var full_detail_total := TREE.FOLIAGE_LOBE_COUNT * 2
    if foliage_total >= full_detail_total:
        _fail("far tree still renders full-detail foliage")
        return
    if foliage_total < TREE.FOLIAGE_LOBE_COUNT + 3:
        _fail("far tree LOD removed too much crown coverage")
        return

    print("BRUSSELS_TREE_DISTANCE_LOD_OK: trunks=2 foliage=%d full_detail=%d near_lobes=%d" % [foliage_total, full_detail_total, TREE.FOLIAGE_LOBE_COUNT])
    quit(0)
