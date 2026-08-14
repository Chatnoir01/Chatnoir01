extends SceneTree

const STREAMER_SCRIPT := preload("res://game/scripts/brussels_cell_streaming_manager.gd")
const BACKEND_SCRIPT := preload("res://game/scripts/brussels_cell_node_backend.gd")
const CELL_ID := "bxl-e149000-n169000-s500"
const MANIFEST_PATH := "res://data/urbis/remaining_brussels/cells/bxl-e149000-n169000-s500/manifest.json"
const RUNTIME_CELL_PATH := "res://data/urbis/remaining_brussels/cells/bxl-e149000-n169000-s500/runtime/cell.game.json"
const IXELLES_SCRIPT_PATH := "res://game/zones/ixelles/ixelles_microslice.gd"

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
    if not _expect(backend.register_script_cell(CELL_ID, IXELLES_SCRIPT_PATH, {"build_collision": false}), "failed to bind real Ixelles runtime script"):
        return
    if not _expect(manager.register_manifest_dict(manifest, cell_world_center), "failed to register real Ixelles manifest"):
        return

    await process_frame
    var approach := cell_world_center + Vector3(600.0, 0.0, 0.0)
    var approach_velocity := Vector3(-100.0, 0.0, 0.0)
    var load_started_ms := Time.get_ticks_msec()
    manager.update_observer(approach, approach_velocity)
    await process_frame
    await process_frame
    var load_elapsed_ms := Time.get_ticks_msec() - load_started_ms

    if not _expect(backend.has_active_instance(CELL_ID), "predictive approach did not instantiate real Ixelles cell"):
        return
    if not _expect(Vector2(approach.x, approach.z).distance_to(Vector2(cell_world_center.x, cell_world_center.z)) > manager.visual_load_radius_m, "probe did not prove predictive prefetch outside current load radius"):
        return

    var ixelles_node := backend.get_instance(CELL_ID)
    if not _expect(is_instance_valid(ixelles_node), "Ixelles node vanished after activation"):
        return
    if not _expect(bool(ixelles_node.get("runtime_loaded")), "Ixelles runtime did not complete its source-backed build"):
        return
    if not _expect(int(ixelles_node.get("terrain_triangle_count")) == 125000, "unexpected Ixelles terrain triangle count"):
        return
    if not _expect(int(ixelles_node.get("building_count")) == 260, "unexpected approved Ixelles building count"):
        return
    if not _expect(ixelles_node.find_child("OfficialIxellesDTMCollision", true, false) == null, "visual-prefetch backend unexpectedly built heavy terrain collision"):
        return

    manager.update_observer(cell_world_center + Vector3(900.0, 0.0, 0.0), Vector3.ZERO)
    await process_frame
    await process_frame
    if not _expect(not backend.has_active_instance(CELL_ID), "real Ixelles node was not released beyond unload radius"):
        return

    var backend_metrics := backend.get_metrics()
    var scheduler_metrics := manager.get_metrics()
    if not _expect(int(backend_metrics.get("load_count", 0)) == 1 and int(backend_metrics.get("unload_count", 0)) == 1 and int(backend_metrics.get("failed_load_count", -1)) == 0, "backend lifecycle counters are invalid: %s" % [backend_metrics]):
        return
    if not _expect(int(scheduler_metrics.get("duplicate_activation_attempts", -1)) == 0, "scheduler duplicated a real cell activation"):
        return

    print("BRUSSELS_REAL_CELL_LIFECYCLE_OK: Ixelles 125000-triangle/260-building cell prefetched outside radius and released; load_ms=%d center=(%.2f, %.2f)" % [load_elapsed_ms, cell_world_center.x, cell_world_center.z])
    backend.queue_free()
    manager.queue_free()
    quit(0)
