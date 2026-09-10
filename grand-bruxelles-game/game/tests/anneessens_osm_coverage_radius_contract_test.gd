extends SceneTree

const DATA_PATH := "res://data/osm/zones/anneessens/environment.game.json"
const RUNTIME_SCRIPT := preload("res://game/scripts/anneessens_osm_furniture_runtime.gd")
const EXPECTED_COVERAGE_RADIUS_M := 130.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    print("ANNEESSENS_OSM_COVERAGE_RADIUS_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    if not FileAccess.file_exists(DATA_PATH):
        _fail("canonical Anneessens environment artifact missing")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
    if not parsed is Dictionary:
        _fail("canonical Anneessens environment artifact invalid")
        return
    var data := (parsed as Dictionary).duplicate(true)
    var selection := data.get("selection", {}) as Dictionary
    if abs(float(selection.get("radius_m", -1.0)) - EXPECTED_COVERAGE_RADIUS_M) > 0.0001:
        _fail("canonical source subset radius is not 130m")
        return

    var runtime := RUNTIME_SCRIPT.new()
    var canonical: Variant = runtime.call("_validate_coverage_contract", data)
    if canonical == null:
        runtime.free()
        _fail("canonical 130m coverage contract rejected")
        return

    var drifted := data.duplicate(true)
    var drifted_selection := drifted.get("selection", {}) as Dictionary
    drifted_selection["radius_m"] = EXPECTED_COVERAGE_RADIUS_M + 1.0
    drifted["selection"] = drifted_selection
    var drifted_result: Variant = runtime.call("_validate_coverage_contract", drifted)
    runtime.free()
    if drifted_result != null:
        _fail("runtime accepted source-subset radius drift from 130m to 131m")
        return

    print("ANNEESSENS_OSM_COVERAGE_RADIUS_OK: canonical_radius_m=130.0 radius_drift_fail_closed=true")
    quit(0)
