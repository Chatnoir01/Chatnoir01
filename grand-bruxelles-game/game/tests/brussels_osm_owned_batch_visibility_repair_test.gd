extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_osm_environment_runtime.gd")
const JETTE_DATA := "res://data/osm/zones/jette/environment.game.json"
const JETTE_SPAWN := Vector3(-687.700268506218, 1.05, -4952.774160383269)

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_OWNED_BATCH_VISIBILITY_REPAIR_FAIL: %s" % message)
    quit(1)

func _owned_visible_batches(runtime: Node3D) -> Array[MultiMeshInstance3D]:
    var batches: Array[MultiMeshInstance3D] = []
    for child: Node in runtime.get_children():
        if child is MultiMeshInstance3D and (child as MultiMeshInstance3D).visible:
            batches.append(child as MultiMeshInstance3D)
    return batches

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
    runtime.name = "BrusselsOsmOwnedBatchVisibilityRepairProbe"
    runtime.set("data_path", JETTE_DATA)
    world.add_child(runtime)

    for _frame: int in range(18):
        await process_frame

    var visible_batches := _owned_visible_batches(runtime)
    if visible_batches.is_empty():
        _fail("baseline did not materialize any visible source-backed MultiMesh batch")
        return

    var victim := visible_batches[0]
    var victim_id := victim.get_instance_id()
    var victim_role := str(victim.get_meta("osm_environment_batch_role", ""))
    if victim_role.is_empty():
        _fail("selected owned batch has no canonical role")
        return

    # Reproduce local visibility drift without moving the player, changing source,
    # camera, geometry, limits or LOD. The runtime still owns this batch and its
    # aggregate visibility state remains enabled, so the next refresh must repair
    # the owned child's visible property instead of silently accepting drift.
    victim.visible = false
    runtime.call("_refresh", false)

    if not is_instance_valid(victim) or victim.get_instance_id() != victim_id:
        _fail("visibility repair replaced canonical owned batch identity")
        return
    if not victim.visible:
        _fail("stationary refresh did not repair owned batch visibility drift")
        return

    print("BRUSSELS_OSM_OWNED_BATCH_VISIBILITY_REPAIR_OK: role=%s batch_identity_preserved=true source=%s license=%s" % [victim_role, str(runtime.get_meta("source", "")), str(runtime.get_meta("license", ""))])
    quit(0)
