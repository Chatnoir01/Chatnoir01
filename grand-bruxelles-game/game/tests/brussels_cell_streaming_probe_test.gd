extends SceneTree

const STREAMER_SCRIPT := preload("res://game/scripts/brussels_cell_streaming_manager.gd")
const REAL_MANIFEST_PATH := "res://data/urbis/remaining_brussels/cells/bxl-e149000-n169000-s500/manifest.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_CELL_STREAMING_PROBE_FAIL: %s" % message)
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
    var manager := STREAMER_SCRIPT.new() as BrusselsCellStreamingManager
    manager.visual_load_radius_m = 350.0
    manager.visual_unload_radius_m = 650.0
    manager.collision_radius_m = 150.0
    manager.lookahead_seconds = 4.0
    manager.max_operations_per_tick = 4
    manager.max_active_cells = 4
    root.add_child(manager)
    await process_frame

    var synthetic_cells := {
        "center": Vector3(0.0, 0.0, 0.0),
        "east": Vector3(500.0, 0.0, 0.0),
        "west": Vector3(-500.0, 0.0, 0.0),
        "far_east": Vector3(1000.0, 0.0, 0.0),
        "north": Vector3(0.0, 0.0, -500.0),
    }
    for cell_id: String in synthetic_cells.keys():
        if not _expect(manager.register_cell_descriptor(cell_id, synthetic_cells[cell_id], Rect2(), 1000), "failed to register synthetic cell %s" % cell_id):
            return

    manager.update_observer(Vector3.ZERO, Vector3.ZERO)
    if not _expect(manager.get_active_cell_ids() == ["center"], "only center should be active at rest, got %s" % [manager.get_active_cell_ids()]):
        return
    if not _expect(manager.is_collision_active("center"), "near active cell should have collision tier enabled"):
        return

    manager.update_observer(Vector3(100.0, 0.0, 0.0), Vector3(50.0, 0.0, 0.0))
    var prefetch_active := manager.get_active_cell_ids()
    if not _expect(prefetch_active.has("east"), "east cell should prefetch before observer crosses its load radius"):
        return
    if not _expect(prefetch_active.has("center"), "center cell should remain active during boundary approach"):
        return
    if not _expect(not manager.is_collision_active("east"), "prefetched east cell must not enable far collision tier"):
        return

    manager.update_observer(Vector3(600.0, 0.0, 0.0), Vector3.ZERO)
    if not _expect(manager.get_active_cell_ids().has("center"), "hysteresis should keep center active at 600 m"):
        return
    if not _expect(manager.is_collision_active("east"), "east collision should activate near observer"):
        return

    manager.update_observer(Vector3(800.0, 0.0, 0.0), Vector3.ZERO)
    if not _expect(not manager.get_active_cell_ids().has("center"), "center should unload beyond 650 m hysteresis radius"):
        return
    if not _expect(manager.get_active_cell_ids().size() <= manager.max_active_cells, "active cell cap exceeded"):
        return

    manager.update_observer(Vector3.ZERO, Vector3(-100.0, 0.0, 0.0))
    if not _expect(manager.get_priority("west") < manager.get_priority("east"), "velocity prediction should prioritize west when moving west"):
        return

    var manifest := _read_json(REAL_MANIFEST_PATH)
    if not _expect(not manifest.is_empty(), "real UrbIS cell manifest missing or invalid"):
        return
    if not _expect(manager.register_manifest_dict(manifest, Vector3(1500.0, 0.0, 0.0)), "real UrbIS manifest should register with explicit game-world center"):
        return
    var real_cell := manager.get_cell_descriptor("bxl-e149000-n169000-s500")
    var source_bbox: Rect2 = real_cell.get("source_bbox_lambert72", Rect2())
    if not _expect(is_equal_approx(source_bbox.position.x, 149000.0) and is_equal_approx(source_bbox.position.y, 169000.0) and is_equal_approx(source_bbox.size.x, 500.0) and is_equal_approx(source_bbox.size.y, 500.0), "Lambert72 source bbox must be preserved exactly"):
        return
    var runtime_paths: Dictionary = real_cell.get("runtime_paths", {})
    if not _expect(str(runtime_paths.get("geometry_file", "")) == "runtime/cell.game.json" and str(runtime_paths.get("network_file", "")) == "runtime/network.game.json", "real runtime paths were not preserved"):
        return

    var metrics := manager.get_metrics()
    if not _expect(int(metrics.get("duplicate_activation_attempts", -1)) == 0, "duplicate cell activations detected"):
        return
    if not _expect(int(metrics.get("activation_count", 0)) >= 3 and int(metrics.get("deactivation_count", 0)) >= 1, "probe did not exercise activation/deactivation lifecycle"):
        return

    print("BRUSSELS_CELL_STREAMING_PROBE_OK: predictive prefetch, hysteresis, bounded queue, collision tiers and real UrbIS manifest passed")
    manager.queue_free()
    quit(0)
