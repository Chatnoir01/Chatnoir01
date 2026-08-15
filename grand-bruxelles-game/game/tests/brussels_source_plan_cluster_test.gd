extends SceneTree

const PLAYABILITY_RUNTIME_SCRIPT := preload("res://game/scripts/mobile_playability_collision_runtime.gd")
const NORTH_CELL_ID := "bxl-e149000-n169500-s500"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_SOURCE_PLAN_CLUSTER_FAIL: %s" % message)
    quit(1)

func _expect(condition: bool, message: String) -> bool:
    if not condition:
        _fail(message)
        return false
    return true

func _contains_static_body(node: Node) -> bool:
    if node is StaticBody3D:
        return true
    for child: Node in node.get_children():
        if _contains_static_body(child):
            return true
    return false

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
    for _frame: int in range(16):
        await process_frame
        runtime = world.get_node_or_null("WorldStreamingRuntime") as BrusselsWorldStreamingRuntime
        if runtime != null and runtime.runtime_ready:
            break
    if not _expect(runtime != null and runtime.runtime_ready, "production runtime did not become ready"):
        return

    var scheduler_metrics: Dictionary = runtime.manager.get_metrics()
    if not _expect(int(scheduler_metrics.get("registered_cells", 0)) == 4, "four-cell cluster was not registered"):
        return

    var descriptor := runtime.manager.get_cell_descriptor(NORTH_CELL_ID)
    var center: Vector3 = descriptor.get("world_center", Vector3.ZERO)
    if not _expect(center != Vector3.ZERO, "north source cell has no world center"):
        return

    player.global_position = center + Vector3(0.0, 1.05, 600.0)
    player.velocity = Vector3(0.0, 0.0, -100.0)
    var source_cell: Node = null
    for _frame: int in range(100):
        await physics_frame
        await process_frame
        if runtime.backend.has_active_instance(NORTH_CELL_ID):
            source_cell = runtime.backend.get_instance(NORTH_CELL_ID)
            if is_instance_valid(source_cell) and bool(source_cell.get("runtime_loaded")):
                break

    if not _expect(is_instance_valid(source_cell) and bool(source_cell.get("runtime_loaded")), "north source-plan cell did not stream in"):
        return
    if not _expect(int(source_cell.get("street_surface_count")) == 307, "north source-plan street surface count drifted"):
        return
    if not _expect(int(source_cell.get("source_building_count")) == 375, "north source building count drifted"):
        return
    if not _expect(int(source_cell.get("blocked_unapproved_building_count")) == 375, "north unapproved building heights were not fully blocked"):
        return
    if not _expect(int(source_cell.get("rendered_building_count")) == 0, "north source-plan cell rendered unapproved building volumes"):
        return
    if not _expect(source_cell.find_child("OfficialBrusselsStreetSurfaces", true, false) != null, "source-backed street surface mesh is missing"):
        return
    if not _expect(int(source_cell.get("street_surface_chunks")) > 1, "source-plan surfaces were not chunked across frames"):
        return
    if not _expect(int(source_cell.call("get_max_stream_phase_ms")) <= 50, "source-plan build exceeded 50 ms phase guard"):
        return

    player.global_position = center + Vector3(0.0, 1.05, 40.0)
    player.velocity = Vector3.ZERO
    for _frame: int in range(5):
        await physics_frame
        await process_frame
    if not _expect(runtime.manager.is_collision_active(NORTH_CELL_ID), "scheduler did not enter near-player tier for north cell"):
        return
    if not _expect(not _contains_static_body(source_cell), "north plan-only cell invented vertical/terrain collision"):
        return

    player.global_position = center + Vector3(0.0, 1.05, 900.0)
    for _frame: int in range(10):
        await physics_frame
        await process_frame
    if not _expect(not runtime.backend.has_active_instance(NORTH_CELL_ID), "north source-plan cell did not unload outside hysteresis radius"):
        return

    print("BRUSSELS_SOURCE_PLAN_CLUSTER_OK: north cell streamed 307 official street surfaces, blocked 375 unapproved building heights, created no fake collision, and unloaded cleanly")
    world.queue_free()
    quit(0)
