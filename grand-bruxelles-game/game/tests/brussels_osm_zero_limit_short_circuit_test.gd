extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_osm_environment_runtime.gd")

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_ZERO_LIMIT_SHORT_CIRCUIT_FAIL: %s" % message)
    quit(1)

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var runtime := RUNTIME_SCRIPT.new() as Node3D
    # Zero is a valid instance limit and semantically disables that presentation
    # family. A disabled family must not inspect or sort its source rows at all.
    # This poisoned internal row is unreachable under that contract and makes any
    # accidental traversal fail loudly instead of hiding unnecessary work.
    runtime.set("_points", {
        "tree": [42],
        "street_lamp": [],
        "bollard": [],
    })
    var rows: Array = runtime.call("_nearby", "tree", Vector3.ZERO, 0) as Array
    if not rows.is_empty():
        _fail("zero-limit selection returned rows")
        return
    print("BRUSSELS_OSM_ZERO_LIMIT_SHORT_CIRCUIT_OK: limit_zero_reads_source=false result_count=0")
    quit(0)
