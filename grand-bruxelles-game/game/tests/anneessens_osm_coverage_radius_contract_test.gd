extends SceneTree

const DATA_PATH := "res://data/osm/zones/anneessens/environment.game.json"
const RUNTIME_SCRIPT := preload("res://game/scripts/anneessens_osm_furniture_runtime.gd")
const EXPECTED_COVERAGE_RADIUS_M := 130.0
const EXPECTED_ANCHOR := Vector2(-272.04, -217.07)
const EXPECTED_UPSTREAM_ORIGIN := Vector2(50.8419, 4.348)
const SOURCE_POSITION_DRIFT_M := 0.25
const UPSTREAM_ORIGIN_DRIFT_DEGREES := 0.0001

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
    var upstream := data.get("upstream", {}) as Dictionary
    var upstream_origin := upstream.get("origin", {}) as Dictionary
    if abs(float(upstream_origin.get("lat", -999.0)) - EXPECTED_UPSTREAM_ORIGIN.x) > 0.0000001 or abs(float(upstream_origin.get("lon", -999.0)) - EXPECTED_UPSTREAM_ORIGIN.y) > 0.0000001:
        _fail("canonical upstream origin drifted")
        return

    var runtime := RUNTIME_SCRIPT.new()
    var canonical: Variant = runtime.call("_validate_coverage_contract", data)
    if canonical == null:
        runtime.free()
        _fail("canonical 130m coverage contract rejected")
        return

    # Upstream-origin provenance regression: path/format/SHA remain pinned, but
    # the derived artifact's declared origin is moved while all selected game
    # positions stay untouched. Legacy coverage validation accepts this drift,
    # allowing an internally contradictory provenance receipt to mount.
    var origin_drifted := data.duplicate(true)
    var drifted_upstream := (origin_drifted.get("upstream", {}) as Dictionary).duplicate(true)
    var drifted_origin := (drifted_upstream.get("origin", {}) as Dictionary).duplicate(true)
    drifted_origin["lat"] = EXPECTED_UPSTREAM_ORIGIN.x + UPSTREAM_ORIGIN_DRIFT_DEGREES
    drifted_upstream["origin"] = drifted_origin
    origin_drifted["upstream"] = drifted_upstream
    var origin_drift_result: Variant = runtime.call("_validate_coverage_contract", origin_drifted)
    if origin_drift_result != null:
        runtime.free()
        _fail("runtime accepted upstream origin drift while retaining pinned source path/format/SHA")
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
    if escaped_membership != null:
        runtime.free()
        _fail("runtime accepted an OSM tree 0.25m outside the declared 130m source subset")
        return

    # Source-position identity regression: retain the selected OSM ID and every
    # existing coverage/selection contract, but move one point 25 cm while it
    # remains inside the 130 m subset. The legacy validation chain accepts this
    # mutation; the new provenance gate must reject it before root creation.
    var source_drifted := data.duplicate(true)
    var source_drifted_points := source_drifted.get("environment_points", []) as Array
    var source_drifted_point := (source_drifted_points[0] as Dictionary).duplicate(true)
    var source_position := source_drifted_point.get("position", []) as Array
    source_drifted_point["position"] = [float(source_position[0]) + SOURCE_POSITION_DRIFT_M, float(source_position[1])]
    source_drifted_points[0] = source_drifted_point
    source_drifted["environment_points"] = source_drifted_points
    var source_drifted_validated: Variant = runtime.call("_collect_validated_tree_points", source_drifted)
    if source_drifted_validated == null:
        runtime.free()
        _fail("synthetic source-position drift did not reach provenance identity gate")
        return
    if runtime.call("_validate_selection_radius_membership", source_drifted_validated as Array) == null:
        runtime.free()
        _fail("synthetic 0.25m source-position drift unexpectedly escaped the 130m subset")
        return
    if runtime.call("_validate_selection_integrity", source_drifted, source_drifted_validated as Array) == null:
        runtime.free()
        _fail("synthetic source-position drift unexpectedly broke selection identity")
        return
    if not runtime.has_method("_validate_source_position_identity"):
        runtime.free()
        _fail("runtime has no fail-closed OSM source-position identity gate")
        return
    var canonical_source_identity: Variant = runtime.call("_validate_source_position_identity", canonical_points as Array)
    if canonical_source_identity == null:
        runtime.free()
        _fail("canonical selected OSM positions rejected by source-position identity gate")
        return
    var source_drift_result: Variant = runtime.call("_validate_source_position_identity", source_drifted_validated as Array)
    runtime.free()
    if source_drift_result != null:
        _fail("runtime accepted 0.25m placement drift for an existing selected OSM ID")
        return

    var source_identity := canonical_source_identity as Dictionary
    if not bool(source_identity.get("source_position_identity_validated", false)):
        _fail("canonical source-position identity receipt missing")
        return
    if float(source_identity.get("max_position_error_m", -1.0)) < 0.0:
        _fail("canonical source-position identity error receipt invalid")
        return

    print("ANNEESSENS_OSM_COVERAGE_RADIUS_OK: canonical_radius_m=130.0 max_distance_m=%.6f radius_drift_fail_closed=true membership_fail_closed=true source_position_drift_fail_closed=true upstream_origin_drift_fail_closed=true" % max_distance_m)
    quit(0)
