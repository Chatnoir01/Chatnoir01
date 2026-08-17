extends SceneTree

const MATERIAL_PATH := "res://game/scripts/brussels_generic_window_surface_material.gd"
const RUNTIME_PATH := "res://game/scripts/brussels_generic_window_surface_runtime.gd"
const MATERIAL_FAMILY := "brussels_generic_window_surface_v1"
const MIN_WINDOWS := 120

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_GENERIC_WINDOW_SURFACE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    if not FileAccess.file_exists(MATERIAL_PATH):
        _fail("reusable generic window surface material missing")
        return
    if not FileAccess.file_exists(RUNTIME_PATH):
        _fail("reusable generic window surface runtime missing")
        return

    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("production main scene missing")
        return
    var scene := packed.instantiate() as Node3D
    root.add_child(scene)

    var runtime := root.get_node_or_null("BrusselsGenericWindowSurfaceRuntime")
    if runtime == null:
        _fail("generic window surface autoload missing")
        return

    for _frame: int in range(240):
        await process_frame
        if runtime.ready_complete():
            break
    if not runtime.ready_complete():
        _fail("runtime did not finish")
        return
    if runtime.failed():
        _fail("runtime reported failure")
        return
    if runtime.applied_window_count() < MIN_WINDOWS:
        _fail("too few existing generic windows received shared surface")
        return
    if runtime.material_family() != MATERIAL_FAMILY:
        _fail("unexpected material family")
        return
    if not runtime.geometry_unchanged():
        _fail("window surface runtime changed existing transforms or instance count")
        return
    if runtime.opening_geometry_claimed():
        _fail("runtime falsely claims authored window openings as source geometry")
        return

    print("BRUSSELS_GENERIC_WINDOW_SURFACE_OK: windows=%d family=%s geometry_unchanged=true opening_geometry_claimed=false" % [runtime.applied_window_count(), runtime.material_family()])
    quit(0)
