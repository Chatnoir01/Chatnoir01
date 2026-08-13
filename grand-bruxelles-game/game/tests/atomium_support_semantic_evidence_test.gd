extends SceneTree

const PATH := "res://data/sources/laeken_jette/atomium_support_semantic_evidence.json"

func _initialize() -> void:
    var f := FileAccess.open(PATH, FileAccess.READ)
    if f == null:
        push_error("ATOMIUM_SUPPORT_EVIDENCE_FAIL: missing evidence")
        quit(1)
        return
    var data = JSON.parse_string(f.get_as_text())
    if typeof(data) != TYPE_DICTIONARY:
        push_error("ATOMIUM_SUPPORT_EVIDENCE_FAIL: invalid json")
        quit(1)
        return
    var supports: Dictionary = data.get("support_constraints", {})
    var pavilion: Dictionary = data.get("base_pavilion_constraints", {})
    var gate: Dictionary = data.get("integration_gate", {})
    if data.get("crs", "") != "EPSG:31370":
        push_error("ATOMIUM_SUPPORT_EVIDENCE_FAIL: crs")
        quit(1)
        return
    if int(supports.get("count", 0)) != 3 or supports.get("form", "") != "inverted_v_bipod":
        push_error("ATOMIUM_SUPPORT_EVIDENCE_FAIL: supports")
        quit(1)
        return
    if absf(float(supports.get("approximate_height_m", 0.0)) - 30.0) > 0.001:
        push_error("ATOMIUM_SUPPORT_EVIDENCE_FAIL: support height")
        quit(1)
        return
    if bool(supports.get("exact_foot_positions_resolved", true)) or bool(supports.get("runtime_geometry_allowed", true)):
        push_error("ATOMIUM_SUPPORT_EVIDENCE_FAIL: support status")
        quit(1)
        return
    if pavilion.get("plan", "") != "circle" or absf(float(pavilion.get("diameter_m", 0.0)) - 26.0) > 0.001:
        push_error("ATOMIUM_SUPPORT_EVIDENCE_FAIL: pavilion plan")
        quit(1)
        return
    if pavilion.get("north_access", "") != "at_grade" or pavilion.get("south_access", "") != "two_parallel_stairs":
        push_error("ATOMIUM_SUPPORT_EVIDENCE_FAIL: pavilion access")
        quit(1)
        return
    if bool(gate.get("runtime_approved", true)) or bool(gate.get("realism_complete", true)):
        push_error("ATOMIUM_SUPPORT_EVIDENCE_FAIL: approval status")
        quit(1)
        return
    if not bool(gate.get("requires_orthophoto_or_survey_for_pose", false)):
        push_error("ATOMIUM_SUPPORT_EVIDENCE_FAIL: source gate")
        quit(1)
        return
    print("ATOMIUM_SUPPORT_EVIDENCE_OK: supports=3 approx_height_m=30 pavilion_diameter_m=26")
    quit(0)
