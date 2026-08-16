extends SceneTree

const PLAYABILITY_RUNTIME_SCRIPT := preload("res://game/scripts/mobile_playability_collision_runtime.gd")
const EAST_CELL_ID := "bxl-e149500-n169000-s500"
const EXPECTED_SOURCE_BUILDINGS := 919
const EXPECTED_VISUAL_BUILDINGS := 584
const EXPECTED_BLOCKED_BUILDINGS := EXPECTED_SOURCE_BUILDINGS - EXPECTED_VISUAL_BUILDINGS

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

    var descriptor := runtime.manager.get_cell_descriptor(EAST_CELL_ID)
    var center: Vector3 = descriptor.get("world_center", Vector3.ZERO)
    if not _expect(center != Vector3.ZERO, "east source cell has no world center"):
        return

    player.global_position = center + Vector3(600.0, 1.05, 0.0)
    player.velocity = Vector3(-100.0, 0.0, 0.0)
    var source_cell: Node = null
    for _frame: int in range(140):
        await physics_frame
        await process_frame
        if runtime.backend.has_active_instance(EAST_CELL_ID):
            source_cell = runtime.backend.get_instance(EAST_CELL_ID)
            if is_instance_valid(source_cell) and bool(source_cell.get("runtime_loaded")):
                break

    if not _expect(is_instance_valid(source_cell) and bool(source_cell.get("runtime_loaded")), "east source-plan cell did not stream in"):
        return
    if not _expect(int(source_cell.get("street_surface_count")) == 252, "east source-plan street surface count drifted"):
        return
    if not _expect(int(source_cell.get("source_building_count")) == EXPECTED_SOURCE_BUILDINGS, "east source building count drifted"):
        return
    if not _expect(bool(source_cell.get("strong_height_contract_loaded")), "east strong-height visual contract was not consumed"):
        return
    if not _expect(int(source_cell.get("rendered_building_count")) == EXPECTED_VISUAL_BUILDINGS, "eligible visual building massing count drifted"):
        return
    if not _expect(int(source_cell.get("blocked_unapproved_building_count")) == EXPECTED_BLOCKED_BUILDINGS, "non-eligible building heights were not fail-closed"):
        return
    if not _expect(source_cell.find_child("VisualCandidateBuildingMassing", true, false) != null, "combined visual building massing mesh is missing"):
        return
    if not _expect(source_cell.find_child("OfficialBrusselsStreetSurfaces", true, false) != null, "source-backed street surface mesh is missing"):
        return
    if not _expect(int(source_cell.get("street_surface_chunks")) > 1, "source-plan surfaces were not chunked across frames"):
        return
    if not _expect(int(source_cell.get("building_massing_chunks")) > 1, "visual building massing was not chunked across frames"):
        return
    if not _expect(int(source_cell.call("get_max_stream_phase_ms")) <= 50, "source-plan build exceeded 50 ms phase guard"):
        return

    player.global_position = center + Vector3(40.0, 1.05, 0.0)
    player.velocity = Vector3.ZERO
    for _frame: int in range(5):
        await physics_frame
        await process_frame
    if not _expect(runtime.manager.is_collision_active(EAST_CELL_ID), "scheduler did not enter near-player tier for east cell"):
        return
    if not _expect(not _contains_static_body(source_cell), "visual candidate massing invented gameplay collision"):
        return

    player.global_position = center + Vector3(900.0, 1.05, 0.0)
    for _frame: int in range(10):
        await physics_frame
        await process_frame
    if not _expect(not runtime.backend.has_active_instance(EAST_CELL_ID), "east source-plan cell did not unload outside hysteresis radius"):
        return

    print("BRUSSELS_SOURCE_PLAN_CLUSTER_OK: east cell streamed 252 official street surfaces, rendered 584 cross-source visual building candidates in a combined mesh, kept 335 buildings fail-closed, created no fake collision, and unloaded cleanly")
    world.queue_free()
    quit(0)
