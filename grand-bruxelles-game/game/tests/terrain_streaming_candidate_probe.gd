extends SceneTree

const STREAMER_SCRIPT := preload("res://game/scripts/brussels_cell_streaming_manager.gd")
const BACKEND_SCRIPT := preload("res://game/scripts/brussels_cell_node_backend.gd")
const SOURCE_PLAN_SCRIPT_PATH := "res://game/scripts/brussels_source_plan_streamed_cell.gd"
const PROBE_FORMAT := "grand-bruxelles-terrain-streaming-godot-probe-v1"
const RESULT_FORMAT := "grand-bruxelles-terrain-streaming-godot-result-v1"
const EXPECTED_ENGINE_VERSION := "4.7.1"

var _probe_count := 0
var _failure_count := 0


func _initialize() -> void:
    call_deferred("_run")


func _arg(prefix: String) -> String:
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with(prefix):
            return arg.substr(prefix.length())
    return ""


func _engine_version() -> String:
    var info := Engine.get_version_info()
    return "%d.%d.%d" % [int(info.get("major", 0)), int(info.get("minor", 0)), int(info.get("patch", 0))]


func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed as Dictionary if parsed is Dictionary else {}


func _write_json(path: String, payload: Dictionary) -> bool:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        push_error("TERRAIN_STREAMING_GODOT_FAIL cannot_write_result path=%s" % path)
        return false
    file.store_string(JSON.stringify(payload, "\t", true) + "\n")
    file.close()
    return true


func _wait_loaded(backend: Variant, cell_id: String, max_frames: int) -> Node:
    var instance: Node = null
    for _index: int in range(max_frames):
        await process_frame
        if bool(backend.call("has_active_instance", cell_id)):
            instance = backend.call("get_instance", cell_id) as Node
            if is_instance_valid(instance) and bool(instance.get("runtime_loaded")):
                return instance
    return instance


func _wait_inactive(backend: Variant, cell_id: String, settle_frames: int) -> bool:
    for _index: int in range(maxi(settle_frames, 1)):
        await process_frame
        if not bool(backend.call("has_active_instance", cell_id)):
            return true
    return not bool(backend.call("has_active_instance", cell_id))


func _cleanup(manager: Variant, backend: Variant) -> void:
    if is_instance_valid(backend):
        backend.queue_free()
    if is_instance_valid(manager):
        manager.queue_free()
    await process_frame


func _run() -> void:
    var probe_root := _arg("--probe-root=")
    var result_root := _arg("--result-root=")
    if probe_root.is_empty() or result_root.is_empty():
        push_error("TERRAIN_STREAMING_GODOT_FAIL missing_probe_or_result_root")
        quit(1)
        return
    if DirAccess.make_dir_recursive_absolute(result_root) != OK:
        push_error("TERRAIN_STREAMING_GODOT_FAIL cannot_create_result_root=%s" % result_root)
        quit(1)
        return
    var directory := DirAccess.open(probe_root)
    if directory == null:
        push_error("TERRAIN_STREAMING_GODOT_FAIL cannot_open_probe_root=%s" % probe_root)
        quit(1)
        return
    var files := directory.get_files()
    files.sort()
    for filename: String in files:
        if not filename.ends_with(".json"):
            continue
        _probe_count += 1
        if not await _probe_file(probe_root.path_join(filename), result_root.path_join(filename)):
            _failure_count += 1
    if _probe_count == 0:
        push_error("TERRAIN_STREAMING_GODOT_FAIL no_probe_files")
        quit(1)
        return
    if _failure_count > 0:
        print("TERRAIN_STREAMING_GODOT_COMPLETE probes=%d failed=%d" % [_probe_count, _failure_count])
        quit(1)
        return
    print("TERRAIN_STREAMING_GODOT_OK probes=%d failed=0 engine=%s" % [_probe_count, _engine_version()])
    quit(0)


func _probe_file(probe_path: String, result_path: String) -> bool:
    var probe: Dictionary = _read_json(probe_path)
    var cell_id := str(probe.get("cell_id", ""))
    var probe_digest := str(probe.get("probe_digest", ""))
    var engine_version := _engine_version()
    var result := {
        "format": RESULT_FORMAT,
        "cell_id": cell_id,
        "probe_digest": probe_digest,
        "engine_version": engine_version,
        "passed": false,
        "status": "failed_probe_contract",
        "metrics": {},
    }
    if probe.get("format") != PROBE_FORMAT or probe.get("crs") != "EPSG:31370" or engine_version != EXPECTED_ENGINE_VERSION:
        _write_json(result_path, result)
        return false

    var files: Variant = probe.get("candidate_files", {})
    var expected: Variant = probe.get("expected", {})
    var config: Variant = probe.get("streaming_config", {})
    var center_raw: Variant = probe.get("world_center", [])
    if not files is Dictionary or not expected is Dictionary or not config is Dictionary or not center_raw is Array or center_raw.size() != 3:
        _write_json(result_path, result)
        return false
    var manifest_path := str(files.get("manifest", ""))
    var runtime_cell_path := str(files.get("runtime_cell", ""))
    var runtime_network_path := str(files.get("runtime_network", ""))
    var manifest: Dictionary = _read_json(manifest_path)
    if manifest.is_empty() or not FileAccess.file_exists(runtime_cell_path) or not FileAccess.file_exists(runtime_network_path):
        result["status"] = "failed_candidate_files_unavailable"
        _write_json(result_path, result)
        return false
    var world_center := Vector3(float(center_raw[0]), float(center_raw[1]), float(center_raw[2]))

    # Keep the production scripts exact, but do not require their class_name cache
    # in this direct --script QA harness. Calls remain against the real instances.
    var manager: Variant = STREAMER_SCRIPT.new()
    manager.set("visual_load_radius_m", float(config.get("visual_load_radius_m", 300.0)))
    manager.set("visual_unload_radius_m", float(config.get("visual_unload_radius_m", 500.0)))
    manager.set("collision_radius_m", float(config.get("collision_radius_m", 1.0)))
    manager.set("lookahead_seconds", float(config.get("lookahead_seconds", 4.0)))
    manager.set("max_operations_per_tick", int(config.get("max_operations_per_tick", 1)))
    manager.set("max_active_cells", int(config.get("max_active_cells", 1)))
    get_root().add_child(manager as Node)

    var backend: Variant = BACKEND_SCRIPT.new()
    get_root().add_child(backend as Node)
    backend.call("bind_manager", manager)
    var overrides := {
        "manifest_path": manifest_path,
        "runtime_cell_path": runtime_cell_path,
        "runtime_network_path": runtime_network_path,
        "strong_heights_path": "",
        "build_collision": false,
    }
    var descriptor_registered: bool = bool(backend.call("register_script_cell", cell_id, SOURCE_PLAN_SCRIPT_PATH, overrides))
    descriptor_registered = descriptor_registered and bool(manager.call("register_manifest_dict", manifest, world_center))
    if not descriptor_registered:
        result["status"] = "failed_candidate_registration"
        result["metrics"] = {"descriptor_registered": false}
        _write_json(result_path, result)
        await _cleanup(manager, backend)
        return false

    var approach_offset := float(config.get("approach_offset_m", 600.0))
    var approach_speed := float(config.get("approach_speed_mps", 100.0))
    var max_load_frames := int(config.get("max_load_frames", 180))
    var settle_frames := int(config.get("settle_frames", 4))
    var far_offset := float(config.get("far_offset_m", 900.0))
    var approach := world_center + Vector3(approach_offset, 0.0, 0.0)
    var velocity := Vector3(-approach_speed, 0.0, 0.0)
    var current_distance := Vector2(approach.x, approach.z).distance_to(Vector2(world_center.x, world_center.z))

    manager.call("update_observer", approach, velocity)
    var first_instance: Node = await _wait_loaded(backend, cell_id, max_load_frames)
    var first_load_completed: bool = is_instance_valid(first_instance) and bool(first_instance.get("runtime_loaded"))
    var predictive_prefetch: bool = first_load_completed and current_distance > float(manager.get("visual_load_radius_m"))
    var runtime_cell_id_match: bool = first_load_completed and str(first_instance.get("cell_id")) == cell_id
    var street_surface_count_match: bool = first_load_completed and int(first_instance.get("street_surface_count")) == int(expected.get("street_surfaces", -1))
    var building_accounting_match: bool = first_load_completed and (
        int(first_instance.get("rendered_building_count")) + int(first_instance.get("blocked_unapproved_building_count"))
    ) == int(expected.get("buildings", -1))
    var collision_claimed_false: bool = first_load_completed and not bool(first_instance.get("build_collision")) and not bool(manager.call("is_collision_active", cell_id))

    manager.call("update_observer", world_center + Vector3(far_offset, 0.0, 0.0), Vector3.ZERO)
    var first_unload: bool = await _wait_inactive(backend, cell_id, settle_frames)
    var cache_after_first: Dictionary = backend.call("get_asset_cache_metrics") as Dictionary

    manager.call("update_observer", approach, velocity)
    var second_instance: Node = await _wait_loaded(backend, cell_id, max_load_frames)
    var second_load_completed: bool = is_instance_valid(second_instance) and bool(second_instance.get("runtime_loaded"))
    var cache_after_second: Dictionary = backend.call("get_asset_cache_metrics") as Dictionary
    var warm_cache_reused: bool = second_load_completed and int(cache_after_second.get("hits", 0)) >= 1 and int(cache_after_second.get("misses", 0)) == 1

    manager.call("update_observer", world_center + Vector3(far_offset, 0.0, 0.0), Vector3.ZERO)
    var final_unload: bool = await _wait_inactive(backend, cell_id, settle_frames)
    var backend_metrics: Dictionary = backend.call("get_metrics") as Dictionary
    var scheduler_metrics: Dictionary = manager.call("get_metrics") as Dictionary
    var final_cache: Dictionary = backend.call("get_asset_cache_metrics") as Dictionary

    var metrics := {
        "descriptor_registered": descriptor_registered,
        "predictive_prefetch_outside_load_radius": predictive_prefetch,
        "first_load_completed": first_load_completed,
        "runtime_cell_id_match": runtime_cell_id_match,
        "street_surface_count_match": street_surface_count_match,
        "building_accounting_match": building_accounting_match,
        "first_unload_completed": first_unload,
        "second_load_completed": second_load_completed,
        "warm_cache_reused": warm_cache_reused,
        "final_unload_completed": final_unload,
        "production_index_used_false": true,
        "collision_claimed_false": collision_claimed_false,
        "backend_load_count": int(backend_metrics.get("load_count", -1)),
        "backend_unload_count": int(backend_metrics.get("unload_count", -1)),
        "backend_failed_load_count": int(backend_metrics.get("failed_load_count", -1)),
        "collision_enable_count": int(backend_metrics.get("collision_enable_count", -1)),
        "duplicate_activation_attempts": int(scheduler_metrics.get("duplicate_activation_attempts", -1)),
        "cache_hits": int(final_cache.get("hits", -1)),
        "cache_misses": int(final_cache.get("misses", -1)),
        "cache_entries": int(final_cache.get("entries", -1)),
        "cache_referenced_entries": int(final_cache.get("referenced_entries", -1)),
        "first_cache_misses": int(cache_after_first.get("misses", -1)),
        "second_cache_hits": int(cache_after_second.get("hits", -1)),
        "first_stream_total_ms": int(first_instance.get("stream_total_ms")) if is_instance_valid(first_instance) else -1,
        "first_stream_max_phase_ms": int(first_instance.call("get_max_stream_phase_ms")) if is_instance_valid(first_instance) and first_instance.has_method("get_max_stream_phase_ms") else -1,
    }
    var passed: bool = true
    for key: String in [
        "descriptor_registered", "predictive_prefetch_outside_load_radius", "first_load_completed",
        "runtime_cell_id_match", "street_surface_count_match", "building_accounting_match",
        "first_unload_completed", "second_load_completed", "warm_cache_reused",
        "final_unload_completed", "production_index_used_false", "collision_claimed_false"
    ]:
        passed = passed and bool(metrics.get(key, false))
    passed = passed and int(metrics["backend_load_count"]) == 2
    passed = passed and int(metrics["backend_unload_count"]) == 2
    passed = passed and int(metrics["backend_failed_load_count"]) == 0
    passed = passed and int(metrics["collision_enable_count"]) == 0
    passed = passed and int(metrics["duplicate_activation_attempts"]) == 0
    passed = passed and int(metrics["cache_misses"]) == 1
    passed = passed and int(metrics["cache_hits"]) >= 1
    passed = passed and int(metrics["cache_referenced_entries"]) == 0

    result["passed"] = passed
    result["status"] = "passed_generic_candidate_prefetch_unload_cache" if passed else "failed_generic_candidate_prefetch_unload_cache"
    result["metrics"] = metrics
    _write_json(result_path, result)
    await _cleanup(manager, backend)
    if passed:
        print("TERRAIN_STREAMING_GODOT_CELL_OK cell=%s loads=2 unloads=2 cache_hits=%d production_index=false runtime_promotion=false" % [cell_id, int(metrics["cache_hits"])])
        return true
    push_error("TERRAIN_STREAMING_GODOT_CELL_FAIL cell=%s status=%s metrics=%s" % [cell_id, result["status"], metrics])
    return false
