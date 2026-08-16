extends SceneTree

const EVIDENCE_PATH := "res://data/qa/bourse_parvis_proportions_evidence.json"
const CAMERA_PATH := "res://data/qa/photo_match/bourse_2019_geotagged_camera_evidence.json"
const SURFACE_PATH := "res://data/urbis/bourse_street_surfaces.game.json"
const CURB_PATH := "res://data/urbis/bourse_curb_source_policy.game.json"
const TARGET_ID := "https://databrussels.be/id/streetsurface/22358"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_PARVIS_PROPORTIONS_FAIL: %s" % message)
    quit(1)

func _json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    return parsed as Dictionary

func _vector2(raw: Variant) -> Vector2:
    if typeof(raw) != TYPE_ARRAY:
        return Vector2.ZERO
    var values := raw as Array
    if values.size() != 2:
        return Vector2.ZERO
    return Vector2(float(values[0]), float(values[1]))

func _run() -> void:
    var evidence := _json(EVIDENCE_PATH)
    if evidence.is_empty():
        _fail("proportion evidence is missing or invalid")
        return
    if str(evidence.get("schema", "")) != "grand-bruxelles-bourse-parvis-proportions-evidence-v1":
        _fail("unsupported evidence schema")
        return
    if bool(evidence.get("runtime_approved", true)) or bool(evidence.get("realism_complete", true)):
        _fail("proportion lot must remain unapproved before human gate")
        return

    var target: Dictionary = evidence.get("target_surface", {})
    if str(target.get("inspire_id", "")) != TARGET_ID:
        _fail("target StreetSurface is not 22358")
        return
    if not bool(target.get("source_geometry_must_remain_unchanged", false)):
        _fail("source geometry immutability is not locked")
        return

    var candidate: Dictionary = evidence.get("qa_candidate", {})
    var axis := _vector2(candidate.get("axis_unit_xz", []))
    var translation := _vector2(candidate.get("translation_xz_m", []))
    if not is_equal_approx(float(candidate.get("translation_m", -1.0)), 1.8):
        _fail("candidate translation is not exactly 1.8 m")
        return
    if abs(axis.length() - 1.0) > 0.000001:
        _fail("stored camera axis is not normalized")
        return
    if abs(translation.length() - 1.8) > 0.000001:
        _fail("stored candidate translation vector is not 1.8 m")
        return
    if abs(translation.dot(axis) - 1.8) > 0.000001:
        _fail("candidate translation is not +1.8 m along the stored camera axis")
        return
    if bool(candidate.get("runtime_promotion_allowed", true)):
        _fail("QA candidate must not permit runtime promotion")
        return

    var camera := _json(CAMERA_PATH)
    var project_transform: Dictionary = camera.get("project_transform", {})
    var hero_witness: Dictionary = camera.get("hero_witness", {})
    var camera_xz := _vector2(project_transform.get("game_camera_x_z_m", []))
    var hero_xz := _vector2(hero_witness.get("hero_bbox_center_game_x_z_m", []))
    var recomputed_axis := camera_xz.direction_to(hero_xz)
    if recomputed_axis.distance_to(axis) > 0.000001:
        _fail("stored candidate axis no longer matches source-backed geotagged camera/hero evidence")
        return

    var surfaces := _json(SURFACE_PATH)
    var found_target := false
    for raw_surface: Variant in surfaces.get("surfaces", []):
        if typeof(raw_surface) != TYPE_DICTIONARY:
            continue
        var surface := raw_surface as Dictionary
        if str(surface.get("inspire_id", "")) == TARGET_ID:
            found_target = true
            if int(surface.get("level", 999)) != 0:
                _fail("22358 is not LVL=0")
                return
            var rings: Array = surface.get("world_rings_xz", [])
            if rings.size() != 1 or (rings[0] as Array).size() < 4:
                _fail("22358 source world polygon is invalid")
                return
    if not found_target:
        _fail("source-locked 22358 is missing from runtime data")
        return

    var curb := _json(CURB_PATH)
    var decision: Dictionary = curb.get("decision", {})
    if bool(decision.get("vertical_extrusion_allowed", true)):
        _fail("curb policy unexpectedly permits vertical extrusion")
        return
    if bool(decision.get("curb_elevation_resolved", true)):
        _fail("curb elevation must remain unresolved")
        return

    var gate: Dictionary = evidence.get("gate", {})
    if str(gate.get("human_verdict", "")) != "pending":
        _fail("human gate must remain pending in this lot")
        return

    print("BOURSE_PARVIS_PROPORTIONS_TEST_OK: target=22358 shift=1.8m gate=pending")
    quit(0)
