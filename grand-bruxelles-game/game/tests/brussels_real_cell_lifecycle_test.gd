extends SceneTree

const STREAMER_SCRIPT := preload("res://game/scripts/brussels_cell_streaming_manager.gd")
const BACKEND_SCRIPT := preload("res://game/scripts/brussels_cell_node_backend.gd")
const CELL_ID := "bxl-e149000-n169000-s500"
const MANIFEST_PATH := "res://data/urbis/remaining_brussels/cells/bxl-e149000-n169000-s500/manifest.json"
const RUNTIME_CELL_PATH := "res://data/urbis/remaining_brussels/cells/bxl-e149000-n169000-s500/runtime/cell.game.json"
const IXELLES_STREAMED_SCRIPT_PATH := "res://game/zones/ixelles/ixelles_streamed_microslice.gd"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_REAL_CELL_LIFECYCLE_FAIL: %s" % message)
    quit(1)

func _expect(condition: bool, message: String) -> bool:
    if not condition:
        _fail(message)
        return false
    return true

func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    return parsed as Dictionary

func _wait_for_loaded_cell(backend: BrusselsCellNodeBackend, max_frames: int = 60) -> Node:
    var cell: Node = null
    for _frame_index: int in range(max_frames):
        await process_frame
        if backend.has_active_instance(CELL_ID):
            cell = backend.get_instance(CELL_ID)
            if is_instance_valid(cell) and bool(cell.get("runtime_loaded")):
                return cell
    return cell

func _run() -> void:
    var manifest := _read_json(MANIFEST_PATH)
    var runtime_cell := _read_json(RUNTIME_CELL_PATH)
    if not _expect(not manifest.is_empty() and not runtime_cell.is_empty(), "real Ixelles source contracts are unavailable"):
        return

    var bbox_raw: Array = manifest.get("bbox", [])
    var coords: Dictionary = runtime_cell.get("coordinate_system", {})
    if not _expect(bbox_raw.size() == 4 and not coords.is_empty(), "Ixelles coordinate contract is incomplete"):
        return
    if not _expect(bool(coords.get("coordinates_are_current_game_world", false)), "Ixelles runtime is not marked as current game world"):
        return

    var center_e := (float(bbox_raw[0]) + float(bbox_raw[2])) * 0.5
    var center_n := (float(bbox_raw[1]) + float(bbox_raw[3])) * 0.5
    var origin_e := float(coords.get("lambert_origin_e", 0.0))
    var origin_n := float(coords.get("lambert_origin_n", 0.0))
    var anchor_x := float(coords.get("world_anchor_x", 0.0))
    var anchor_z := float(coords.get("world_anchor_z", 0.0))
    var cell_world_center := Vector3(anchor_x + (center_e - origin_e), 0.0, anchor_z - (center_n - origin_n))

    var manager := STREAMER_SCRIPT.new() as BrusselsCellStreamingManager
    manager.visual_load_radius_m = 300.0
    manager.visual_unload_radius_m = 500.0
    manager.collision_radius_m = 120.0
    manager.lookahead_seconds = 4.0
    manager.max_operations_per_tick = 1
    manager.max_active_cells = 1
    root.add_child(manager)

    var backend := BACKEND_SCRIPT.new() as BrusselsCellNodeBackend
    root.add_child(backend)
    backend.bind_manager(manager)
    if not _expect(backend.register_script_cell(CELL_ID, IXELLES_STREAMED_SCRIPT_PATH, {"build_collision": false}), "failed to bind streamed Ixelles runtime script"):
        return
    if not _expect(manager.register_manifest_dict(manifest, cell_world_center), "failed to register real Ixelles manifest"):
        return

    await process_frame
    var approach := cell_world_center + Vector3(600.0, 0.0, 0.0)
    var approach_velocity := Vector3(-100.0, 0.0, 0.0)
    var load_started_ms := Time.get_ticks_msec()
    manager.update_observer(approach, approach_velocity)
    var ixelles_node := await _wait_for_loaded_cell(backend)
    var load_elapsed_ms := Time.get_ticks_msec() - load_started_ms

    if not _expect(backend.has_active_instance(CELL_ID), "predictive approach did not instantiate real Ixelles cell"):
        return
    if not _expect(Vector2(approach.x, approach.z).distance_to(Vector2(cell_world_center.x, cell_world_center.z)) > manager.visual_load_radius_m, "probe did not prove predictive prefetch outside current load radius"):
        return
    if not _expect(is_instance_valid(ixelles_node) and bool(ixelles_node.get("runtime_loaded")), "Ixelles streamed runtime did not complete within 60 frames"):
        return
    if not _expect(int(ixelles_node.get("terrain_triangle_count")) == 125000, "unexpected Ixelles terrain triangle count"):
        return
    if not _expect(int(ixelles_node.get("building_count")) == 260, "unexpected approved Ixelles building count"):
        return
    if not _expect(not manager.is_collision_active(CELL_ID), "visual prefetch unexpectedly activated collision outside near-player radius"):
        return
    if not _expect(ixelles_node.find_child("OfficialIxellesDTMCollision", true, false) == null, "visual-prefetch backend unexpectedly built heavy terrain collision"):
        return

    var phase_ms: Dictionary = (ixelles_node.get("stream_phase_ms") as Dictionary).duplicate(true)
    var total_stream_ms := int(ixelles_node.get("stream_total_ms"))
    var max_phase_ms := int(ixelles_node.call("get_max_stream_phase_ms"))
    var vertex_chunks := int(ixelles_node.get("terrain_vertex_chunks"))
    var index_chunks := int(ixelles_node.get("terrain_index_chunks"))
    var required_phases: Array[String] = ["contracts_materials", "terrain_vertices_chunk", "terrain_indices_chunk", "terrain_mesh_commit", "street_surfaces", "buildings"]
    for phase_name: String in required_phases:
        if not _expect(phase_ms.has(phase_name), "missing streamed build telemetry phase '%s': %s" % [phase_name, phase_ms]):
            return
    if not _expect(vertex_chunks > 1 and index_chunks > 1, "terrain geometry was not actually chunked across frames"):
        return
    if not _expect(max_phase_ms <= 50, "streaming phase budget regressed above 50 ms: max=%d phases=%s" % [max_phase_ms, phase_ms]):
        return

    manager.update_observer(cell_world_center + Vector3(60.0, 0.0, 0.0), Vector3.ZERO)
    await process_frame
    await process_frame
    if not _expect(manager.is_collision_active(CELL_ID), "near-player collision tier did not activate"):
        return
    if not _expect(ixelles_node.find_child("OfficialIxellesDTMCollision", true, false) != null, "near-player collision body was not created"):
        return
    if not _expect(bool(ixelles_node.call("is_streamed_collision_enabled")), "Ixelles collision state did not report enabled"):
        return

    manager.update_observer(cell_world_center + Vector3(250.0, 0.0, 0.0), Vector3.ZERO)
    await process_frame
    await process_frame
    if not _expect(backend.has_active_instance(CELL_ID), "visual cell was unloaded when only collision should have cooled"):
        return
    if not _expect(not manager.is_collision_active(CELL_ID), "collision tier remained active outside collision radius"):
        return
    if not _expect(not bool(ixelles_node.call("is_streamed_collision_enabled")), "Ixelles collision state did not report disabled"):
        return
    if not _expect(ixelles_node.find_child("OfficialIxellesDTMCollision", true, false) == null, "heavy terrain collision was not released outside near-player radius"):
        return
    var collision_metrics: Dictionary = ixelles_node.call("get_streamed_collision_metrics")
    if not _expect(int(collision_metrics.get("enable_count", 0)) == 1 and int(collision_metrics.get("disable_count", 0)) == 1, "unexpected collision lifecycle metrics: %s" % [collision_metrics]):
        return

    manager.update_observer(cell_world_center + Vector3(900.0, 0.0, 0.0), Vector3.ZERO)
    await process_frame
    await process_frame
    if not _expect(not backend.has_active_instance(CELL_ID), "real Ixelles node was not released beyond unload radius"):
        return

    var cache_after_first: Dictionary = backend.get_asset_cache_metrics()
    if not _expect(int(cache_after_first.get("misses", 0)) == 1 and int(cache_after_first.get("hits", 0)) == 0 and int(cache_after_first.get("entries", 0)) == 1 and int(cache_after_first.get("referenced_entries", -1)) == 0, "first unload did not leave one warm unreferenced resource: %s" % [cache_after_first]):
        return

    manager.update_observer(approach, approach_velocity)
    var second_ixelles := await _wait_for_loaded_cell(backend)
    if not _expect(is_instance_valid(second_ixelles) and bool(second_ixelles.get("runtime_loaded")), "second Ixelles load from warm cache failed"):
        return
    var cache_after_second_load: Dictionary = backend.get_asset_cache_metrics()
    if not _expect(int(cache_after_second_load.get("hits", 0)) >= 1 and int(cache_after_second_load.get("misses", 0)) == 1, "second activation did not reuse warm resource cache: %s" % [cache_after_second_load]):
        return

    manager.update_observer(cell_world_center + Vector3(900.0, 0.0, 0.0), Vector3.ZERO)
    await process_frame
    await process_frame
    if not _expect(not backend.has_active_instance(CELL_ID), "second Ixelles instance was not released"):
        return

    var backend_metrics := backend.get_metrics()
    var scheduler_metrics := manager.get_metrics()
    var final_cache: Dictionary = backend.get_asset_cache_metrics()
    if not _expect(int(backend_metrics.get("load_count", 0)) == 2 and int(backend_metrics.get("unload_count", 0)) == 2 and int(backend_metrics.get("failed_load_count", -1)) == 0, "backend lifecycle counters are invalid: %s" % [backend_metrics]):
        return
    if not _expect(int(backend_metrics.get("collision_enable_count", 0)) == 1 and int(backend_metrics.get("collision_disable_count", 0)) == 1, "backend collision tier counters are invalid: %s" % [backend_metrics]):
        return
    if not _expect(int(final_cache.get("hits", 0)) >= 1 and int(final_cache.get("misses", 0)) == 1 and int(final_cache.get("referenced_entries", -1)) == 0, "asset cache final state is invalid: %s" % [final_cache]):
        return
    if not _expect(int(scheduler_metrics.get("duplicate_activation_attempts", -1)) == 0, "scheduler duplicated a real cell activation"):
        return

    print("BRUSSELS_REAL_CELL_LIFECYCLE_OK: predictive visual prefetch + streamed collision tier + warm asset cache passed; load_ms=%d max_phase_ms=%d collision=%s cache=%s" % [load_elapsed_ms, max_phase_ms, collision_metrics, final_cache])
    backend.queue_free()
    manager.queue_free()
    quit(0)
