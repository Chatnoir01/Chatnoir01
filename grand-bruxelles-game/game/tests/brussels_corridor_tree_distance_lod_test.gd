extends SceneTree

const RUNTIME := preload("res://game/scripts/brussels_corridor_tree_runtime.gd")
const TREE := preload("res://game/scripts/brussels_street_tree_asset.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_CORRIDOR_TREE_LOD_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var runtime := RUNTIME.new()
    root.add_child(runtime)
    runtime.set_process(false)
    if not "tree_full_detail_radius_m" in runtime:
        _fail("corridor distance-aware tree LOD radius missing")
        return
    if not runtime.has_method("foliage_lobe_indices_for_distance"):
        _fail("corridor tree LOD selector missing")
        return
    var radius := float(runtime.tree_full_detail_radius_m)
    if absf(radius - 140.0) > 0.001:
        _fail("corridor tree LOD radius drifted from validated 140 m policy")
        return
    var near_indices := runtime.call("foliage_lobe_indices_for_distance", radius - 1.0) as Array
    var far_indices := runtime.call("foliage_lobe_indices_for_distance", radius + 1.0) as Array
    if near_indices.size() != TREE.FOLIAGE_LOBE_COUNT:
        _fail("near corridor tree lost full-detail crown")
        return
    if far_indices != [0, 3, 6]:
        _fail("far corridor tree must use deterministic 0/3/6 crown")
        return
    var full_detail_foliage := 266 * TREE.FOLIAGE_LOBE_COUNT
    var all_far_foliage := 266 * far_indices.size()
    if all_far_foliage >= full_detail_foliage:
        _fail("corridor LOD does not reduce foliage instances")
        return
    print("BRUSSELS_CORRIDOR_TREE_LOD_OK: radius_m=%.1f near_lobes=%d far_lobes=%d full_detail_foliage=%d all_far_foliage=%d" % [radius, near_indices.size(), far_indices.size(), full_detail_foliage, all_far_foliage])
    quit(0)
