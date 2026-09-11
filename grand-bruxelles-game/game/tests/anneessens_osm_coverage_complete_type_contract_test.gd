extends SceneTree

const DATA_PATH := "res://data/osm/zones/anneessens/environment.game.json"
const RUNTIME_SCRIPT := preload("res://game/scripts/anneessens_osm_furniture_runtime.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    print("ANNEESSENS_OSM_COVERAGE_COMPLETE_TYPE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    if not FileAccess.file_exists(DATA_PATH):
        _fail("canonical Anneessens environment artifact missing")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
    if not parsed is Dictionary:
        _fail("canonical Anneessens environment artifact invalid")
        return

    var runtime := RUNTIME_SCRIPT.new()
    var canonical := (parsed as Dictionary).duplicate(true)
    var canonical_contract: Variant = runtime.call("_validate_coverage_contract", canonical)
    if canonical_contract == null:
        runtime.free()
        _fail("runtime rejected canonical boolean coverage_complete=false")
        return

    var selection_value: Variant = canonical.get("selection", null)
    if not selection_value is Dictionary:
        runtime.free()
        _fail("canonical selection contract missing")
        return
    var canonical_selection := selection_value as Dictionary
    if typeof(canonical_selection.get("coverage_complete", null)) != TYPE_BOOL or bool(canonical_selection.get("coverage_complete", true)):
        runtime.free()
        _fail("canonical coverage_complete fixture is not boolean false")
        return

    # JSON number 0 is falsey when coerced with bool(...), but it is not the
    # provenance boolean asserted by the zone schema. Preserve every other
    # field and prove the runtime rejects this semantic type drift.
    var numeric_false := canonical.duplicate(true)
    var numeric_selection := (numeric_false.get("selection", {}) as Dictionary).duplicate(true)
    numeric_selection["coverage_complete"] = 0
    numeric_false["selection"] = numeric_selection
    var numeric_contract: Variant = runtime.call("_validate_coverage_contract", numeric_false)

    runtime.free()
    if numeric_contract != null:
        _fail("runtime accepted numeric coverage_complete=0 as boolean false")
        return

    print("ANNEESSENS_OSM_COVERAGE_COMPLETE_TYPE_OK: canonical_boolean_false=true numeric_zero_fail_closed=true")
    quit(0)
