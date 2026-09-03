extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_osm_environment_runtime.gd")
const JETTE_DATA := "res://data/osm/zones/jette/environment.game.json"
const SPAWN := Vector3(-687.700268506218, 1.05, -4952.774160383269)

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_ENVIRONMENT_PLAYER_LOSS_FAIL: %s" % message)
    quit(1)

func _batch_snapshot(runtime: Node3D) -> Dictionary:
    var snapshot := {}
    for child: Node in runtime.get_children():
        if child is MultiMeshInstance3D:
            var instance := child as MultiMeshInstance3D
            snapshot[instance.name] = {
                "node_id": instance.get_instance_id(),
                "multimesh_id": instance.multimesh.get_instance_id() if instance.multimesh != null else 0,
                "instance_count": instance.multimesh.instance_count if instance.multimesh != null else -1,
            }
    return snapshot

func _all_batches_visible(runtime: Node3D, expected: bool) -> bool:
    var seen := 0
    for child: Node in runtime.get_children():
        if child is MultiMeshInstance3D:
            seen += 1
            if (child as MultiMeshInstance3D).visible != expected:
                return false
    return seen > 0

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    if current_scene != null:
        _fail("script witness requires current_scene == null")
        return

    var world := Node3D.new()
    world.name = "Main"
    root.add_child(world)

    var player := Node3D.new()
    player.name = "Player"
    player.add_to_group("player")
    player.position = SPAWN
    world.add_child(player)

    var runtime := RUNTIME_SCRIPT.new() as Node3D
    runtime.name = "BrusselsOsmEnvironmentPlayerLossProbe"
    runtime.set("data_path", JETTE_DATA)
    world.add_child(runtime)

    for _frame: int in range(18):
        await process_frame

    var counts: Dictionary = runtime.get("last_render_counts")
    if int(counts.get("tree", 0)) == 0 or int(counts.get("street_lamp", 0)) == 0:
        _fail("baseline rendered no source-backed trees/lamps")
        return
    if not _all_batches_visible(runtime, true):
        _fail("near-player baseline must expose rendered MultiMesh batches")
        return

    var baseline := _batch_snapshot(runtime)
    if baseline.is_empty():
        _fail("baseline produced no MultiMesh batches")
        return
    var source := str(runtime.get_meta("source", ""))
    var license := str(runtime.get_meta("license", ""))
    if source.is_empty() or license != "ODbL-1.0":
        _fail("OSM provenance contract missing before Player loss")
        return
    if bool(runtime.get_meta("source_dimensions_measured", true)):
        _fail("authored asset dimensions were misrepresented as source measurements")
        return

    world.remove_child(player)
    player.queue_free()
    for _frame: int in range(8):
        await process_frame

    if not _all_batches_visible(runtime, false):
        _fail("rendered OSM batches remained visible after required Player anchor disappeared")
        return

    var hidden_snapshot := _batch_snapshot(runtime)
    if hidden_snapshot != baseline:
        _fail("Player loss rebuilt or mutated source-backed batch identity")
        return

    var replacement := Node3D.new()
    replacement.name = "Player"
    replacement.add_to_group("player")
    replacement.position = SPAWN
    world.add_child(replacement)
    for _frame: int in range(8):
        await process_frame

    if not _all_batches_visible(runtime, true):
        _fail("OSM batches did not reactivate after a legitimate Player returned")
        return
    if _batch_snapshot(runtime) != baseline:
        _fail("Player recovery rebuilt source-backed geometry despite unchanged anchor")
        return
    if str(runtime.get_meta("source", "")) != source or str(runtime.get_meta("license", "")) != license:
        _fail("source/license provenance changed across Player loss recovery")
        return

    print("BRUSSELS_OSM_ENVIRONMENT_PLAYER_LOSS_OK: fail_closed=true reactivated=true geometry_rebuilt=false batches=%d source=%s license=%s" % [baseline.size(), source, license])
    quit(0)
