extends SceneTree

const STREAMER_SCRIPT := preload("res://game/scripts/brussels_cell_streaming_manager.gd")
const BACKEND_SCRIPT := preload("res://game/scripts/brussels_cell_node_backend.gd")
const SOURCE_PLAN_SCRIPT_PATH := "res://game/scripts/brussels_source_plan_streamed_cell.gd"
const PROBE_FORMAT := "grand-bruxelles-terrain-performance-godot-probe-v1"
const RESULT_FORMAT := "grand-bruxelles-terrain-performance-godot-result-v1"
const EXPECTED_ENGINE_VERSION := "4.7.1"
const EXPECTED_RENDERER := "gl_compatibility"


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
        push_error("TERRAIN_PERFORMANCE_GODOT_FAIL cannot_write_result=%s" % path)
        return false
    file.store_string(JSON.stringify(payload, "\t", true) + "\n")
    file.close()
    return true


func _percentile(values: Array[float], percentile: float) -> float:
    if values.is_empty():
        return 0.0
    var sorted_values := values.duplicate()
    sorted_values.sort()
    var index := clampi(int(ceil((sorted_values.size() - 1) * percentile)), 0, sorted_values.size() - 1)
    return sorted_values[index]


func _wait_loaded(backend: Variant, cell_id: String, max_frames: int) -> Node:
    for _index: int in range(max_frames):
        await process_frame
        if bool(backend.call("has_active_instance", cell_id)):
            var instance := backend.call("get_instance", cell_id) as Node
            if is_instance_valid(instance) and bool(instance.get("runtime_loaded")):
                return instance
    return null


func _cleanup(manager: Variant, backend: Variant, camera: Camera3D) -> void:
    if is_instance_valid(camera):
        camera.queue_free()
    if is_instance_valid(backend):
        backend.queue_free()
    if is_instance_valid(manager):
        manager.queue_free()
    await process_frame


func _run() -> void:
    var probe_path := _arg("--probe=")
    var result_path := _arg("--result=")
    if probe_path.is_empty() or result_path.is_empty():
        push_error("TERRAIN_PERFORMANCE_GODOT_FAIL missing_probe_or_result")
        quit(1)
        return
    var probe := _read_json(probe_path)
    var cell_id := str(probe.get("cell_id", ""))
    var engine_version := _engine_version()
    var result := {
        "format": RESULT_FORMAT,
        "cell_id": cell_id,
        "probe_digest": str(probe.get("probe_digest", "")),
        "engine_version": engine_version,
        "renderer": EXPECTED_RENDERER,
        "measurement_complete": false,
        "metrics": {},
    }
    if probe.get("format") != PROBE_FORMAT or probe.get("crs") != "EPSG:31370" or engine_version != EXPECTED_ENGINE_VERSION:
        _write_json(result_path, result)
        quit(1)
        return

    var files: Dictionary = probe.get("candidate_files", {}) as Dictionary
    var center_raw: Array = probe.get("world_center", []) as Array
    var config: Dictionary = probe.get("measurement_config", {}) as Dictionary
    if files.is_empty() or center_raw.size() != 3 or config.is_empty():
        _write_json(result_path, result)
        quit(1)
        return
    var manifest_path := str(files.get("manifest", ""))
    var runtime_cell_path := str(files.get("runtime_cell", ""))
    var runtime_network_path := str(files.get("runtime_network", ""))
    var manifest := _read_json(manifest_path)
    if manifest.is_empty() or not FileAccess.file_exists(runtime_cell_path) or not FileAccess.file_exists(runtime_network_path):
        _write_json(result_path, result)
        quit(1)
        return

    root.size = Vector2i(int(config.get("viewport_width", 1280)), int(config.get("viewport_height", 720)))
    var world_center := Vector3(float(center_raw[0]), float(center_raw[1]), float(center_raw[2]))
    var manager: Variant = STREAMER_SCRIPT.new()
    manager.set("visual_load_radius_m", 300.0)
    manager.set("visual_unload_radius_m", 500.0)
    manager.set("collision_radius_m", 1.0)
    manager.set("max_operations_per_tick", 1)
    manager.set("max_active_cells", 1)
    root.add_child(manager as Node)

    var backend: Variant = BACKEND_SCRIPT.new()
    root.add_child(backend as Node)
    backend.call("bind_manager", manager)
    var overrides := {
        "manifest_path": manifest_path,
        "runtime_cell_path": runtime_cell_path,
        "runtime_network_path": runtime_network_path,
        "strong_heights_path": "",
        "build_collision": false,
    }
    var registered := bool(backend.call("register_script_cell", cell_id, SOURCE_PLAN_SCRIPT_PATH, overrides))
    registered = registered and bool(manager.call("register_manifest_dict", manifest, world_center))
    if not registered:
        _write_json(result_path, result)
        await _cleanup(manager, backend, null)
        quit(1)
        return

    manager.call("update_observer", world_center, Vector3.ZERO)
    var instance := await _wait_loaded(backend, cell_id, int(config.get("max_load_frames", 180)))
    if not is_instance_valid(instance):
        _write_json(result_path, result)
        await _cleanup(manager, backend, null)
        quit(1)
        return

    var camera := Camera3D.new()
    root.add_child(camera)
    camera.position = world_center + Vector3(0.0, 120.0, 160.0)
    camera.look_at(world_center, Vector3.UP)
    camera.current = true

    var warmup_frames := int(config.get("warmup_frames", 60))
    var sample_frames := int(config.get("sample_frames", 180))
    for _i: int in range(warmup_frames):
        await process_frame

    var frame_times: Array[float] = []
    var draw_calls_max := 0
    var objects_max := 0
    var primitives_max := 0
    var memory_max := 0.0
    var previous_tick := Time.get_ticks_usec()
    for _i: int in range(sample_frames):
        await process_frame
        var now := Time.get_ticks_usec()
        frame_times.append(float(now - previous_tick) / 1000.0)
        previous_tick = now
        draw_calls_max = maxi(draw_calls_max, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
        objects_max = maxi(objects_max, int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
        primitives_max = maxi(primitives_max, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
        memory_max = maxf(memory_max, float(Performance.get_monitor(Performance.MEMORY_STATIC)))

    var frame_sum := 0.0
    for frame_ms: float in frame_times:
        frame_sum += frame_ms
    var metrics := {
        "warmup_frames": warmup_frames,
        "sample_frames": sample_frames,
        "wall_frame_ms_avg": frame_sum / float(maxi(sample_frames, 1)),
        "wall_frame_ms_p95": _percentile(frame_times, 0.95),
        "draw_calls_max": draw_calls_max,
        "objects_in_frame_max": objects_max,
        "primitives_in_frame_max": primitives_max,
        "static_memory_mib_max": memory_max / (1024.0 * 1024.0),
        "stream_total_ms": int(instance.get("stream_total_ms")),
        "stream_max_phase_ms": int(instance.call("get_max_stream_phase_ms")) if instance.has_method("get_max_stream_phase_ms") else 0,
        "render_metrics_available": draw_calls_max > 0 or objects_max > 0 or primitives_max > 0,
        "collision_claimed_false": not bool(instance.get("build_collision")) and not bool(manager.call("is_collision_active", cell_id)),
    }
    result["measurement_complete"] = true
    result["metrics"] = metrics
    _write_json(result_path, result)
    print("TERRAIN_PERFORMANCE_GODOT_OK cell=%s avg_ms=%.3f p95_ms=%.3f draws=%d render_metrics=%s runtime_promotion=false" % [cell_id, metrics["wall_frame_ms_avg"], metrics["wall_frame_ms_p95"], draw_calls_max, str(metrics["render_metrics_available"]).to_lower()])
    await _cleanup(manager, backend, camera)
    quit(0)
