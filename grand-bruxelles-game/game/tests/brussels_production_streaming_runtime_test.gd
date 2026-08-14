extends SceneTree

const PLAYABILITY_RUNTIME_SCRIPT := preload("res://game/scripts/mobile_playability_collision_runtime.gd")
const IXELLES_CELL_ID := "bxl-e149000-n169000-s500"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_PRODUCTION_STREAMING_FAIL: %s" % message)
    quit(1)

func _expect(condition: bool, message: String) -> bool:
    if not condition:
        _fail(message)
        return false
    return true

func _run() -> void:
    var world := Node3D.new()
    world.name = "Main"
    root.add_child(world)

    var player := CharacterBody3D.new()
    player.name = "Player"
    player.position = Vector3(-652.0, 1.05, 621.0)
    world.add_child(player)

    var playability := PLAYABILITY_RUNTIME_SCRIPT.new()
    playability.name = "MobilePlayabilityCollisionRuntime"
    world.add_child(playability)

    var runtime: BrusselsWorldStreamingRuntime = null
    for _frame: int in range(12):
        await process_frame
        runtime = world.get_node_or_null("WorldStreamingRuntime") as BrusselsWorldStreamingRuntime
        if runtime != null and runtime.runtime_ready:
            break
    if not _expect(runtime != null and runtime.runtime_ready, "playable scene did not attach production world streaming runtime"):
        return

    var metrics := runtime.get_streaming_metrics()
    var scheduler: Dictionary = metrics.get("scheduler", {})
    if not _expect(int(scheduler.get("registered_cells", 0)) == 4, "production runtime did not register the four-cell Ixelles cluster"):
        return
    if not _expect(int(scheduler.get("active_cells", -1)) == 0, "Ixelles cluster should not be active from the Midi start position"):
        return

    var descriptor := runtime.manager.get_cell_descriptor(IXELLES_CELL_ID)
    var center: Vector3 = descriptor.get("world_center", Vector3.ZERO)
    if not _expect(center != Vector3.ZERO, "production runtime has no source-backed Ixelles world center"):
        return

    player.global_position = center + Vector3(600.0, 1.05, 0.0)
    player.velocity = Vector3(-100.0, 0.0, 0.0)
    var ixelles: Node = null
    for _frame: int in range(90):
        await physics_frame
        await process_frame
        if runtime.backend.has_active_instance(IXELLES_CELL_ID):
            ixelles = runtime.backend.get_instance(IXELLES_CELL_ID)
            if is_instance_valid(ixelles) and bool(ixelles.get("runtime_loaded")):
                break
    if not _expect(is_instance_valid(ixelles) and bool(ixelles.get("runtime_loaded")), "production observer did not prefetch Ixelles"):
        return
    if not _expect(not runtime.manager.is_collision_active(IXELLES_CELL_ID), "production prefetch enabled Ixelles collision too early"):
        return

    player.global_position = center + Vector3(60.0, 1.05, 0.0)
    player.velocity = Vector3.ZERO
    for _frame: int in range(5):
        await physics_frame
        await process_frame
    if not _expect(runtime.manager.is_collision_active(IXELLES_CELL_ID), "production near-player collision tier did not enable"):
        return
    if not _expect(ixelles.find_child("OfficialIxellesDTMCollision", true, false) != null, "production runtime did not create Ixelles DTM collision"):
        return

    player.global_position = center + Vector3(900.0, 1.05, 0.0)
    for _frame: int in range(8):
        await physics_frame
        await process_frame
    if not _expect(not runtime.backend.has_active_instance(IXELLES_CELL_ID), "production runtime did not unload Ixelles outside hysteresis radius"):
        return

    var final_metrics := runtime.get_streaming_metrics()
    var backend_metrics: Dictionary = final_metrics.get("backend", {})
    if not _expect(int(backend_metrics.get("load_count", 0)) >= 1 and int(backend_metrics.get("unload_count", 0)) >= 1, "production backend did not complete a real cell lifecycle: %s" % [backend_metrics]):
        return

    print("BRUSSELS_PRODUCTION_STREAMING_OK: playable scene registered four source cells, prefetched Ixelles, enabled near collision and unloaded Ixelles")
    world.queue_free()
    quit(0)
