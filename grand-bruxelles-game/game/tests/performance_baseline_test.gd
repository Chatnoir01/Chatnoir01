extends SceneTree

const WARMUP_FRAMES := 60
const SAMPLE_FRAMES := 180


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("PERFORMANCE_BASELINE_FAIL: %s" % message)
    quit(1)


func _percentile(sorted_values: Array[float], percentile: float) -> float:
    if sorted_values.is_empty():
        return 0.0
    var index := int(ceil((sorted_values.size() - 1) * percentile))
    index = clampi(index, 0, sorted_values.size() - 1)
    return sorted_values[index]


func _run() -> void:
    var packed: PackedScene = load("res://game/main.tscn")
    if packed == null:
        _fail("main scene did not load")
        return

    var scene: Node = packed.instantiate()
    root.add_child(scene)

    for _i in range(WARMUP_FRAMES):
        await process_frame

    var fps_monitor_sum := 0.0
    var process_monitor_sum_ms := 0.0
    var physics_monitor_sum_ms := 0.0
    var draw_calls_max := 0
    var objects_max := 0
    var primitives_max := 0
    var static_memory_max := 0.0
    var wall_frame_times_ms: Array[float] = []
    var previous_tick_usec := Time.get_ticks_usec()

    for _i in range(SAMPLE_FRAMES):
        await process_frame
        var now_tick_usec := Time.get_ticks_usec()
        wall_frame_times_ms.append(float(now_tick_usec - previous_tick_usec) / 1000.0)
        previous_tick_usec = now_tick_usec

        fps_monitor_sum += float(Performance.get_monitor(Performance.TIME_FPS))
        process_monitor_sum_ms += float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
        physics_monitor_sum_ms += float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
        draw_calls_max = maxi(draw_calls_max, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
        objects_max = maxi(objects_max, int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
        primitives_max = maxi(primitives_max, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
        static_memory_max = maxf(static_memory_max, float(Performance.get_monitor(Performance.MEMORY_STATIC)))

    var wall_sum_ms := 0.0
    for frame_ms in wall_frame_times_ms:
        wall_sum_ms += frame_ms
    var wall_frame_ms_avg := wall_sum_ms / float(SAMPLE_FRAMES)
    var sorted_wall_times := wall_frame_times_ms.duplicate()
    sorted_wall_times.sort()
    var wall_frame_ms_p95 := _percentile(sorted_wall_times, 0.95)
    var wall_fps_estimate := 1000.0 / wall_frame_ms_avg if wall_frame_ms_avg > 0.0 else 0.0
    var render_metrics_available := draw_calls_max > 0 or objects_max > 0 or primitives_max > 0

    var metrics := {
        "warmup_frames": WARMUP_FRAMES,
        "sample_frames": SAMPLE_FRAMES,
        "wall_frame_ms_avg": wall_frame_ms_avg,
        "wall_frame_ms_p95": wall_frame_ms_p95,
        "wall_fps_estimate": wall_fps_estimate,
        "fps_monitor_avg": fps_monitor_sum / float(SAMPLE_FRAMES),
        "process_monitor_ms_avg": process_monitor_sum_ms / float(SAMPLE_FRAMES),
        "physics_monitor_ms_avg": physics_monitor_sum_ms / float(SAMPLE_FRAMES),
        "render_metrics_available": render_metrics_available,
        "draw_calls_max": draw_calls_max,
        "objects_in_frame_max": objects_max,
        "primitives_in_frame_max": primitives_max,
        "static_memory_mib_max": static_memory_max / (1024.0 * 1024.0)
    }

    print("PERFORMANCE_BASELINE_JSON: %s" % JSON.stringify(metrics))
    print("PERFORMANCE_BASELINE_OK")
    scene.queue_free()
    await process_frame
    quit(0)
