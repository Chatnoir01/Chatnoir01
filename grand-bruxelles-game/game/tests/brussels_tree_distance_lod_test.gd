extends SceneTree

const RUNTIME := preload("res://game/scripts/brussels_osm_environment_runtime.gd")
const TREE := preload("res://game/scripts/brussels_street_tree_asset.gd")
const JETTE_DATA := "res://data/osm/zones/jette/environment.game.json"

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
    if not FileAccess.file_exists(JETTE_DATA):
        _fail("valid environment fixture missing")
        return
    var runtime := RUNTIME.new()
    runtime.data_path = JETTE_DATA
    root.add_child(runtime)
    runtime.set_process(false)
    if not bool(runtime.call("loaded_ok")):
        _fail("valid environment fixture rejected")
        return
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
    for child in runtime.get_children():
        runtime.remove_child(child)
        child.queue_free()
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
    runtime._points = {
        "tree": [{"osm_id": 101, "position": near_base}, {"osm_id": 202, "position": far_base}],
        "street_lamp": [],
        "bollard": [],
    }
    runtime.call("_rebuild", Vector3.ZERO)
    runtime.call("_rebuild", Vector3.ZERO)
    for name_value: String in ["TreeTrunks", "TreeFoliageDark", "TreeFoliageLight"]:
        if runtime.get_node_or_null(name_value) == null:
            _fail("deterministic tree batch name lost after repeated rebuild: %s" % name_value)
            return
    print("BRUSSELS_TREE_DISTANCE_LOD_OK: trunks=2 foliage=%d full_detail=%d near_lobes=%d deterministic_rebuild=true fixture_contract=true" % [foliage_total, full_detail_total, TREE.FOLIAGE_LOBE_COUNT])
    quit(0)
