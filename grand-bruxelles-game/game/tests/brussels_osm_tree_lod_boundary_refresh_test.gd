extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_osm_environment_runtime.gd")
const JETTE_DATA := "res://data/osm/zones/jette/environment.game.json"

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_TREE_LOD_BOUNDARY_REFRESH_FAIL: %s" % message)
    quit(1)

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var world := Node3D.new()
    world.name = "Main"
    root.add_child(world)
    current_scene = world

    var player := Node3D.new()
    player.name = "Player"
    player.add_to_group("player")
    world.add_child(player)

    var runtime := RUNTIME_SCRIPT.new() as Node3D
    runtime.name = "BrusselsOsmTreeLodBoundaryRefreshProbe"
    runtime.set("data_path", JETTE_DATA)
    runtime.set("render_radius_m", 350.0)
    runtime.set("refresh_distance_m", 80.0)
    runtime.set("tree_full_detail_radius_m", 140.0)
    runtime.set("max_trees", 1)
    runtime.set("max_street_lamps", 0)
    runtime.set("max_bollards", 0)
    world.add_child(runtime)

    for _frame: int in range(12):
        await process_frame

    var loaded_points: Dictionary = runtime.get("_points") as Dictionary
    var source_trees: Array = loaded_points.get("tree", []) as Array
    if source_trees.is_empty():
        _fail("validated Jette source did not provide a tree witness")
        return

    # Isolate one already validated source-backed tree so this test measures only
    # the LOD refresh contract, not nearest-neighbour selection changes.
    var witness_tree: Dictionary = (source_trees[0] as Dictionary).duplicate(true)
    var witness_position: Vector3 = witness_tree["position"]
    runtime.set("_points", {
        "tree": [witness_tree],
        "street_lamp": [],
        "bollard": [],
    })

    player.position = witness_position + Vector3(150.0, 0.0, 0.0)
    runtime.call("_refresh", true)
    var far_counts: Dictionary = runtime.get("last_tree_lod_counts") as Dictionary
    if int(far_counts.get("far", 0)) != 1 or int(far_counts.get("near", 0)) != 0:
        _fail("baseline tree was not classified far at 150m")
        return
    var trunk_before := runtime.get_node_or_null("TreeTrunks") as MultiMeshInstance3D
    if trunk_before == null or trunk_before.multimesh == null or trunk_before.multimesh.instance_count != 1:
        _fail("baseline source-backed trunk batch was not materialized exactly once")
        return
    var trunk_instance_id := trunk_before.get_instance_id()
    var trunk_multimesh_id := trunk_before.multimesh.get_instance_id()

    # 20m is deliberately below refresh_distance_m=80m, but it crosses the
    # authored 140m tree LOD boundary. Foliage detail must follow that boundary
    # without rebuilding the invariant trunk batch.
    player.position = witness_position + Vector3(130.0, 0.0, 0.0)
    runtime.call("_refresh", false)
    var near_counts: Dictionary = runtime.get("last_tree_lod_counts") as Dictionary
    if int(near_counts.get("near", 0)) != 1 or int(near_counts.get("far", 0)) != 0:
        _fail("tree LOD stayed stale after Player crossed near/far boundary inside refresh window")
        return
    var trunk_after := runtime.get_node_or_null("TreeTrunks") as MultiMeshInstance3D
    if trunk_after == null:
        _fail("tree LOD refresh removed the source-backed trunk batch")
        return
    if trunk_after.get_instance_id() != trunk_instance_id or trunk_after.multimesh == null or trunk_after.multimesh.get_instance_id() != trunk_multimesh_id:
        _fail("tree LOD-only refresh rebuilt invariant trunk batch instead of foliage only")
        return
    if trunk_after.multimesh.instance_count != 1:
        _fail("tree LOD-only refresh changed invariant trunk instance count")
        return

    print("BRUSSELS_OSM_TREE_LOD_BOUNDARY_REFRESH_OK: far_at_150m=true near_at_130m=true movement_m=20 refresh_distance_m=80 trunk_batch_preserved=true source=%s license=%s" % [str(runtime.get_meta("source", "")), str(runtime.get_meta("license", ""))])
    quit(0)
