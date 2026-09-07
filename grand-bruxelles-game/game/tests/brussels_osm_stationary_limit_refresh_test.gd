extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_osm_environment_runtime.gd")
const JETTE_DATA := "res://data/osm/zones/jette/environment.game.json"
const JETTE_SPAWN := Vector3(-687.700268506218, 1.05, -4952.774160383269)

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_STATIONARY_LIMIT_REFRESH_FAIL: %s" % message)
    quit(1)

func _batch_ids(runtime: Node3D) -> Array[int]:
    var ids: Array[int] = []
    for child: Node in runtime.get_children():
        if child is MultiMeshInstance3D:
            ids.append(child.get_instance_id())
    ids.sort()
    return ids

func _total_render_count(runtime: Node3D) -> int:
    var counts := runtime.get("last_render_counts") as Dictionary
    return int(counts.get("tree", 0)) + int(counts.get("street_lamp", 0)) + int(counts.get("bollard", 0))

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
    player.position = JETTE_SPAWN
    world.add_child(player)

    var runtime := RUNTIME_SCRIPT.new() as Node3D
    runtime.name = "BrusselsOsmStationaryLimitRefreshProbe"
    runtime.set("data_path", JETTE_DATA)
    world.add_child(runtime)

    for _frame: int in range(18):
        await process_frame

    var baseline_total := _total_render_count(runtime)
    if baseline_total <= 0:
        _fail("baseline did not materialize any source-backed Jette environment points")
        return
    var baseline_anchor: Vector3 = runtime.get("_last_anchor")
    var baseline_batch_ids := _batch_ids(runtime)
    if baseline_batch_ids.is_empty():
        _fail("baseline did not materialize reusable MultiMesh batches")
        return

    runtime.set("max_trees", 0)
    runtime.set("max_street_lamps", 0)
    runtime.set("max_bollards", 0)
    runtime.call("_refresh", false)

    if runtime.get("_last_anchor") != baseline_anchor:
        _fail("stationary limit refresh moved the authoritative player anchor")
        return
    if _total_render_count(runtime) != 0:
        _fail("stationary max_* limit change did not rebuild source-backed environment selection")
        return
    if _batch_ids(runtime) != baseline_batch_ids:
        _fail("stationary limit refresh replaced reusable MultiMesh batch identity")
        return

    print("BRUSSELS_OSM_STATIONARY_LIMIT_REFRESH_OK: baseline_total=%d final_total=0 anchor_unchanged=true batch_identity_preserved=true source=%s license=%s" % [baseline_total, str(runtime.get_meta("source", "")), str(runtime.get_meta("license", ""))])
    quit(0)
