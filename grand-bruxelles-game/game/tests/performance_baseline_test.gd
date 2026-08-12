extends SceneTree

const WARMUP_FRAMES := 60
const SAMPLE_FRAMES := 180


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("PERFORMANCE_BASELINE_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var packed: PackedScene = load("res://game/main.tscn")
    if packed == null:
        _fail("main scene did not load")
        return

    var scene: Node = packed.instantiate()
    root.add_child(scene)

    for _i in range(WARMUP_FRAMES):
        await process_frame

    var fps_sum := 0.0
    var process_sum_ms := 0.0
    var physics_sum_ms := 0.0
    var draw_calls_max := 0
    var objects_max := 0
    var primitives_max := 0
    var static_memory_max := 0.0

    for _i in range(SAMPLE_FRAMES):
        await process_frame
        fps_sum += float(Performance.get_monitor(Performance.TIME_FPS))
        process_sum_ms += float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
        physics_sum_ms += float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
        draw_calls_max = maxi(draw_calls_max, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
        objects_max = maxi(objects_max, int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
        primitives_max = maxi(primitives_max, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
        static_memory_max = maxf(static_memory_max, float(Performance.get_monitor(Performance.MEMORY_STATIC)))

    var metrics := {
        "warmup_frames": WARMUP_FRAMES,
        "sample_frames": SAMPLE_FRAMES,
        "fps_avg": fps_sum / float(SAMPLE_FRAMES),
        "process_ms_avg": process_sum_ms / float(SAMPLE_FRAMES),
        "physics_ms_avg": physics_sum_ms / float(SAMPLE_FRAMES),
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
