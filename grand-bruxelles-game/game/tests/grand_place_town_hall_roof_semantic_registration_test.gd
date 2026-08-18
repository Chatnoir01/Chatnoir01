extends SceneTree

const CONTRACT_PATH := "res://data/qa/grand_place_town_hall_roof_semantic_registration.json"
const PRODUCTION_BASE := "6b165d44ab4bd8fa1cc61ef70e040ccf04b7906a"
const VERTEX_TOLERANCE_M := 0.001
const SPAN_TOLERANCE_M := 0.0001

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_TOWN_HALL_ROOF_SEMANTIC_FAIL: " + message)
    quit(1)

func _json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}

func _v3(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.INF
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))

func _short_id(raw: Variant) -> String:
    return str(raw).rsplit("/", false, 1)[-1]

func _find_face(faces: Array, full_id: String) -> Dictionary:
    var wanted := _short_id(full_id)
    for raw_face: Variant in faces:
        if typeof(raw_face) == TYPE_DICTIONARY:
            var face := raw_face as Dictionary
            if _short_id(face.get("id", "")) == wanted:
                return face
    return {}

func _face_has_vertex(face: Dictionary, point: Vector3) -> bool:
    for raw_triangle: Variant in face.get("triangles", []):
        if typeof(raw_triangle) != TYPE_ARRAY:
            continue
        for raw_vertex: Variant in raw_triangle:
            var vertex := _v3(raw_vertex)
            if vertex.is_finite() and vertex.distance_to(point) <= VERTEX_TOLERANCE_M:
                return true
    return false

func _chain_span(points: Array) -> float:
    if points.size() < 2:
        return 0.0
    var span := 0.0
    for index: int in range(points.size() - 1):
        var a := _v3(points[index])
        var b := _v3(points[index + 1])
        span += Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
    return span

func _run() -> void:
    var contract := _json(CONTRACT_PATH)
    if str(contract.get("schema", "")) != "grand-bruxelles-town-hall-roof-semantic-registration-v1":
        _fail("semantic registration contract missing or schema drift")
        return
    if str(contract.get("production_base", "")) != PRODUCTION_BASE:
        _fail("production base drift")
        return

    var decision: Dictionary = contract.get("decision", {})
    if not bool(decision.get("roof_plane_semantic_owner_resolved", false)):
        _fail("roof semantic owner must be explicitly resolved")
        return
    for key: String in ["runtime_changed", "geometry_changed", "material_changed", "official_vertices_changed", "dormers_authored", "implementation_authorized", "visual_candidate_approved", "realism_complete"]:
        if bool(decision.get(key, true)):
            _fail("fail-closed decision drift: " + key)
            return

    var target: Dictionary = contract.get("target", {})
    var geometry := _json(str(target.get("official_geometry_path", "")))
    if geometry.is_empty():
        _fail("official geometry missing")
        return
    var source: Dictionary = geometry.get("source", {})
    if str(source.get("building_2d_id", "")) != str(target.get("urbis_building_id", "")):
        _fail("official building identity drift")
        return
    if str(source.get("package_sha256", "")) != str(target.get("official_package_sha256", "")):
        _fail("official UrbIS package digest drift")
        return

    var faces: Array = geometry.get("faces", [])
    var roof := _find_face(faces, str(target.get("roof_face_id", "")))
    if roof.is_empty() or str(roof.get("type", "")) != "ROOFSURFACE":
        _fail("registered roof face missing or not ROOFSURFACE")
        return

    var wall_ids: Array = target.get("shared_gallery_wall_face_ids", [])
    if wall_ids.size() != 2:
        _fail("right-gallery wall chain must remain exactly two faces")
        return
    var wall_a := _find_face(faces, str(wall_ids[0]))
    var wall_b := _find_face(faces, str(wall_ids[1]))
    if wall_a.is_empty() or wall_b.is_empty() or str(wall_a.get("type", "")) != "WALLSURFACE" or str(wall_b.get("type", "")) != "WALLSURFACE":
        _fail("registered gallery wall faces missing or wrong type")
        return

    var eave_points: Array = target.get("shared_eave_points", [])
    if eave_points.size() != int(target.get("shared_eave_point_count", 0)) or eave_points.size() != 3:
        _fail("shared eave point contract drift")
        return
    var p0 := _v3(eave_points[0])
    var p1 := _v3(eave_points[1])
    var p2 := _v3(eave_points[2])
    for point: Vector3 in [p0, p1, p2]:
        if not point.is_finite() or not _face_has_vertex(roof, point):
            _fail("roof face does not contain required shared eave vertex: %s" % point)
            return
    if not _face_has_vertex(wall_a, p0) or not _face_has_vertex(wall_a, p1):
        _fail("first gallery wall top edge does not match roof eave")
        return
    if not _face_has_vertex(wall_b, p1) or not _face_has_vertex(wall_b, p2):
        _fail("second gallery wall top edge does not match roof eave")
        return

    var measured_span := _chain_span(eave_points)
    var expected_span := float(target.get("shared_eave_span_m", 0.0))
    if absf(measured_span - expected_span) > SPAN_TOLERANCE_M:
        _fail("shared roof/gallery eave span drift: %.12f vs %.12f" % [measured_span, expected_span])
        return

    var existing: Dictionary = contract.get("existing_registration", {})
    var gallery := _json(str(existing.get("right_gallery_contract_path", "")))
    if str(gallery.get("schema", "")) != "grand-bruxelles-town-hall-right-gallery-v2":
        _fail("shipped right-gallery registration missing")
        return
    var gallery_target: Dictionary = gallery.get("target", {})
    var registered_wall_ids: Array = gallery_target.get("face_ids", [])
    if registered_wall_ids != wall_ids:
        _fail("roof adjacency does not match shipped right-gallery face chain")
        return
    if absf(float(gallery_target.get("official_chain_span_m", 0.0)) - measured_span) > SPAN_TOLERANCE_M:
        _fail("roof eave span does not match shipped B1500 gallery span")
        return
    var heritage_sources: Dictionary = gallery.get("heritage_sources", {})
    var b1500: Dictionary = heritage_sources.get("kcml_b1500", {})
    if str(b1500.get("scope_text", "")) != str(existing.get("expected_scope_text", "")):
        _fail("B1500 right-of-tower semantic scope drift")
        return

    var roof_identity := _json(str(existing.get("roof_material_identity_path", "")))
    var presentation: Dictionary = roof_identity.get("presentation_contract", {})
    if bool(presentation.get("dormers_authored", true)):
        _fail("existing roof identity unexpectedly claims dormers are authored")
        return
    var heritage_scope: Dictionary = contract.get("heritage_scope", {})
    if int(heritage_scope.get("dormer_row_count_building_scope", 0)) != 4:
        _fail("building/wing-level four-row heritage fact drift")
        return
    for key: String in ["dormer_rows_assigned_to_face", "dormer_positions_resolved", "dormer_dimensions_resolved", "tower_spire_detail_resolved"]:
        if bool(heritage_scope.get(key, true)):
            _fail("unsupported detail was promoted: " + key)
            return

    print("GRAND_PLACE_TOWN_HALL_ROOF_SEMANTIC_OK face=%s walls=%s+%s span=%.12f scope=%s dormers_fail_closed=true" % [
        _short_id(target.get("roof_face_id", "")),
        _short_id(wall_ids[0]),
        _short_id(wall_ids[1]),
        measured_span,
        str(target.get("semantic_scope", ""))
    ])
    quit(0)
