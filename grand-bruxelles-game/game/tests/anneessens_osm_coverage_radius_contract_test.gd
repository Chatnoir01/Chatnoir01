extends SceneTree

const DATA_PATH := "res://data/osm/zones/anneessens/environment.game.json"
const RUNTIME_SCRIPT := preload("res://game/scripts/anneessens_osm_furniture_runtime.gd")
const EXPECTED_COVERAGE_RADIUS_M := 130.0
const EXPECTED_ANCHOR := Vector2(-272.04, -217.07)

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
    var anchor := selection.get("anchor", []) as Array
    if anchor.size() != 2 or Vector2(float(anchor[0]), float(anchor[1])).distance_to(EXPECTED_ANCHOR) > 0.0001:
        _fail("canonical source subset anchor drifted")
        return

    var runtime := RUNTIME_SCRIPT.new()
    var canonical: Variant = runtime.call("_validate_coverage_contract", data)
    if canonical == null:
        runtime.free()
        _fail("canonical 130m coverage contract rejected")
        return

    var canonical_points: Variant = runtime.call("_collect_validated_tree_points", data)
    if canonical_points == null:
        runtime.free()
        _fail("canonical source-backed tree points rejected")
        return
    var canonical_membership: Variant = runtime.call("_validate_selection_radius_membership", canonical_points as Array)
    if canonical_membership == null:
        runtime.free()
        _fail("canonical tree points were not proven inside the 130m source subset")
        return
    var max_distance_m := float((canonical_membership as Dictionary).get("max_distance_m", -1.0))
    if max_distance_m <= 0.0 or max_distance_m > EXPECTED_COVERAGE_RADIUS_M:
        runtime.free()
        _fail("canonical radius-membership receipt invalid")
        return

    var drifted := data.duplicate(true)
    var drifted_selection := drifted.get("selection", {}) as Dictionary
    drifted_selection["radius_m"] = EXPECTED_COVERAGE_RADIUS_M + 1.0
    drifted["selection"] = drifted_selection
    var drifted_result: Variant = runtime.call("_validate_coverage_contract", drifted)
    if drifted_result != null:
        runtime.free()
        _fail("runtime accepted source-subset radius drift from 130m to 131m")
        return

    var escaped := data.duplicate(true)
    var escaped_points := escaped.get("environment_points", []) as Array
    var escaped_point := (escaped_points[0] as Dictionary).duplicate(true)
    escaped_point["position"] = [EXPECTED_ANCHOR.x + EXPECTED_COVERAGE_RADIUS_M + 0.25, EXPECTED_ANCHOR.y]
    escaped_points[0] = escaped_point
    escaped["environment_points"] = escaped_points
    var escaped_validated: Variant = runtime.call("_collect_validated_tree_points", escaped)
    if escaped_validated == null:
        runtime.free()
        _fail("synthetic escaped point did not reach radius-membership gate")
        return
    var escaped_membership: Variant = runtime.call("_validate_selection_radius_membership", escaped_validated as Array)
    runtime.free()
    if escaped_membership != null:
        _fail("runtime accepted an OSM tree 0.25m outside the declared 130m source subset")
        return

    print("ANNEESSENS_OSM_COVERAGE_RADIUS_OK: canonical_radius_m=130.0 max_distance_m=%.6f radius_drift_fail_closed=true membership_fail_closed=true" % max_distance_m)
    quit(0)
