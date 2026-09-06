extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_osm_environment_runtime.gd")
const JETTE_DATA := "res://data/osm/zones/jette/environment.game.json"
const JETTE_SPAWN := Vector3(-687.700268506218, 1.05, -4952.774160383269)

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_STATIC_RESOURCE_REUSE_FAIL: %s" % message)
    quit(1)

func _batch(runtime: Node3D, batch_name: String) -> MultiMeshInstance3D:
    return runtime.get_node_or_null(batch_name) as MultiMeshInstance3D

func _mesh_id(runtime: Node3D, batch_name: String) -> int:
    var batch := _batch(runtime, batch_name)
    if batch == null or batch.multimesh == null or batch.multimesh.mesh == null:
        return 0
    return batch.multimesh.mesh.get_instance_id()

func _material_id(runtime: Node3D, batch_name: String) -> int:
    var batch := _batch(runtime, batch_name)
    if batch == null or batch.multimesh == null or batch.multimesh.mesh == null:
        return 0
    var material: Material = batch.multimesh.mesh.material
    return material.get_instance_id() if material != null else 0

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
    runtime.name = "BrusselsOsmStaticResourceReuseProbe"
    runtime.set("data_path", JETTE_DATA)
    runtime.set("refresh_distance_m", 1.0)
    world.add_child(runtime)

    for _frame: int in range(18):
        await process_frame

    var baseline_batch := _batch(runtime, "TreeTrunks")
    var baseline_mesh_id := _mesh_id(runtime, "TreeTrunks")
    var baseline_material_id := _material_id(runtime, "TreeTrunks")
    if baseline_batch == null or baseline_batch.multimesh == null or baseline_mesh_id == 0 or baseline_material_id == 0:
        _fail("baseline did not materialize the source-backed Jette tree trunk batch")
        return
    var baseline_batch_id := baseline_batch.get_instance_id()
    var baseline_multimesh_id := baseline_batch.multimesh.get_instance_id()
    var baseline_anchor: Vector3 = runtime.get("_last_anchor")

    player.position += Vector3(2.0, 0.0, 0.0)
    runtime.call("_refresh", false)

    var refreshed_batch := _batch(runtime, "TreeTrunks")
    if refreshed_batch == null:
        _fail("horizontal movement removed the source-backed tree trunk batch")
        return
    if refreshed_batch.get_instance_id() != baseline_batch_id:
        _fail("spatial refresh replaced reusable tree trunk batch identity")
        return
    if refreshed_batch.multimesh == null or refreshed_batch.multimesh.get_instance_id() != baseline_multimesh_id:
        _fail("spatial refresh replaced reusable tree trunk MultiMesh")
        return
    if _mesh_id(runtime, "TreeTrunks") != baseline_mesh_id:
        _fail("spatial refresh recreated immutable tree trunk mesh instead of reusing it")
        return
    if _material_id(runtime, "TreeTrunks") != baseline_material_id:
        _fail("spatial refresh recreated immutable tree trunk material instead of reusing it")
        return
    var refreshed_anchor: Vector3 = runtime.get("_last_anchor")
    if refreshed_anchor == baseline_anchor:
        _fail("spatial refresh preserved resources but did not advance the renderer anchor")
        return
    if absf(refreshed_anchor.x - player.global_position.x) > 0.001 or absf(refreshed_anchor.z - player.global_position.z) > 0.001:
        _fail("spatial refresh did not advance the renderer anchor to the Player")
        return

    print("BRUSSELS_OSM_STATIC_RESOURCE_REUSE_OK: batch_reused=true multimesh_reused=true immutable_tree_mesh_reused=true immutable_tree_material_reused=true source=%s license=%s" % [str(runtime.get_meta("source", "")), str(runtime.get_meta("license", ""))])
    quit(0)
