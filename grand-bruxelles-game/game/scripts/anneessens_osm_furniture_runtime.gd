extends "res://game/scripts/anneessens_osm_furniture_runtime_base.gd"

# Exact selected placement subset from the pinned OSM upstream snapshot
# EXPECTED_UPSTREAM_SHA256. These coordinates are provenance identity, not
# authored visual tuning: changing them requires a new source intake/digest.
const SOURCE_POSITION_EPSILON_M := 0.0001
const EXPECTED_SOURCE_POSITIONS := {
    4672009403: Vector2(-186.799, -120.437),
    4672009414: Vector2(-165.05, -147.654),
    4672009415: Vector2(-169.929, -141.509),
    4672009416: Vector2(-175.018, -135.231),
    4672009417: Vector2(-179.918, -128.83),
    11929097332: Vector2(-313.793, -143.858),
    11929097333: Vector2(-306.074, -147.576),
}

var _source_position_identity_receipt: Dictionary = {}

func _validate_source_position_identity(tree_points: Array) -> Variant:
    if tree_points.size() != EXPECTED_SOURCE_POSITIONS.size():
        push_error("Anneessens OSM furniture source-position point count drifted")
        return null
    var seen: Dictionary = {}
    var max_position_error_m := 0.0
    for tree_point: Variant in tree_points:
        if not tree_point is Dictionary:
            push_error("Anneessens OSM furniture source-position point invalid")
            return null
        var point := tree_point as Dictionary
        var osm_id_value: Variant = point.get("osm_id", null)
        var position_value: Variant = point.get("position", null)
        if typeof(osm_id_value) != TYPE_INT or not position_value is Vector3:
            push_error("Anneessens OSM furniture source-position identity shape invalid")
            return null
        var osm_id := int(osm_id_value)
        if seen.has(osm_id) or not EXPECTED_SOURCE_POSITIONS.has(osm_id):
            push_error("Anneessens OSM furniture source-position identity id invalid")
            return null
        var position := position_value as Vector3
        if not is_finite(position.x) or not is_finite(position.z):
            push_error("Anneessens OSM furniture source-position coordinate non-finite")
            return null
        var expected := EXPECTED_SOURCE_POSITIONS[osm_id] as Vector2
        var position_error_m := Vector2(position.x - expected.x, position.z - expected.y).length()
        if not is_finite(position_error_m) or position_error_m > SOURCE_POSITION_EPSILON_M:
            push_error("Anneessens OSM furniture selected OSM position drifted from pinned upstream")
            return null
        seen[osm_id] = true
        max_position_error_m = max(max_position_error_m, position_error_m)
    if seen.size() != EXPECTED_SOURCE_POSITIONS.size():
        push_error("Anneessens OSM furniture source-position identity incomplete")
        return null
    return {
        "source_position_identity_validated": true,
        "max_position_error_m": max_position_error_m,
        "source_position_epsilon_m": SOURCE_POSITION_EPSILON_M,
        "upstream_source_sha256": EXPECTED_UPSTREAM_SHA256,
    }

func _build_once() -> void:
    if _tearing_down or not is_instance_valid(_scene) or is_instance_valid(_root):
        return
    if not FileAccess.file_exists(DATA_PATH):
        push_warning("Anneessens OSM furniture data missing")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
    if not parsed is Dictionary:
        push_error("Anneessens OSM furniture JSON invalid")
        return
    var data := parsed as Dictionary
    var validated_tree_points: Variant = _collect_validated_tree_points(data)
    if validated_tree_points == null:
        return
    var source_identity_value: Variant = _validate_source_position_identity(validated_tree_points as Array)
    if source_identity_value == null:
        return
    _source_position_identity_receipt = source_identity_value as Dictionary

    # Preserve the already validated source placement, geometry, materials,
    # collision policy, ownership and lifecycle implementation byte-for-byte.
    # The provenance identity gate above is deliberately the only precondition
    # added before the legacy implementation is allowed to create its root.
    super._build_once()
    if not is_instance_valid(_root):
        return
    _root.set_meta("source_position_identity_validated", true)
    _root.set_meta("source_position_max_error_m", float(_source_position_identity_receipt["max_position_error_m"]))
    _root.set_meta("source_position_epsilon_m", SOURCE_POSITION_EPSILON_M)
    print("ANNEESSENS_OSM_SOURCE_POSITION_IDENTITY_OK: trees=%d max_error_m=%.6f epsilon_m=%.6f upstream_sha256=%s" % [validated_tree_points.size(), float(_source_position_identity_receipt["max_position_error_m"]), SOURCE_POSITION_EPSILON_M, EXPECTED_UPSTREAM_SHA256])
