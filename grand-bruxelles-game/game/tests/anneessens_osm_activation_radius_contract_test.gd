extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/anneessens_osm_furniture_runtime.gd")
const EXPECTED_ACTIVATION_RADIUS_M := 170.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    print("ANNEESSENS_OSM_ACTIVATION_RADIUS_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var runtime := RUNTIME_SCRIPT.new()
    if not runtime.has_method("_validated_activation_radius_m"):
        runtime.free()
        _fail("runtime has no fail-closed activation-radius validator")
        return

    runtime.activation_radius_m = EXPECTED_ACTIVATION_RADIUS_M
    var canonical: Variant = runtime.call("_validated_activation_radius_m")
    if canonical == null or abs(float(canonical) - EXPECTED_ACTIVATION_RADIUS_M) > 0.0001:
        runtime.free()
        _fail("canonical 170m activation radius rejected")
        return

    for invalid_radius: float in [0.0, -1.0, INF, -INF, NAN]:
        runtime.activation_radius_m = invalid_radius
        if runtime.call("_validated_activation_radius_m") != null:
            runtime.free()
            _fail("runtime accepted invalid activation radius %s" % str(invalid_radius))
            return

    runtime.activation_radius_m = EXPECTED_ACTIVATION_RADIUS_M + 0.25
    if runtime.call("_validated_activation_radius_m") != null:
        runtime.free()
        _fail("runtime accepted drift from frozen 170m activation radius")
        return

    runtime.free()
    print("ANNEESSENS_OSM_ACTIVATION_RADIUS_OK: canonical_radius_m=170.0 zero_fail_closed=true negative_fail_closed=true non_finite_fail_closed=true drift_fail_closed=true")
    quit(0)
