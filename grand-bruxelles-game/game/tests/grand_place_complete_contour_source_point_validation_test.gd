extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/grand_place_complete_contour_runtime.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_SOURCE_POINT_VALIDATION_FAIL: %s" % message)
    quit(1)

func _expect_valid(runtime: Node, raw: Variant, expected: Vector3, label: String) -> bool:
    var parsed: Vector3 = runtime.call("_point", raw)
    if not parsed.is_finite() or not parsed.is_equal_approx(expected):
        _fail("valid numeric point rejected or changed: %s -> %s" % [label, parsed])
        return false
    return true

func _expect_rejected(runtime: Node, raw: Variant, label: String) -> bool:
    var parsed: Vector3 = runtime.call("_point", raw)
    if parsed.is_finite():
        _fail("non-canonical source point was coerced instead of rejected: %s -> %s" % [label, parsed])
        return false
    return true

func _run() -> void:
    var runtime: Node = RUNTIME_SCRIPT.new()

    if not _expect_valid(runtime, [281.3858, 0.0, -472.4659], Vector3(281.3858, 0.0, -472.4659), "float triplet"):
        return
    if not _expect_valid(runtime, [281, 0, -472], Vector3(281.0, 0.0, -472.0), "integer triplet"):
        return

    if not _expect_rejected(runtime, ["281.3858", 0.0, -472.4659], "numeric string"):
        return
    if not _expect_rejected(runtime, [true, 0.0, -472.4659], "boolean"):
        return
    if not _expect_rejected(runtime, [NAN, 0.0, -472.4659], "NaN"):
        return
    if not _expect_rejected(runtime, [INF, 0.0, -472.4659], "+INF"):
        return
    if not _expect_rejected(runtime, [281.3858, -INF, -472.4659], "-INF"):
        return
    if not _expect_rejected(runtime, [281.3858, 0.0], "short point"):
        return
    if not _expect_rejected(runtime, {"x": 281.3858, "y": 0.0, "z": -472.4659}, "dictionary"):
        return

    print("GRAND_PLACE_SOURCE_POINT_VALIDATION_OK: strict int/float finite coordinates only")
    quit(0)
